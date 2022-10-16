module Rooms
  ( Rooms,
  )
where

import Data.Map.Strict (Map)
import ODPClient (HostID)
import Room

type Rooms = Map HostID Room
