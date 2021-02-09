module Room (Room (..), ODPChannel, Player (..)) where

import Control.Concurrent
import Control.Concurrent.STM.TChan
import qualified Data.ByteString as BS
import Data.Text

type ODPChannel = TChan BS.ByteString

data Player = Player {id :: Text, playerJoined :: BS.ByteString} deriving (Eq)

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
