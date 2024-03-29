{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import qualified Characters
import Control.Concurrent (MVar, ThreadId, forkFinally, killThread, myThreadId)
import qualified Control.Concurrent.MVar as MVar
import Control.Concurrent.STM (TVar, atomically, retry)
import qualified Control.Concurrent.STM.TChan as TChan
import qualified Control.Concurrent.STM.TVar as TVar
import Control.Exception (try)
import Control.Exception.Base (SomeException)
import Control.Monad (forever)
import Data.Aeson (Object, eitherDecode, encode)
import qualified Data.Aeson.Key as AKey
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Types (Value (..), parseMaybe, (.:))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as B
import qualified Data.ByteString.Search as BSS
import Data.Either.Combinators (mapLeft)
import Data.Function ((&))
import Data.Functor (($>), (<&>))
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import Data.String (fromString)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import qualified Data.Tuple as Tuple
import Data.Void (Void, absurd)
import Debug
import GHC.Conc (ThreadStatus (..))
import qualified GHC.Conc as Conc
import JDNProtocol (PlayerUpdate (..))
import qualified JDNProtocol
import JDNWSURL (JDNWSURL)
import qualified JDNWSURL
import Network.HTTP.Simple (Response, getResponseBody, httpJSON)
import Network.HTTP.Types (status200, status404)
import qualified Network.URL as URL
import Network.Wai as Wai
  ( Application,
    Request (pathInfo, requestHeaderHost),
    Response,
    responseLBS,
  )
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Handler.WebSockets as WaiWS
import qualified Network.WebSockets as WS
import ODPClient
import ODPException
import Player (Player (..))
import Room (ODPChannel)
import qualified Room
import Rooms (Rooms)
import System.Random.Stateful
import Utils
import WSURLData (WSURLData)
import qualified WSURLData
import qualified Wuss

main :: IO ()
main = do
  let host = "localhost"
  let port = 32623
  putStrLn $ "Starting on http://" ++ host ++ ":" ++ show port
  state <- atomically $ TVar.newTVar Map.empty
  Warp.runSettings
    (Warp.setHost (fromString host) $ Warp.setPort port Warp.defaultSettings)
    $ WaiWS.websocketsOr JDNProtocol.webSocketConnectionOptions (application state) httpApp

httpApp :: Wai.Application
httpApp request respond = do
  let path = request & pathInfo
  response <- case path of
    -- /v1/query is used by extension <= v1.1.0, here for backward compatibility
    ["v1", "query", odpClientDataText] -> query request odpClientDataText
    ["about"] -> pure $ responseLBS status200 [] "{\"name\":\"OnlineDanceParty\",\"supported\":[1]}"
    _ -> pure $ responseLBS status404 [] "Not found"
  respond response

getJSONString :: AKey.Key -> Object -> Maybe Text
getJSONString key json = flip parseMaybe json $ \obj -> do
  obj .: key

query :: Wai.Request -> Text -> IO Wai.Response
query request odpClientDataText = do
  odpClientData <-
    (decode'' odpClientDataText :: Maybe Object)
      & orElseThrowMaybe (InvalidRequest "Could not decode client data")

  -- todo: use aeson directly?
  -- todo: send original user agent? define our own user agent? currently no user agent is send
  -- todo: what if call fails? --todo: handle non 200 response
  response <- httpJSON "https://justdancenow.com/query" :: IO (Network.HTTP.Simple.Response Object)
  let responseBody = response & getResponseBody

  let wsURLKey = AKey.fromText "wsUrl"
  wsURL <- responseBody & getJSONString wsURLKey & orElseThrowMaybe (JDNCommunicationError "Could not get wsUrl")

  let wsURLData =
        Object
          ( KM.fromList
              [ ("originalWSURL", String wsURL),
                ("odpClient", Object odpClientData)
              ]
          )

  host <- request & requestHeaderHost & orElseThrowMaybe (InvalidRequest "No host header")
  url <- "wss://" <> host <> "/" <> B.toStrict (encode wsURLData) & decodeUtf8' & orElseThrowEither
  let modifiedResponse = responseBody & KM.insert wsURLKey (String url)

  pure $
    responseLBS
      status200
      [ ("Access-Control-Allow-Origin", "https://justdancenow.com"),
        ("Content-Type", "application/json; charset=utf-8")
      ]
      (encode modifiedResponse)

removePlayerFromList :: Text -> [Player] -> [Player]
removePlayerFromList playerID = filter (\p -> Player.id p /= playerID)

updatePlayers :: PlayerUpdate -> BS.ByteString -> [Player] -> [Player]
updatePlayers (PlayerJoined playerID) message players =
  Player
    { Player.id = playerID,
      Player.playerJoined = message
    }
    : players
updatePlayers (PlayerLeft playerID) _ players =
  removePlayerFromList playerID players
updatePlayers (PlayerKicked playerID) _ players =
  removePlayerFromList playerID players

jdnClientApp :: ODPChannel -> ODPChannel -> TVar [Player] -> WS.ClientApp ()
jdnClientApp toJDN fromJDN tPlayers conn = do
  replaceIDsTVar <- atomically $ TVar.newTVar []

  let replaceInMessage = List.foldl' (\m (o, r) -> B.toStrict (BSS.replace o r m))

  sendingToJDNThread <-
    forkFinally
      ( forever $ do
          originalMsg <- atomically $ TChan.readTChan toJDN
          replaceIDs <- TVar.readTVarIO replaceIDsTVar <&> (<&> Tuple.swap)
          let msg = replaceInMessage originalMsg replaceIDs
          debug $ putStrLn $ "Sending message to JDN: " ++ show msg
          WS.sendTextData conn msg
      )
      ( \(result :: Either SomeException Void) -> do
          debug $ putStrLn $ "Sending to JDN thread ended: " ++ show result
          -- todo: kill sending thread, if no one reads toJDN channel the messages will pile up in memory
      )

  err <-
    ( try
        ( forever $ do
            let removeIDFromList playerID = atomically $ TVar.modifyTVar replaceIDsTVar (List.filter (\(o, _) -> o /= encodeUtf8 playerID))
            originalMsg <- WS.receiveData conn
            _ <- debug $ putStrLn $ "Recevied message from JDN: " ++ show originalMsg
            let playerUpdate = JDNProtocol.parsePlayerUpdate originalMsg
            case playerUpdate of
              Just (PlayerJoined originalID) -> do
                randomGen <- newStdGen
                let replaceID = C.pack $ randomString randomGen Characters.aToZLowerUpperNumeric (Text.length originalID)
                atomically $ TVar.modifyTVar replaceIDsTVar (List.insert (encodeUtf8 originalID, replaceID))
              _ -> pure ()
            replaceIDs <- TVar.readTVarIO replaceIDsTVar
            let msg = replaceInMessage originalMsg replaceIDs
            -- todo: if no one reads these messages they will pile up in memory
            atomically $ TChan.writeTChan fromJDN msg
            case playerUpdate of
              Just (PlayerLeft originalID) -> removeIDFromList originalID
              Just (PlayerKicked originalID) -> removeIDFromList originalID
              _ -> pure ()
            case playerUpdate of
              Just f -> atomically $ TVar.modifyTVar' tPlayers (updatePlayers f msg)
              Nothing -> pure ()
        ) ::
        IO (Either SomeException Void)
      )
      <&> either Prelude.id absurd

  debug $ putStrLn ("Receiving jdnClient ended: " ++ show err)
  killThread sendingToJDNThread

-- todo: kill this thread and remove room when there are no hosts and no followers
createJDNThread :: JDNWSURL -> ODPChannel -> ODPChannel -> TVar Rooms -> HostID -> TVar [Player] -> IO ThreadId
createJDNThread originalWSURL toJDN fromJDN tRooms hostId tPlayers =
  forkFinally
    ( Wuss.runSecureClientWith
        (JDNWSURL.host originalWSURL)
        443
        (JDNWSURL.pathAndParams originalWSURL)
        JDNProtocol.webSocketConnectionOptions
        [ ("Origin", "https://justdancenow.com"),
          ("Sec-WebSocket-Protocol", JDNProtocol.secWebSocketProtocol)
        ]
        (jdnClientApp toJDN fromJDN tPlayers)
    )
    ( \(result :: Either SomeException ()) -> do
        debug $ putStrLn $ "jdnClientApp ended: " ++ show result
        roomMaybe <- atomically $ do
          rooms <- TVar.readTVar tRooms
          let roomMaybe = Map.lookup hostId rooms
          TVar.writeTVar tRooms (Map.delete hostId rooms)
          pure roomMaybe
        case roomMaybe of
          Nothing -> putStrLn "Warning: trying to delete non existing room"
          Just room -> do
            debug $ putStrLn "Killing host thread"
            killThread $ Room.hostToJDNThread room
            debug $ putStrLn "Killing followers"
            mapM_ killThread (Room.followerThreads room)
        debug $ putStrLn "jdnClientApp cleanup done"
    )

createHostToJDNChannelThread :: WS.Connection -> ODPChannel -> IO (ThreadId, MVar ())
createHostToJDNChannelThread conn toJDN = do
  mVar <- MVar.newEmptyMVar
  debug $ putStrLn "Creating host thread."
  threadId <-
    forkFinally
      ( do
          forever $
            do
              msg <- WS.receiveData conn
              debug $ putStrLn $ "Received message from host: " ++ show msg
              atomically $ TChan.writeTChan toJDN msg
      )
      ( \(result :: Either SomeException Void) -> do
          debug $ putStrLn $ "Host thread ended: " ++ show result
      )
  pure (threadId, mVar)

{- todo: if the sending thread of the host dies, the receiving end will think it is still a host and
 sender: web will not be replaced with sender: app -}
createJDNChannelToHostThread :: WS.Connection -> ODPChannel -> TVar Rooms -> HostID -> IO (ThreadId, MVar ())
createJDNChannelToHostThread conn fromJDN tRooms hostId = do
  mVar <- MVar.newEmptyMVar
  threadId <-
    forkFinally
      ( do
          chan <- atomically $ TChan.dupTChan fromJDN
          forever $ do
            msg <- atomically $ TChan.readTChan chan
            case msg of
              -- _ | msg == ping -> pure () --todo: let server send pong, ping pong should work even if host dies
              _ -> do
                _ <- debug $ putStrLn $ "Sending message to host: " ++ show msg
                WS.sendTextData conn msg
      )
      ( \(result :: Either SomeException Void) -> do
          MVar.putMVar mVar ()
          debug $ putStrLn $ "Host receiving thread ended: " ++ show result
          removeThreadFromFollowers tRooms hostId
      )
  pure (threadId, mVar)

sendInitialSate :: WS.Connection -> BS.ByteString -> TVar [Player] -> IO ()
sendInitialSate conn registerRoomResponse tPlayers = do
  WS.sendTextData conn registerRoomResponse
  players <- TVar.readTVarIO tPlayers
  mapM_ (WS.sendTextData conn . Player.playerJoined) players

removeThreadFromFollowers :: TVar Rooms -> HostID -> IO ()
removeThreadFromFollowers tRooms hostId = do
  threadId <- myThreadId
  atomically $ TVar.modifyTVar tRooms (Map.adjust (\r -> r {Room.followerThreads = List.delete threadId (Room.followerThreads r)}) hostId)

-- todo: warn user if there is no host
handleFollower :: Follower -> WS.Connection -> TVar Rooms -> IO (Either String (MVar ()))
handleFollower follower conn tRooms = do
  let hostId = ODPClient.hostToFollow follower
  (room, registerRoomResponse) <-
    atomically $
      TVar.readTVar tRooms
        <&> Map.lookup hostId
        >>= ( \case
                Nothing -> retry
                Just room -> pure (room, Room.registerRoomResponse room)
            )
  fromFollowerMVar <- MVar.newEmptyMVar
  threadId <-
    forkFinally
      ( do
          chan <- atomically $ TChan.dupTChan (Room.fromJDN room)
          _ <- WS.receiveData conn :: IO BS.ByteString -- wait for register room request
          _ <- sendInitialSate conn registerRoomResponse (Room.players room)
          forever $ do
            originalMsg <- atomically $ TChan.readTChan chan
            -- todo: do this calculation once, not for every follower
            let msg = case JDNProtocol.toJSON originalMsg of
                  (prefix, Just o) -> BS.append prefix (B.toStrict $ encode (Map.adjust (const "app") "sender" (KM.toMap o)))
                  (_, Nothing) -> originalMsg
            case msg of
              _ | msg == JDNProtocol.ping -> pure ()
              _ -> do
                debug $ putStrLn $ "Sending message to follower: " ++ show msg
                WS.sendTextData conn msg
      )
      ( \(result :: Either SomeException Void) -> do
          debug $ putStrLn $ "Follower thread ended: " ++ show result
          removeThreadFromFollowers tRooms hostId
          MVar.putMVar fromFollowerMVar ()
      )
  success <- atomically $ do
    rooms <- TVar.readTVar tRooms
    let maybeRoom = Map.lookup hostId rooms
    case maybeRoom of
      Nothing -> pure False
      Just roomToUpdate ->
        TVar.writeTVar tRooms (Map.insert hostId (roomToUpdate {Room.followerThreads = threadId : Room.followerThreads roomToUpdate}) rooms)
          $> True
  if success
    then pure ()
    else debug (putStrLn "Created follower thread for non existing room") >> killThread threadId
  pure $ Right fromFollowerMVar

threadRunning :: ThreadId -> IO Bool
threadRunning threadID =
  Conc.threadStatus threadID
    <&> ( \case
            ThreadRunning -> True
            ThreadBlocked _ -> True
            ThreadFinished -> False
            ThreadDied -> False
        )

handleHost :: Host -> JDNWSURL -> WS.Connection -> TVar Rooms -> IO (Either String (MVar (), MVar ()))
handleHost host originalWSURL wsConn tr = do
  let hostId = ODPClient.id host
  savedRoom <- TVar.readTVarIO tr <&> Map.lookup hostId

  running <- case savedRoom of
    Nothing -> pure False
    Just room -> room & Room.hostToJDNThread & threadRunning

  tPlayers <- case savedRoom of
    Nothing -> atomically $ TVar.newTVar []
    Just room -> pure $ Room.players room

  if running
    then pure $ Left "HostID already claimed."
    else do
      toJDN <- case savedRoom of
        Just room -> pure $ Room.toJDN room
        Nothing -> atomically TChan.newTChan
      fromJDN <- case savedRoom of
        Just room -> pure $ Room.fromJDN room
        Nothing -> atomically TChan.newTChan
      jdnThreadMaybe <- case savedRoom of
        Just _ -> pure Nothing
        Nothing -> Just <$> createJDNThread originalWSURL toJDN fromJDN tr hostId tPlayers

      registerRoomRequest <- WS.receiveData wsConn
      registerRoomResponse <- case savedRoom of
        Just room -> pure $ Room.registerRoomResponse room
        Nothing -> do
          _ <- atomically $ TChan.writeTChan toJDN registerRoomRequest
          debug $ putStrLn "Waiting for registerRoom response"
          atomically $ TChan.readTChan fromJDN
      debug $ putStrLn $ "Sending registerRoom response: " ++ C.unpack registerRoomResponse

      sendInitialSate wsConn registerRoomResponse tPlayers

      (hostToJDNThread, sendMVar) <- createHostToJDNChannelThread wsConn toJDN
      (jdnToHostThread, recvMVar) <- createJDNChannelToHostThread wsConn fromJDN tr hostId

      result <- atomically $ do
        rooms <- TVar.readTVar tr
        let savedRoom2 = Map.lookup hostId rooms
        if (savedRoom2 <&> (\r -> (Room.fromJDN r, Room.toJDN r, Room.hostToJDNThread r, Room.jdnThread r)))
          /= (savedRoom <&> (\r -> (Room.fromJDN r, Room.toJDN r, Room.hostToJDNThread r, Room.jdnThread r)))
          then pure $ Left $ "Room was changed for host: " ++ show hostId ++ "."
          else case savedRoom2 of
            Just room ->
              Right
                <$> TVar.writeTVar
                  tr
                  ( Map.insert
                      hostId
                      ( room
                          { Room.hostToJDNThread = hostToJDNThread,
                            Room.followerThreads = jdnToHostThread : Room.followerThreads room
                          }
                      )
                      rooms
                  )
            Nothing ->
              Right
                <$> TVar.writeTVar
                  tr
                  ( Map.insert
                      hostId
                      Room.Room
                        { Room.toJDN = toJDN,
                          Room.fromJDN = fromJDN,
                          Room.hostToJDNThread = hostToJDNThread,
                          Room.jdnThread = fromJust jdnThreadMaybe, -- todo: do not use fromJust
                          Room.registerRoomResponse = registerRoomResponse,
                          Room.players = tPlayers,
                          Room.followerThreads = [jdnToHostThread]
                        }
                      rooms
                  )

      case result of
        Left m -> do
          case jdnThreadMaybe of
            Nothing -> pure ()
            Just jdnThread -> killThread jdnThread
          _ <- killThread hostToJDNThread
          _ <- killThread jdnToHostThread
          _ <- debug $ putStrLn $ "Oops! " ++ m ++ " Trying again..."
          handleHost host originalWSURL wsConn tr
        Right _ -> pure $ Right (recvMVar, sendMVar)

application :: TVar Rooms -> WS.ServerApp
application tr pending = do
  let requestURLByteString = C.unpack $ WS.requestPath $ WS.pendingRequest pending
  requestURL <- requestURLByteString & URL.importURL & orElseThrowMaybe (InvalidRequest "Invalid URL.")
  let requestPath = requestURL & URL.url_path
  let json = take (length requestPath - length JDNWSURL.path) requestPath
  wsURLData <-
    (eitherDecode (B.fromStrict (C.pack json)) :: Either String WSURLData)
      & mapLeft InvalidRequest
      & orElseThrowEither

  wsConn <- WS.acceptRequestWith pending (WS.defaultAcceptRequest {WS.acceptSubprotocol = Just JDNProtocol.secWebSocketProtocol})
  -- todo: do we need a ping thread?
  -- todo: just dance also does ping?
  -- todo: check origin
  WS.withPingThread wsConn 30 (return ()) $ do
    case WSURLData.odpClient wsURLData of
      Host host -> do
        jdnWSURL <-
          JDNWSURL.newJDNWSURL
            (drop (length JDNWSURL.protocol + length ("://" :: String)) (WSURLData.originalWSURL wsURLData))
            (URL.url_params requestURL)
            & mapLeft InvalidRequest
            & orElseThrowEither
        handleHost host jdnWSURL wsConn tr
          >>= ( \case
                  Left err -> debug $ putStrLn err
                  Right (recvMVar, sendMVAr) -> MVar.takeMVar recvMVar >> MVar.takeMVar sendMVAr
              )
      Follower follower ->
        handleFollower follower wsConn tr
          >>= ( \case
                  Left err -> debug $ putStrLn err
                  Right mVar -> MVar.takeMVar mVar
              )
