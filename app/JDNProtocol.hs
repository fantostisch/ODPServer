{-# LANGUAGE OverloadedStrings #-}

module JDNProtocol
  ( webSocketConnectionOptions,
    secWebSocketProtocol,
    ping,
    pong,
    getFunction,
    parseMessage,
    PlayerUpdate (..),
    idFromPlayerJoined,
    idFromPlayerLeft,
    idFromPlayerKicked,
  )
where

import Data.Aeson ((.:))
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as B
import Data.Function ((&))
import Data.Functor ((<&>))
import Data.Text (Text)
import qualified Network.WebSockets as WS

data PlayerUpdate = PlayerJoined | PlayerLeft | PlayerKicked

webSocketConnectionOptions :: WS.ConnectionOptions
webSocketConnectionOptions =
  WS.defaultConnectionOptions
    { WS.connectionCompressionOptions = WS.PermessageDeflateCompression WS.defaultPermessageDeflate
    }

--todo: use protocol specified by client instead of hardcoding protocol
secWebSocketProtocol :: BS.ByteString
secWebSocketProtocol = "screen.justdancenow.com"

ping :: BS.ByteString
ping = "000f{\"func\":\"ping\"}"

pong :: BS.ByteString
pong = "000f{\"func\":\"pong\"}"

parseFunc :: BS.ByteString -> Maybe PlayerUpdate
parseFunc "playerJoined" = Just PlayerJoined
parseFunc "playerLeft" = Just PlayerLeft
parseFunc "playerKicked" = Just PlayerKicked
parseFunc _ = Nothing

extractFunctionString :: BS.ByteString -> BS.ByteString
extractFunctionString msg = C.takeWhile (/= '"') (BS.drop (length ("00h7{\"func\":\"" :: String)) msg)

getFunction :: BS.ByteString -> Maybe PlayerUpdate
getFunction = extractFunctionString <&> parseFunc

parseMessage :: C.ByteString -> (C.ByteString, Maybe Aeson.Object)
parseMessage msg = (prefix, parseJSON $ B.fromStrict msgNoPrefix)
  where
    prefixLength = length ("002e" :: String) --todo: do not specify String (also on other places)
    msgNoPrefix = BS.drop prefixLength msg
    prefix = BS.take prefixLength msg

parseJSON :: B.ByteString -> Maybe Aeson.Object
parseJSON = Aeson.decode

idFromPlayerJoined :: C.ByteString -> Maybe Text
idFromPlayerJoined msg =
  JDNProtocol.parseMessage msg
    & snd
    >>= parseMaybe
      ( \obj -> do
          newPlayer <- obj .: "newPlayer"
          newPlayer .: "id"
      )

idFromPlayerLeft :: C.ByteString -> Maybe Text
idFromPlayerLeft msg =
  JDNProtocol.parseMessage msg
    & snd
    >>= parseMaybe
      (.: "playerID") --todo: what is the difference between playerID and controller?

idFromPlayerKicked :: C.ByteString -> Maybe Text
idFromPlayerKicked msg =
  JDNProtocol.parseMessage msg
    & snd
    >>= parseMaybe
      (.: "playerID") --todo: what is the difference between playerID and controller?
