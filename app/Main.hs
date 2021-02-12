{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Control.Concurrent (MVar, ThreadId, forkFinally, killThread, myThreadId)
import qualified Control.Concurrent.MVar as MVar
import Control.Concurrent.STM (TVar, atomically, retry)
import qualified Control.Concurrent.STM.TChan as TChan
import qualified Control.Concurrent.STM.TVar as TVar
import Control.Exception (try)
import Control.Exception.Base (SomeException)
import Control.Monad (forever)
import Data.Aeson (Object, eitherDecode, encode)
import Data.Aeson.Types (Value (..), parseMaybe, (.:))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as B
import Data.Either.Combinators (mapLeft)
import Data.Function ((&))
import Data.Functor (($>), (<&>))
import Data.HashMap.Strict (fromList)
import qualified Data.HashMap.Strict as HM
import qualified Data.HashSet as HS
import qualified Data.List as List
import Data.Maybe (fromJust)
import Data.Text (Text, unpack)
import Data.Text.Encoding (decodeUtf8')
import Data.Void (Void, absurd)
import Debug
import GHC.Conc (ThreadStatus (..))
import qualified GHC.Conc as Conc
import JDNProtocol (PlayerJoinedOrLeft (..))
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
import qualified Rooms
import Utils
import WSURLData (WSURLData)
import qualified WSURLData
import qualified Wuss

type WSHostsTVar = TVar (HS.HashSet String)

main :: IO ()
main = do
  let host = "localhost"
  let port = 32623
  putStrLn $ "Starting on http://" ++ host ++ ":" ++ show port
  state <- atomically $ TVar.newTVar Rooms.new
  allowedWSURLs <- atomically $ TVar.newTVar HS.empty
  Warp.runSettings
    (Warp.setHost "localhost" {- todo -} $ Warp.setPort port Warp.defaultSettings)
    $ WaiWS.websocketsOr JDNProtocol.webSocketConnectionOptions (application state allowedWSURLs) (httpApp allowedWSURLs)

httpApp :: WSHostsTVar -> Wai.Application
httpApp allowedWSURLs request respond = do
  let path = request & pathInfo
  response <- case path of
    ["v1", "query", odpClientDataText] -> query allowedWSURLs request odpClientDataText
    ["about"] -> pure $ responseLBS status200 [] "{\"name\":\"OnlineDanceParty\",\"supported\":[1]}"
    _ -> pure $ responseLBS status404 [] "Not found"
  respond response

getJSONString :: Text -> Object -> Maybe Text
getJSONString key json = flip parseMaybe json $ \obj -> do
  obj .: key

query :: WSHostsTVar -> Wai.Request -> Text -> IO Wai.Response
query allowedWSURLs request odpClientDataText = do
  odpClientData <-
    (decode'' odpClientDataText :: Maybe Object)
      & orElseThrowMaybe (InvalidRequest "Could not decode client data")

  -- todo: use aeson directly?
  -- todo: send original user agent? define our own user agent? currently no user agent is send
  -- todo: what if call fails? --todo: handle non 200 response
  response <- httpJSON "https://justdancenow.com/query" :: IO (Network.HTTP.Simple.Response Object)
  let responseBody = response & getResponseBody

  let wsURLKey = "wsUrl"
  wsURL <- responseBody & getJSONString wsURLKey & orElseThrowMaybe (JDNCommunicationError "Could not get wsUrl")

  let wsURLString = unpack wsURL
  _ <- atomically $ TVar.modifyTVar allowedWSURLs (HS.insert (drop (length ("wss://" :: String)) wsURLString))
  let wsURLData =
        Object
          ( fromList
              [ ("originalWSURL", String wsURL),
                ("odpClient", Object odpClientData)
              ]
          )

  host <- request & requestHeaderHost & orElseThrowMaybe (InvalidRequest "No host header")
  url <- "wss://" <> host <> "/" <> B.toStrict (encode wsURLData) & decodeUtf8' & orElseThrowEither
  let modifiedResponse = responseBody & HM.insert wsURLKey (String url)

  pure $
    responseLBS
      status200
      [ ("Access-Control-Allow-Origin", "https://justdancenow.com"),
        ("Content-Type", "application/json; charset=utf-8")
      ]
      (encode modifiedResponse)

updatePlayers :: PlayerJoinedOrLeft -> BS.ByteString -> [Player] -> Maybe [Player]
updatePlayers PlayerJoined message players =
  playerJoinedIDMaybe
    <&> ( \playerJoinedID ->
            Player
              { Player.id = playerJoinedID,
                Player.playerJoined = message
              } :
            players
        )
  where
    playerJoinedIDMaybe = JDNProtocol.idFromPlayerJoined message
updatePlayers PlayerLeft message players =
  playerLeftIDMaybe
    <&> ( \playerLeftID ->
            filter (\p -> Player.id p /= playerLeftID) players
        )
  where
    playerLeftIDMaybe = JDNProtocol.idFromPlayerLeft message

jdnClientApp :: ODPChannel -> ODPChannel -> TVar [Player] -> WS.ClientApp ()
jdnClientApp sendChannel receiveChannel tPlayers conn = do
  sendingThread <-
    forkFinally
      ( forever $ do
          msg <- atomically $ TChan.readTChan sendChannel
          debug $ putStrLn $ "Sending message to JDN: " ++ show msg
          WS.sendTextData conn msg
      )
      ( \(result :: Either SomeException Void) -> do
          debug $ putStrLn $ "Sending jdnClient ended: " ++ show result
          --todo: kill sending thread, if no one reads sendChannel the messages will pile up in memory
      )

  err <-
    ( try
        ( forever $ do
            msg <- WS.receiveData conn
            _ <- debug $ putStrLn $ "Recevied message from JDN: " ++ show msg
            case JDNProtocol.getFunction msg of
              Just f -> atomically $ do
                room <- TVar.readTVar tPlayers
                case updatePlayers f msg room of
                  Just updatedRoom -> TVar.writeTVar tPlayers updatedRoom
                  Nothing -> pure () --something is wrong, todo: log this
              Nothing -> pure ()
            atomically $ TChan.writeTChan receiveChannel msg
            --todo: if no one reads these messages they will pile up in memory
        ) ::
        IO (Either SomeException Void)
      )
      <&> either Prelude.id absurd

  debug $ putStrLn ("Receiving jdnClient ended: " ++ show err)
  killThread sendingThread

--todo: kill this thread and remove room when there are no hosts and no followers
createJDNThread :: JDNWSURL -> ODPChannel -> ODPChannel -> TVar Rooms -> HostID -> TVar [Player] -> IO ThreadId
createJDNThread originalWSURL sendChannel receiveChannel tRooms hostId tPlayers =
  forkFinally
    ( Wuss.runSecureClientWith
        (JDNWSURL.host originalWSURL)
        443
        (JDNWSURL.pathAndParams originalWSURL)
        JDNProtocol.webSocketConnectionOptions
        [ ("Origin", "https://justdancenow.com"),
          ("Sec-WebSocket-Protocol", JDNProtocol.secWebSocketProtocol)
        ]
        (jdnClientApp sendChannel receiveChannel tPlayers)
    )
    ( \(result :: Either SomeException ()) -> do
        debug $ putStrLn $ "jdnClientApp ended: " ++ show result
        roomMaybe <- atomically $ do
          rooms <- TVar.readTVar tRooms
          let roomMaybe = Rooms.lookup hostId rooms
          TVar.modifyTVar tRooms (Rooms.delete hostId)
          pure roomMaybe
        case roomMaybe of
          Nothing -> putStrLn "Warning: trying to delete non existing room"
          Just room -> do
            debug $ putStrLn "Killing host thread"
            killThread $ Room.hostThread room
            debug $ putStrLn "Killing followers"
            mapM_ killThread (Room.followerThreads room)
        debug $ putStrLn "jdnClientApp cleanup done"
    )

-- thread that sends from host to JDN
createSendToHostThread :: WS.Connection -> ODPChannel -> IO (ThreadId, MVar ())
createSendToHostThread conn sendChannel = do
  mVar <- MVar.newEmptyMVar
  debug $ putStrLn "Creating host thread."
  threadId <-
    forkFinally
      ( do
          forever $
            do
              msg <- WS.receiveData conn
              debug $ putStrLn $ "Received message from host: " ++ show msg
              atomically $ TChan.writeTChan sendChannel msg
      )
      ( \(result :: Either SomeException Void) -> do
          debug $ putStrLn $ "Host thread ended: " ++ show result
      )
  pure (threadId, mVar)

{- todo: if the sending thread of the host dies, the receiving end will think it is still a host and
 sender: web will not be replaced with sender: app -}
-- thread that receives from JDN and sends to the host
createReceiveFromHostThread :: WS.Connection -> ODPChannel -> TVar Rooms -> HostID -> IO (ThreadId, MVar ())
createReceiveFromHostThread conn recvChannel tRooms hostId = do
  mVar <- MVar.newEmptyMVar
  threadId <-
    forkFinally
      ( do
          chan <- atomically $ TChan.dupTChan recvChannel
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
  players <- atomically $ TVar.readTVar tPlayers
  mapM_ (WS.sendTextData conn . Player.playerJoined) players

removeThreadFromFollowers :: TVar Rooms -> HostID -> IO ()
removeThreadFromFollowers tRooms hostId = do
  threadId <- myThreadId
  atomically $ TVar.modifyTVar tRooms (Rooms.adjust (\r -> r {Room.followerThreads = List.delete threadId (Room.followerThreads r)}) hostId)

--todo: warn user if there is no host
handleFollower :: Follower -> WS.Connection -> TVar Rooms -> IO (Either String (MVar ()))
handleFollower follower conn tRooms = do
  let hostId = ODPClient.hostToFollow follower
  (room, registerRoomResponse) <-
    atomically $
      TVar.readTVar tRooms
        <&> Rooms.lookup hostId
        >>= ( \case
                Nothing -> retry
                Just room -> pure (room, Room.registerRoomResponse room)
            )
  receiveMVar <- MVar.newEmptyMVar
  threadId <-
    forkFinally
      ( do
          chan <- atomically $ TChan.dupTChan (Room.receiveChannel room)
          _ <- WS.receiveData conn :: IO BS.ByteString -- wait for register room request
          _ <- sendInitialSate conn registerRoomResponse (Room.players room)
          forever $ do
            originalMsg <- atomically $ TChan.readTChan chan
            --todo: do this calculation once, not for every follower
            let msg = case JDNProtocol.parseMessage originalMsg of
                  (prefix, Just o) -> BS.append prefix (B.toStrict $ encode (HM.adjust (const "app") "sender" o))
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
          MVar.putMVar receiveMVar ()
      )
  success <- atomically $ do
    rooms <- TVar.readTVar tRooms
    let maybeRoom = Rooms.lookup hostId rooms
    case maybeRoom of
      Nothing -> pure False
      Just room ->
        TVar.writeTVar tRooms (Rooms.insert hostId (room {Room.followerThreads = threadId : Room.followerThreads room}) rooms)
          $> True
  if success
    then pure ()
    else debug (putStrLn "Created follower thread for non existing room") >> killThread threadId
  pure $ Right receiveMVar

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
  let hostId = (ODPClient.id host)
  savedRoom <- atomically (TVar.readTVar tr) <&> Rooms.lookup hostId

  running <- case savedRoom of
    Nothing -> pure False
    Just room -> room & Room.hostThread & threadRunning

  tPlayers <- case savedRoom of
    Nothing -> atomically $ TVar.newTVar []
    Just room -> pure $ Room.players room

  if running
    then pure $ Left "HostID already claimed."
    else do
      sendChannel <- case savedRoom of
        Just room -> pure $ Room.sendChannel room
        Nothing -> atomically TChan.newTChan
      receiveChannel <- case savedRoom of
        Just room -> pure $ Room.receiveChannel room
        Nothing -> atomically TChan.newTChan
      jdnThreadMaybe <- case savedRoom of
        Just _ -> pure Nothing
        Nothing -> Just <$> createJDNThread originalWSURL sendChannel receiveChannel tr hostId tPlayers

      registerRoomRequest <- WS.receiveData wsConn
      registerRoomResponse <- case savedRoom of
        Just room -> pure $ Room.registerRoomResponse room
        Nothing -> do
          _ <- atomically $ TChan.writeTChan sendChannel registerRoomRequest
          debug $ putStrLn "Waiting for registerRoom response"
          atomically $ TChan.readTChan receiveChannel
      debug $ putStrLn $ "Sending registerRoom response: " ++ C.unpack registerRoomResponse

      sendInitialSate wsConn registerRoomResponse tPlayers

      (hostSendingThread, sendMVar) <- createSendToHostThread wsConn sendChannel
      (hostReceivingThread, recvMVar) <- createReceiveFromHostThread wsConn receiveChannel tr hostId

      result <- atomically $ do
        rooms <- TVar.readTVar tr
        let savedRoom2 = Rooms.lookup hostId rooms
        if (savedRoom2 <&> (\r -> (Room.receiveChannel r, Room.sendChannel r, Room.hostThread r, Room.jdnThread r)))
          /= (savedRoom <&> (\r -> (Room.receiveChannel r, Room.sendChannel r, Room.hostThread r, Room.jdnThread r)))
          then pure $ Left $ "Room was changed for host: " ++ show hostId ++ "."
          else case savedRoom2 of
            Just room ->
              Right
                <$> TVar.writeTVar
                  tr
                  ( Rooms.insert
                      hostId
                      ( room
                          { Room.hostThread = hostSendingThread,
                            Room.followerThreads = hostReceivingThread : Room.followerThreads room
                          }
                      )
                      rooms
                  )
            Nothing ->
              Right
                <$> TVar.writeTVar
                  tr
                  ( Rooms.insert
                      hostId
                      Room.Room
                        { Room.sendChannel = sendChannel,
                          Room.receiveChannel = receiveChannel,
                          Room.hostThread = hostSendingThread,
                          Room.jdnThread = fromJust jdnThreadMaybe, --todo: do not use fromJust
                          Room.registerRoomResponse = registerRoomResponse,
                          Room.players = tPlayers,
                          Room.followerThreads = [hostReceivingThread]
                        }
                      rooms
                  )

      case result of
        Left m -> do
          case jdnThreadMaybe of
            Nothing -> pure ()
            Just jdnThread -> killThread jdnThread
          _ <- killThread hostSendingThread
          _ <- killThread hostReceivingThread
          _ <- debug $ putStrLn $ "Oops! " ++ m ++ " Trying again..."
          handleHost host originalWSURL wsConn tr
        Right _ -> pure $ Right (recvMVar, sendMVar)

application :: TVar Rooms -> WSHostsTVar -> WS.ServerApp
application tr wsHostsTVar pending = do
  let requestURLByteString = C.unpack $ WS.requestPath $ WS.pendingRequest pending
  requestURL <- requestURLByteString & URL.importURL & orElseThrowMaybe (InvalidRequest "Invalid URL.")
  let requestPath = requestURL & URL.url_path
  let json = take (length requestPath - length JDNWSURL.path) requestPath
  wsURLData <-
    (eitherDecode (B.fromStrict (C.pack json)) :: Either String WSURLData)
      & mapLeft InvalidRequest
      & orElseThrowEither

  wsHosts <- atomically $ TVar.readTVar wsHostsTVar
  jdnWSURL <-
    JDNWSURL.newJDNWSURL
      wsHosts
      (drop (length JDNWSURL.protocol + length ("://" :: String)) (WSURLData.originalWSURL wsURLData))
      (URL.url_params requestURL)
      & mapLeft InvalidRequest
      & orElseThrowEither

  wsConn <- WS.acceptRequestWith pending (WS.defaultAcceptRequest {WS.acceptSubprotocol = Just JDNProtocol.secWebSocketProtocol})
  -- todo: do we need a ping thread?
  -- todo: just dance also does ping?
  -- todo: check origin
  WS.withPingThread wsConn 30 (return ()) $ do
    case WSURLData.odpClient wsURLData of
      Host host ->
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
