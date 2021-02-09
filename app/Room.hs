module Room (Room (..), ODPChannel) where

import Control.Concurrent
import Control.Concurrent.STM.TChan
import qualified Data.ByteString as BS
import Player (Player)

type ODPChannel = TChan BS.ByteString

data Room = Room
  { receiveChannel :: ODPChannel,
    sendChannel :: ODPChannel,
    hostThread :: ThreadId,
    jdnThread :: ThreadId,
    registerRoomResponse :: BS.ByteString,
    players :: [Player],
    followerThreads :: [ThreadId]
  }
  deriving (Eq)
