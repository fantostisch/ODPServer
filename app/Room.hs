module Room (Room (..), ODPChannel) where

import Control.Concurrent
import Control.Concurrent.STM.TChan
import qualified Data.ByteString as BS

type ODPChannel = TChan BS.ByteString

data Room = Room
  { receiveChannel :: ODPChannel,
    sendChannel :: ODPChannel,
    hostThread :: ThreadId,
    jdnThread :: ThreadId,
    registerRoomResponse :: BS.ByteString,
    followerThreads :: [ThreadId]
  }
  deriving (Eq)
