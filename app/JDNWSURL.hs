module JDNWSURL (newJDNWSURL, JDNWSURL, host, pathAndParams, protocol, port, path) where

import Data.HashSet (HashSet)
import qualified Data.HashSet as HS
import qualified Network.URL as URL

data JDNWSURL = JDNWSURL {host :: String, pathAndParams :: String} deriving (Show)

wssProtocol :: String
wssProtocol = "wss"

protocol :: String
protocol = wssProtocol

port :: Int
port = 433

path :: String
path = "/screen"

newJDNWSURL :: HashSet String -> String -> [(String, String)] -> Either String JDNWSURL
newJDNWSURL trustedHosts host params =
  if host `HS.member` trustedHosts
    then Right JDNWSURL {host = host, pathAndParams = path ++ URL.exportParams params}
    else Left $ "Untrusted host: " ++ host
