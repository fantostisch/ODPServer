{-# LANGUAGE DeriveGeneric #-}

module WSURLData
  ( WSURLData (..),
  )
where

import Data.Aeson (FromJSON)
import GHC.Generics
import ODPClient

data WSURLData = WSURLData {originalWSURL :: String, odpClient :: ODPClient} deriving (Generic, Show)

instance FromJSON WSURLData
