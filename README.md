# Online Dance Party Server

Server for [Online Dance Party](https://github.com/fantostisch/OnlineDanceParty).

## Using your own server

You can use dance.nickaquina.nl as server, but preferably you should host your own server. To deploy
your own server please read the [deployment documentation](doc/DEPLOYING.md).

## How does it work?

All players connect to this server instead of the Just Dance Now server, the websocket messages of
the host get forwarded to the Just Dance Now server. The messages of the other players are dropped.
The websocket messages of the Just Dance Now server are forwarded to all clients. Assets (HTML, CSS,
JS, music and video files) are downloaded directly from the Just Dance Now server and are not
relayed through this server.

## Development

[Install The Haskell Tool Stack](https://haskellstack.org)

### Setup

```sh
cp doc/Settings.example.hs app/Settings.hs
```

### Building and running

Build on every change:

```sh
make watch
```

Running:

```sh
make run
```

Running with stack traces:

```sh
make debug
```

### Testing

```sh
make test
```

### Development setup

Recommended IDE is [IntelliJ IDEA](https://www.jetbrains.com/idea/)
with [IntelliJ-Haskell](https://plugins.jetbrains.com/plugin/8258-intellij-haskell). Alternative
is [VSCodium](https://vscodium.com/)
with [Haskell Language Server](https://marketplace.visualstudio.com/items?itemName=haskell.haskell).

If IntelliSense breaks because the project does not compile, add some `undefined`'s to let the
project compile.

To view library documentation run:
`stack --open haddock`. If this command fails because the project does not compile,
use `stack --open haddock --only-dependencies`.

### Formatting

Please format all code using [ormolu](https://github.com/tweag/ormolu) and keep lines below 90 characters.

To install ormolu, run in this directory:
```bash
stack install ormolu-0.4.0.0
```

To run ormolu on all source files:
```bash
make format
```

## Documentation

Other documentation in:

* [doc/](doc/)

## License

**License**:  AGPL-3.0-or-later

```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
