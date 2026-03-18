# Multiplayer Game Shell — Design Spec

## Overview

A browser-based multiplayer game platform built with Godot 4.x. A "shell" provides game selection, room-based matchmaking, and WebSocket networking. Individual games are Godot scenes that plug into the shell via a common interface. The first game is tic-tac-toe for two players.

**Goal**: Two players load the game in their browsers, connect to each other via room code, and play tic-tac-toe. The architecture supports adding more multiplayer games without changing the server or shell networking.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Matchmaking | Room codes (4-char alphanumeric) | Simplest for "play with a friend" co-op |
| Networking | WebSocket relay (not WebRTC) | Pure GDScript, no JS interop, trivial for turn-based games |
| Godot version | 4.x (latest stable) | Modern API, solid web export |
| Game loading | Scene-based with common interface | Simple, no server changes per game |
| Relay server | Node.js | Lightest setup, first-class WebSocket support |
| State authority | Host player (room creator) | No server game logic, server stays dumb |
| UI | Minimal/functional | Experiment platform — architecture over polish |

## System Architecture

```
[Browser: Godot HTML5] <--WebSocket--> [Node.js Relay Server] <--WebSocket--> [Browser: Godot HTML5]
```

Three components:

1. **Relay Server** — manages rooms (create/join by code), forwards JSON messages between peers. No game logic. ~100 lines of Node.js.
2. **Godot Client** — exported as HTML5. Contains the game shell (UI, networking, game loader) and all game scenes. Room creator is "host" and authoritative for game state.
3. **Protocol** — JSON messages over WebSocket with a `type` field.

## Relay Server

Single `server.js` file. Dependency: `ws`.

### State

In-memory `Map<room_code, { host: WebSocket, guest: WebSocket }>`.

### Room Codes

Random 4-character alphanumeric (e.g. `A3F7`). Generated on room creation, checked for collisions.

### Message Protocol

**Client → Server:**

| Message | Purpose |
|---|---|
| `{ type: "create_room" }` | Host creates a new room |
| `{ type: "join_room", code: "A3F7" }` | Guest joins an existing room |
| `{ type: "relay", data: {...} }` | Forward payload to the other peer |

**Server → Client:**

| Message | Purpose |
|---|---|
| `{ type: "room_created", code: "A3F7" }` | Room created, here's the code |
| `{ type: "peer_joined", your_role: "host" }` | Sent to host when guest joins. `your_role` is the recipient's own role. |
| `{ type: "peer_joined", your_role: "guest" }` | Sent to guest on successful join. `your_role` is the recipient's own role. |
| `{ type: "peer_left" }` | Other peer disconnected |
| `{ type: "relay", data: {...} }` | Forwarded message from other peer |
| `{ type: "error", message: "..." }` | Error (room not found, room full) |

### Edge Cases

- Join non-existent room → error "Room not found"
- Join full room → error "Room full"
- Peer disconnects → `peer_left` sent to remaining peer, room cleaned up
- No persistence, no auth, no HTTPS (dev-only for v1)

## Godot Client Architecture

### Project Structure

```
project.godot
scenes/
  shell/
    main_menu.tscn          # Game selection screen
    lobby.tscn               # Create/join room UI
  games/
    tic_tac_toe/
      tic_tac_toe.tscn       # Game scene
      tic_tac_toe.gd         # Game logic + rendering
scripts/
  network/
    ws_client.gd             # WebSocket manager (autoload)
  game_interface.gd          # Base class for all games
export_presets.cfg           # HTML5 export config
```

### Autoloads

**WsClient** (`scripts/network/ws_client.gd`) — singleton managing WebSocket connection.

Signals:
- `connected`
- `disconnected`
- `room_created(code: String)`
- `peer_joined(your_role: String)`
- `peer_left`
- `message_received(data: Dictionary)`

Methods:
- `connect_to_server()` (uses hardcoded `SERVER_URL` constant, `ws://localhost:8080`)
- `create_room()`
- `join_room(code: String)`
- `send_relay(data: Dictionary)`

### Scene Flow

**Host flow**: MainMenu → (pick game) → Lobby → (create room, show code, wait for guest) → GameScene → (game over) → Lobby

**Guest flow**: MainMenu → (enter room code) → Lobby → (join room, wait for host to start) → GameScene → (game over) → Lobby

The host selects which game to play. When the guest joins, the host sends a `{ type: "game_selected", scene: "res://scenes/games/..." }` relay message with the scene path. The lobby on both sides then transitions to the game scene. The guest does not independently pick a game — they join whatever the host chose.

MainMenu has two paths: "Host Game" (pick game → create room) and "Join Game" (enter code → join room).

### Game Interface

All games extend `game_interface.gd`:

```gdscript
# Base class for all games
extends Node

var is_host: bool = false

func start_game(_is_host: bool) -> void:
    is_host = _is_host

func on_peer_message(_data: Dictionary) -> void:
    pass

func send_message(data: Dictionary) -> void:
    WsClient.send_relay(data)

func on_peer_left() -> void:
    # Default: show disconnect message and return to main menu
    pass
```

Adding a new game: create a scene + script in `scenes/games/<name>/`, extend `game_interface.gd`, add entry to game registry.

### Game Registry

A simple dictionary in `main_menu.gd` mapping game names to scene paths, used to populate the game list:

```gdscript
var games := {
    "Tic-Tac-Toe": "res://scenes/games/tic_tac_toe/tic_tac_toe.tscn"
}
```

## Tic-Tac-Toe Game

### State

3x3 array held by host. Host = X (goes first), Guest = O.

### Rendering

3x3 grid of buttons. Each shows "", "X", or "O". A label shows whose turn it is and game result.

### Game Message Protocol

All messages sent via relay:

| Message | Direction | Purpose |
|---|---|---|
| `{ type: "game_start", board: [9 empty strings] }` | Host → Guest | Initial state sync |
| `{ type: "move", position: 0-8 }` | Current player → other | Claim a cell |
| `{ type: "state_update", board: [...], turn: "X"/"O" }` | Host → Guest | Authoritative state after move |
| `{ type: "game_over", winner: "X"/"O"/"draw" }` | Host → Guest | Game ended |

### Flow

1. Both players connect via lobby
2. Host sends `game_start` with empty board
3. Players alternate turns — click cell → send `move` to the other peer via relay
4. Host validates all moves (correct turn, cell empty), updates board, sends `state_update`. Guest never updates board locally — it only renders from `state_update` messages. When host makes a move, it processes locally (no round-trip) and sends `state_update` to guest.
5. Host checks win/draw after each move, sends `game_over` if applicable
6. "Play Again": only the host can trigger it. Host clicks "Play Again" → sends new `game_start` → guest's board resets automatically. Guest sees "Waiting for host..." until reset. Host always plays X.

### Win Detection

Check 8 lines (3 rows, 3 cols, 2 diagonals) for three matching non-empty values.

## HTML5 Export & Dev Workflow

- Use Godot "Web" export preset → produces `index.html`, `.wasm`, `.pck`, `.js`
- Serve from any static file server
- WebSocket URL: `ws://localhost:8080` in dev (hardcoded constant, easy to change later)

### Dev Workflow

1. `node server.js` — start relay on port 8080
2. Export from Godot or use built-in "Run in Browser"
3. Open two browser tabs to test multiplayer

## Limitations (v1)

- HTTP only, no TLS
- No reconnection — disconnect sends you back to lobby
- 2 players per room only
- No room timeout/cleanup beyond disconnect handling
- Host leaving ends the game — guest sees "Host disconnected" and returns to main menu
