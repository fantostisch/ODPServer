{-# LANGUAGE OverloadedStrings #-}

module JDNProtocol
  ( webSocketConnectionOptions,
    secWebSocketProtocol,
    ping,
    pong,
    parsePlayerUpdate,
    toJSON,
    PlayerUpdate (..),
  )
where

import Data.Aeson ((.:))
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (parseMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C
import qualified Data.ByteString.Lazy as B
import qualified Data.ByteString.UTF8 as BSU
import Data.Char (intToDigit)
import Data.Function ((&))
import Data.Text (Text)
import qualified Network.WebSockets as WS
import Numeric (showIntAtBase)
import Utils

type PlayerId = Text

data PlayerUpdate = PlayerJoined (Maybe PlayerId) | PlayerLeft (Maybe PlayerId) | PlayerKicked (Maybe PlayerId)

webSocketConnectionOptions :: WS.ConnectionOptions
webSocketConnectionOptions =
  WS.defaultConnectionOptions
    { WS.connectionCompressionOptions = WS.PermessageDeflateCompression WS.defaultPermessageDeflate
    }

-- todo: use protocol specified by client instead of hardcoding protocol
secWebSocketProtocol :: BS.ByteString
secWebSocketProtocol = "screen.justdancenow.com"

prefixMessage :: BS.ByteString -> BS.ByteString
prefixMessage message = BSU.fromString (padLeft 4 '0' (showIntAtBase 36 intToDigit (BSU.length message) "")) <> message

ping :: BS.ByteString
ping = prefixMessage "{\"func\":\"ping\"}"

pong :: BS.ByteString
pong = prefixMessage "{\"func\":\"pong\"}"

toJSON :: C.ByteString -> (C.ByteString, Maybe Aeson.Object)
toJSON msg = (prefix, Aeson.decode $ B.fromStrict msgNoPrefix)
  where
    prefixLength = length ("002e" :: String) -- todo: do not specify String (also on other places)
    msgNoPrefix = BS.drop prefixLength msg
    prefix = BS.take prefixLength msg

extractFunctionString :: BS.ByteString -> BS.ByteString
extractFunctionString msg = C.takeWhile (/= '"') (BS.drop (length ("00h7{\"func\":\"" :: String)) msg)

parsePlayerUpdate :: BS.ByteString -> Maybe PlayerUpdate
parsePlayerUpdate msg = case extractFunctionString msg of
  "playerJoined" ->
    Just $
      PlayerJoined
        ( parseJSON
            ( \obj -> do
                newPlayer <- obj .: "newPlayer"
                newPlayer .: "id"
            )
        )
  "playerLeft" -> Just $ PlayerLeft (parseJSON (.: "playerID")) -- todo: what is the difference between playerID and controller?
  "playerKicked" -> Just $ PlayerKicked (parseJSON (.: "playerID")) -- todo: what is the difference between playerID and controller?
  _ -> Nothing
  where
    parseJSON x =
      toJSON msg & snd
        >>= parseMaybe x
