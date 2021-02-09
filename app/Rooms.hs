module Rooms
  ( Rooms,
    new,
    Rooms.lookup,
    insert,
    adjust,
    delete,
  )
where

import Control.Concurrent.STM.TVar (TVar)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import ODPClient (HostID)
import Room

type Rooms = Map HostID (TVar Room) --todo: TVar of Room is not used, remove?

new :: Rooms
new = Map.empty

lookup :: HostID -> Rooms -> Maybe (TVar Room)
lookup = Map.lookup

insert :: HostID -> TVar Room -> Rooms -> Rooms
insert = Map.insert

adjust :: (TVar Room -> TVar Room) -> HostID -> Rooms -> Rooms
adjust = Map.adjust

delete :: HostID -> Rooms -> Rooms
delete = Map.delete
