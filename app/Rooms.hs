module Rooms
  ( Rooms,
    new,
    Rooms.lookup,
    insert,
    adjust,
    delete,
  )
where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import ODPClient (HostID)
import Room

type Rooms = Map HostID Room

new :: Rooms
new = Map.empty

lookup :: HostID -> Rooms -> Maybe Room
lookup = Map.lookup

insert :: HostID -> Room -> Rooms -> Rooms
insert = Map.insert

adjust :: (Room -> Room) -> HostID -> Rooms -> Rooms
adjust = Map.adjust

delete :: HostID -> Rooms -> Rooms
delete = Map.delete
