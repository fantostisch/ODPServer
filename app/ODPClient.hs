{-# LANGUAGE DeriveGeneric #-}

module ODPClient
  ( ODPClient (..),
    HostID,
    Host (..),
    Follower (..),
  )
where

import Data.Aeson (FromJSON)
import Data.Text (Text)
import GHC.Generics

data ODPClient = Host Host | Follower Follower deriving (Generic, Show)

type HostID = Text

newtype Host = HostC {id :: HostID} deriving (Generic, Show)

newtype Follower = FollowerC {hostToFollow :: HostID} deriving (Generic, Show)

instance FromJSON ODPClient

instance FromJSON Host

instance FromJSON Follower
