module Room (Room (..), ODPChannel) where

import Control.Concurrent
import Control.Concurrent.STM (TVar)
import Control.Concurrent.STM.TChan
import qualified Data.ByteString as BS
import Player (Player)

type ODPChannel = TChan BS.ByteString

data Room = Room
  { fromJDN :: ODPChannel,
    toJDN :: ODPChannel,
    hostToJDNThread :: ThreadId,
    jdnThread :: ThreadId,
    registerRoomResponse :: BS.ByteString,
    players :: TVar [Player],
    followerThreads :: [ThreadId]
  }
  deriving (Eq)
