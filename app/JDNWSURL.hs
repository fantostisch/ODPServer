module JDNWSURL (newJDNWSURL, JDNWSURL, host, pathAndParams, protocol, port, path) where

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

ireHost :: String
ireHost = "ire-prod-drs.justdancenow.com"

locationLength :: Int
locationLength = length "ire"

allowedLocationCharacters :: [Char]
allowedLocationCharacters = "abcdefghijklmnopqrstuvwxyz"

isValidJDNWSHost :: String -> Bool
isValidJDNWSHost url =
  let (location, remaining) = splitAt locationLength url
      correctLocation = all (`elem` allowedLocationCharacters) location
      correctRemaining = remaining == drop locationLength ireHost
   in correctRemaining && correctLocation

newJDNWSURL :: String -> [(String, String)] -> Either String JDNWSURL
newJDNWSURL host params =
  if isValidJDNWSHost host
    then Right JDNWSURL {host = host, pathAndParams = path ++ URL.exportParams params}
    else Left $ "Untrusted host: " ++ host
