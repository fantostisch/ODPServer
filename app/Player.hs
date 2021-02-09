module Player
  ( Player (..),
  )
where

import qualified Data.ByteString as BS
import Data.Text

data Player = Player {id :: Text, playerJoined :: BS.ByteString} deriving (Eq)
