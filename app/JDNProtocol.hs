{-# LANGUAGE OverloadedStrings #-}

module JDNProtocol
  ( webSocketConnectionOptions,
    secWebSocketProtocol,
    ping,
    pong,
    playerJoinedFunc,
    playerLeftFunc,
    getFunction,
    parseMessage,
  )
where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as B
import qualified Network.WebSockets as WS

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

playerJoinedFunc :: BS.ByteString
playerJoinedFunc = "playerJoined"

playerLeftFunc :: BS.ByteString
playerLeftFunc = "playerLeft"

getFunction :: BS.ByteString -> BS.ByteString
getFunction msg = C.takeWhile (/= '"') (BS.drop (length ("00h7{\"func\":\"" :: String)) msg)

parseMessage :: C.ByteString -> (C.ByteString, Maybe Aeson.Object)
parseMessage msg = (prefix, parseJSON $ B.fromStrict msgNoPrefix)
  where
    prefixLength = length ("002e" :: String) --todo: do not specify String (also on other places)
    msgNoPrefix = BS.drop prefixLength msg
    prefix = BS.take prefixLength msg

parseJSON :: B.ByteString -> Maybe Aeson.Object
parseJSON = Aeson.decode
