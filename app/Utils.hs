module Utils
  ( orElseThrowMaybe,
    orElseThrowEither,
    decode'',
    padLeft,
  )
where

import Control.Exception.Base (Exception, throwIO)
import Data.Aeson (FromJSON, decode)
import Data.ByteString.Builder (toLazyByteString)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8Builder)

orElseThrowMaybe :: Exception e => e -> Maybe a -> IO a
orElseThrowMaybe b Nothing = throwIO b
orElseThrowMaybe _ (Just a) = pure a

orElseThrowEither :: Exception e => Either e b -> IO b
orElseThrowEither (Left e) = throwIO e
orElseThrowEither (Right b) = pure b

decode'' :: FromJSON a => Text -> Maybe a
decode'' = decode . toLazyByteString . encodeUtf8Builder

padLeft :: Int -> a -> [a] -> [a]
padLeft n x xs = replicate (n - length xs) x ++ xs
