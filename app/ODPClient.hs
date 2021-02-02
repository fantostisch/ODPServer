{-# LANGUAGE DeriveGeneric #-}

module ODPClient
  ( ODPClient (..),
    HostID,
    Host (..),
    Follower (..),
  )
where

import Data.Aeson (FromJSON, ToJSON (..), defaultOptions, genericToEncoding)
import Data.Text (Text)
import GHC.Generics

data ODPClient = Host Host | Follower Follower deriving (Generic, Show)

instance FromJSON ODPClient

instance ToJSON ODPClient where
  toEncoding = genericToEncoding defaultOptions

type HostID = Text

newtype Host = HostC {id :: HostID} deriving (Generic, Show)

instance FromJSON Host

instance ToJSON Host where
  toEncoding = genericToEncoding defaultOptions

newtype Follower = FollowerC {hostToFollow :: HostID} deriving (Generic, Show)

instance FromJSON Follower

instance ToJSON Follower where
  toEncoding = genericToEncoding defaultOptions
