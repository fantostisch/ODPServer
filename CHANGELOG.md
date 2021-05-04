# Changelog for Online Dance Party Server

## [1.2.1]
* Allow locations with an `x`.

## [1.2.0]
* Allow specific websocket urls instead of only the ones the server receives from JDN, necessary to fix
  [dance room does not exist error](https://github.com/fantostisch/OnlineDanceParty/issues/1).

## [1.1.1]

* Followers that join after a player is kicked will now not see this player anymore.

## [1.1.0]

* Followers will now see all players, even if the follower joined the room after those players
  joined.
* Followers can now join a room before the hosts does. Followers will see a loading animation until
  the host joins.
* Connections with the host and followers will now close when the connection with JDN closes.

## [1.0.0]

Initial release
