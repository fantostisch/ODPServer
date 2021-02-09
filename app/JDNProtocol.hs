{-# LANGUAGE OverloadedStrings #-}

module JDNProtocol
  ( webSocketConnectionOptions,
    secWebSocketProtocol,
    ping,
    pong,
    playerJoinedFunc,
    playerLeftFunc,
    getFunction,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
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
