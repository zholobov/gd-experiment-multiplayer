# Multiplayer Game Shell Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a browser-based multiplayer game shell in Godot 4.x with a Node.js WebSocket relay, and a tic-tac-toe game as the first playable game.

**Architecture:** A thin Node.js WebSocket relay server handles room creation/joining and message forwarding. The Godot 4.x client exports to HTML5, contains a game shell (main menu, lobby, networking singleton) and pluggable game scenes. The room creator is host and authoritative for game state.

**Tech Stack:** Godot 4.x (GDScript), Node.js (ws library), HTML5/WebSocket

**Spec:** `docs/superpowers/specs/2026-03-17-multiplayer-game-shell-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `server/package.json` | Node.js dependencies (ws) |
| `server/server.js` | WebSocket relay — rooms, message forwarding |
| `server/server.test.js` | Relay server tests |
| `godot/project.godot` | Godot project config with autoloads |
| `godot/scripts/network/ws_client.gd` | WebSocket manager singleton (autoload) |
| `godot/scripts/game_interface.gd` | Base class for all games |
| `godot/scenes/shell/main_menu.tscn` | Main menu scene |
| `godot/scenes/shell/main_menu.gd` | Main menu logic (host/join paths, game registry) |
| `godot/scenes/shell/lobby.tscn` | Lobby scene (room code display/entry) |
| `godot/scenes/shell/lobby.gd` | Lobby logic (create/join room, transition to game) |
| `godot/scenes/games/tic_tac_toe/tic_tac_toe.tscn` | Tic-tac-toe scene (3x3 grid + labels) |
| `godot/scenes/games/tic_tac_toe/tic_tac_toe.gd` | Tic-tac-toe game logic |

---

## Task 0: Prerequisites

- [ ] **Step 1: Install Node.js**

```bash
brew install node
```

- [ ] **Step 2: Verify Godot 4 is available**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --version`
Expected: `4.x.x.stable...`

- [ ] **Step 3: Initialize git repo**

```bash
cd /Users/zholobov/src/gd-experiment-multiplayer
git init
```

- [ ] **Step 4: Create .gitignore**

Create `.gitignore`:

```
# Godot
godot/.godot/
godot/export/

# Node
server/node_modules/

# OS
.DS_Store
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "chore: initial repo with .gitignore"
```

---

## Task 1: Relay Server

**Files:**
- Create: `server/package.json`
- Create: `server/server.js`
- Create: `server/server.test.js`

- [ ] **Step 1: Initialize Node project and install dependencies**

```bash
cd server
npm init -y
npm install ws
npm install --save-dev vitest
```

Add to `package.json`:
```json
"type": "module",
"scripts": {
  "start": "node server.js",
  "test": "vitest run"
}
```

- [ ] **Step 2: Write relay server tests**

Create `server/server.test.js`:

```javascript
import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { WebSocket, WebSocketServer } from 'ws';
import { createServer } from './server.js';

let server;
let port;

function connectClient() {
  return new Promise((resolve) => {
    const ws = new WebSocket(`ws://localhost:${port}`);
    ws.on('open', () => resolve(ws));
  });
}

function waitForMessage(ws) {
  return new Promise((resolve) => {
    ws.once('message', (data) => resolve(JSON.parse(data)));
  });
}

function send(ws, obj) {
  ws.send(JSON.stringify(obj));
}

beforeAll(() => {
  return new Promise((resolve) => {
    server = createServer(0); // port 0 = random available port
    server.on('listening', () => {
      port = server.address().port;
      resolve();
    });
  });
});

afterAll(() => {
  server.close();
});

describe('room creation', () => {
  it('should create a room and return a 4-char code', async () => {
    const ws = await connectClient();
    send(ws, { type: 'create_room' });
    const msg = await waitForMessage(ws);
    expect(msg.type).toBe('room_created');
    expect(msg.code).toMatch(/^[A-Z0-9]{4}$/);
    ws.close();
  });
});

describe('room joining', () => {
  it('should let a guest join an existing room', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    const hostMsgPromise = waitForMessage(host);
    send(guest, { type: 'join_room', code: created.code });

    const guestMsg = await waitForMessage(guest);
    expect(guestMsg.type).toBe('peer_joined');
    expect(guestMsg.your_role).toBe('guest');

    const hostMsg = await hostMsgPromise;
    expect(hostMsg.type).toBe('peer_joined');
    expect(hostMsg.your_role).toBe('host');

    host.close();
    guest.close();
  });

  it('should error on non-existent room', async () => {
    const ws = await connectClient();
    send(ws, { type: 'join_room', code: 'ZZZZ' });
    const msg = await waitForMessage(ws);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Room not found');
    ws.close();
  });

  it('should error on full room', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest1 = await connectClient();
    send(guest1, { type: 'join_room', code: created.code });
    await waitForMessage(guest1); // peer_joined

    const guest2 = await connectClient();
    send(guest2, { type: 'join_room', code: created.code });
    const msg = await waitForMessage(guest2);
    expect(msg.type).toBe('error');
    expect(msg.message).toBe('Room full');

    host.close();
    guest1.close();
    guest2.close();
  });
});

describe('relay', () => {
  it('should forward messages between peers', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    send(guest, { type: 'join_room', code: created.code });
    await waitForMessage(guest); // peer_joined
    await waitForMessage(host);  // peer_joined

    const guestMsgPromise = waitForMessage(guest);
    send(host, { type: 'relay', data: { type: 'game_start', board: ['','','','','','','','',''] } });
    const relayed = await guestMsgPromise;
    expect(relayed.type).toBe('relay');
    expect(relayed.data.type).toBe('game_start');

    host.close();
    guest.close();
  });
});

describe('disconnect', () => {
  it('should notify peer when other disconnects', async () => {
    const host = await connectClient();
    send(host, { type: 'create_room' });
    const created = await waitForMessage(host);

    const guest = await connectClient();
    send(guest, { type: 'join_room', code: created.code });
    await waitForMessage(guest); // peer_joined
    await waitForMessage(host);  // peer_joined

    const hostMsgPromise = waitForMessage(host);
    guest.close();
    const msg = await hostMsgPromise;
    expect(msg.type).toBe('peer_left');

    host.close();
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd server && npm test`
Expected: FAIL — `server.js` doesn't exist yet

- [ ] **Step 4: Implement the relay server**

Create `server/server.js`:

```javascript
import { WebSocketServer } from 'ws';

const rooms = new Map();

function generateCode() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code;
  do {
    code = '';
    for (let i = 0; i < 4; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
  } while (rooms.has(code));
  return code;
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function findRoom(ws) {
  for (const [code, room] of rooms) {
    if (room.host === ws || room.guest === ws) {
      return [code, room];
    }
  }
  return [null, null];
}

function getPeer(room, ws) {
  if (room.host === ws) return room.guest;
  if (room.guest === ws) return room.host;
  return null;
}

export function createServer(port) {
  const wss = new WebSocketServer({ port });

  wss.on('connection', (ws) => {
    ws.on('message', (raw) => {
      let msg;
      try {
        msg = JSON.parse(raw);
      } catch {
        return;
      }

      if (msg.type === 'create_room') {
        const code = generateCode();
        rooms.set(code, { host: ws, guest: null });
        ws._roomCode = code;
        send(ws, { type: 'room_created', code });
      } else if (msg.type === 'join_room') {
        const room = rooms.get(msg.code);
        if (!room) {
          send(ws, { type: 'error', message: 'Room not found' });
        } else if (room.guest) {
          send(ws, { type: 'error', message: 'Room full' });
        } else {
          room.guest = ws;
          ws._roomCode = msg.code;
          send(ws, { type: 'peer_joined', your_role: 'guest' });
          send(room.host, { type: 'peer_joined', your_role: 'host' });
        }
      } else if (msg.type === 'relay') {
        const [code, room] = findRoom(ws);
        if (room) {
          const peer = getPeer(room, ws);
          if (peer) {
            send(peer, { type: 'relay', data: msg.data });
          }
        }
      }
    });

    ws.on('close', () => {
      const [code, room] = findRoom(ws);
      if (room) {
        const peer = getPeer(room, ws);
        if (peer) {
          send(peer, { type: 'peer_left' });
        }
        rooms.delete(code);
      }
    });
  });

  return wss;
}

// Run standalone when executed directly
import { fileURLToPath } from 'url';
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const PORT = process.env.PORT || 8080;
  const wss = createServer(PORT);
  console.log(`Relay server listening on ws://localhost:${PORT}`);
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd server && npm test`
Expected: All 5 tests PASS

- [ ] **Step 6: Commit**

```bash
git add server/
git commit -m "feat: add WebSocket relay server with room management and tests"
```

---

## Task 2: Godot Project Setup

**Files:**
- Create: `godot/project.godot`
- Create: `godot/scripts/network/ws_client.gd`
- Create: `godot/scripts/game_interface.gd`

- [ ] **Step 1: Create Godot project file**

Create `godot/project.godot`:

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; but it can also be manually edited.

config_version=5

[application]

config/name="Multiplayer Game Shell"
run/main_scene="res://scenes/shell/main_menu.tscn"
config/features=PackedStringArray("4.3", "GL Compatibility")

[autoload]

WsClient="*res://scripts/network/ws_client.gd"

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

- [ ] **Step 2: Create WsClient autoload**

Create `godot/scripts/network/ws_client.gd`:

```gdscript
extends Node

signal connected
signal disconnected
signal room_created(code: String)
signal peer_joined(your_role: String)
signal peer_left
signal message_received(data: Dictionary)

const SERVER_URL := "ws://localhost:8080"

var _socket := WebSocketPeer.new()
var _connected := false

func _ready() -> void:
	set_process(false)

func connect_to_server() -> void:
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		push_error("WebSocket connection failed: %s" % err)
		return
	set_process(true)

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			connected.emit()
		while _socket.get_available_packet_count() > 0:
			var raw := _socket.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				_handle_message(parsed)
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			disconnected.emit()
		set_process(false)

func _handle_message(msg: Dictionary) -> void:
	match msg.get("type", ""):
		"room_created":
			room_created.emit(msg["code"])
		"peer_joined":
			peer_joined.emit(msg["your_role"])
		"peer_left":
			peer_left.emit()
		"relay":
			message_received.emit(msg["data"])
		"error":
			push_error("Server error: %s" % msg.get("message", "unknown"))

func create_room() -> void:
	_send({"type": "create_room"})

func join_room(code: String) -> void:
	_send({"type": "join_room", "code": code})

func send_relay(data: Dictionary) -> void:
	_send({"type": "relay", "data": data})

func close() -> void:
	_socket.close()

func _send(data: Dictionary) -> void:
	var json := JSON.stringify(data)
	_socket.send_text(json)
```

- [ ] **Step 3: Create game interface base class**

Create `godot/scripts/game_interface.gd`:

```gdscript
class_name GameInterface
extends Node

var is_host := false

func start_game(_is_host: bool) -> void:
	is_host = _is_host

func on_peer_message(_data: Dictionary) -> void:
	pass

func send_message(data: Dictionary) -> void:
	WsClient.send_relay(data)

func on_peer_left() -> void:
	get_tree().change_scene_to_file("res://scenes/shell/main_menu.tscn")
```

- [ ] **Step 4: Commit**

```bash
git add godot/project.godot godot/scripts/
git commit -m "feat: add Godot project with WsClient autoload and GameInterface base"
```

---

## Task 3: Main Menu Scene

**Files:**
- Create: `godot/scenes/shell/main_menu.tscn`
- Create: `godot/scenes/shell/main_menu.gd`

- [ ] **Step 1: Create main menu script**

Create `godot/scenes/shell/main_menu.gd`:

```gdscript
extends Control

var games := {
	"Tic-Tac-Toe": "res://scenes/games/tic_tac_toe/tic_tac_toe.tscn"
}

@onready var game_list: ItemList = %GameList
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var code_input: LineEdit = %CodeInput
@onready var status_label: Label = %StatusLabel

var _selected_game_scene: String = ""

func _ready() -> void:
	for game_name in games:
		game_list.add_item(game_name)
	host_button.disabled = true
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	game_list.item_selected.connect(_on_game_selected)

func _on_game_selected(index: int) -> void:
	var game_name := game_list.get_item_text(index)
	_selected_game_scene = games[game_name]
	host_button.disabled = false

func _on_host_pressed() -> void:
	if _selected_game_scene.is_empty():
		return
	_go_to_lobby(_selected_game_scene, true)

func _on_join_pressed() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		status_label.text = "Enter a 4-character room code"
		return
	_go_to_lobby("", false, code)

func _go_to_lobby(game_scene: String, is_host: bool, code: String = "") -> void:
	var lobby := preload("res://scenes/shell/lobby.tscn").instantiate()
	lobby.game_scene = game_scene
	lobby.is_host = is_host
	lobby.room_code = code
	get_tree().root.add_child(lobby)
	queue_free()
```

- [ ] **Step 2: Create main menu scene file**

Create `godot/scenes/shell/main_menu.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://main_menu"]

[ext_resource type="Script" path="res://scenes/shell/main_menu.gd" id="1"]

[node name="MainMenu" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="MarginContainer" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 40
theme_override_constants/margin_top = 40
theme_override_constants/margin_right = 40
theme_override_constants/margin_bottom = 40

[node name="VBox" type="VBoxContainer" parent="MarginContainer"]
layout_mode = 2

[node name="Title" type="Label" parent="MarginContainer/VBox"]
layout_mode = 2
text = "Multiplayer Game Shell"
horizontal_alignment = 1

[node name="Spacer1" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 20)

[node name="HostSection" type="VBoxContainer" parent="MarginContainer/VBox"]
layout_mode = 2

[node name="HostLabel" type="Label" parent="MarginContainer/VBox/HostSection"]
layout_mode = 2
text = "Select a game and host:"

[node name="GameList" type="ItemList" parent="MarginContainer/VBox/HostSection"]
unique_name_in_owner = true
layout_mode = 2
custom_minimum_size = Vector2(0, 100)

[node name="HostButton" type="Button" parent="MarginContainer/VBox/HostSection"]
unique_name_in_owner = true
layout_mode = 2
text = "Host Game"

[node name="Spacer2" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 20)

[node name="JoinSection" type="VBoxContainer" parent="MarginContainer/VBox"]
layout_mode = 2

[node name="JoinLabel" type="Label" parent="MarginContainer/VBox/JoinSection"]
layout_mode = 2
text = "Or join with a room code:"

[node name="CodeInput" type="LineEdit" parent="MarginContainer/VBox/JoinSection"]
unique_name_in_owner = true
layout_mode = 2
placeholder_text = "Enter room code (e.g. A3F7)"
max_length = 4

[node name="JoinButton" type="Button" parent="MarginContainer/VBox/JoinSection"]
unique_name_in_owner = true
layout_mode = 2
text = "Join Game"

[node name="Spacer3" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 10)

[node name="StatusLabel" type="Label" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = ""
horizontal_alignment = 1
```

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/shell/main_menu.*
git commit -m "feat: add main menu with game selection and host/join paths"
```

---

## Task 4: Lobby Scene

**Files:**
- Create: `godot/scenes/shell/lobby.tscn`
- Create: `godot/scenes/shell/lobby.gd`

- [ ] **Step 1: Create lobby script**

Create `godot/scenes/shell/lobby.gd`:

```gdscript
extends Control

var game_scene: String = ""
var is_host := false
var room_code: String = ""

@onready var status_label: Label = %StatusLabel
@onready var code_label: Label = %CodeLabel
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	WsClient.connected.connect(_on_connected)
	WsClient.room_created.connect(_on_room_created)
	WsClient.peer_joined.connect(_on_peer_joined)
	WsClient.message_received.connect(_on_message_received)
	WsClient.disconnected.connect(_on_disconnected)
	WsClient.peer_left.connect(_on_peer_left)

	status_label.text = "Connecting to server..."
	code_label.text = ""
	WsClient.connect_to_server()

func _on_connected() -> void:
	if is_host:
		status_label.text = "Connected. Creating room..."
		WsClient.create_room()
	else:
		status_label.text = "Connected. Joining room %s..." % room_code
		WsClient.join_room(room_code)

func _on_room_created(code: String) -> void:
	room_code = code
	code_label.text = "Room Code: %s" % code
	status_label.text = "Waiting for other player to join..."

func _on_peer_joined(your_role: String) -> void:
	status_label.text = "Player joined! Starting game..."
	if is_host:
		WsClient.send_relay({"type": "game_selected", "scene": game_scene})
		_start_game()
	# Guest waits for game_selected message

func _on_message_received(data: Dictionary) -> void:
	if data.get("type", "") == "game_selected":
		game_scene = data["scene"]
		_start_game()

func _start_game() -> void:
	var scene := load(game_scene) as PackedScene
	if not scene:
		status_label.text = "Error: could not load game"
		return
	var game_node := scene.instantiate()
	if game_node.has_method("start_game"):
		game_node.call_deferred("start_game", is_host)
	WsClient.message_received.disconnect(_on_message_received)
	get_tree().root.add_child(game_node)
	queue_free()

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."

func _on_peer_left() -> void:
	status_label.text = "Other player left."

func _on_back_pressed() -> void:
	WsClient.close()
	get_tree().change_scene_to_file("res://scenes/shell/main_menu.tscn")

func _exit_tree() -> void:
	# Disconnect signals to avoid errors after scene change
	if WsClient.connected.is_connected(_on_connected):
		WsClient.connected.disconnect(_on_connected)
	if WsClient.room_created.is_connected(_on_room_created):
		WsClient.room_created.disconnect(_on_room_created)
	if WsClient.peer_joined.is_connected(_on_peer_joined):
		WsClient.peer_joined.disconnect(_on_peer_joined)
	if WsClient.disconnected.is_connected(_on_disconnected):
		WsClient.disconnected.disconnect(_on_disconnected)
	if WsClient.peer_left.is_connected(_on_peer_left):
		WsClient.peer_left.disconnect(_on_peer_left)
	if WsClient.message_received.is_connected(_on_message_received):
		WsClient.message_received.disconnect(_on_message_received)
```

- [ ] **Step 2: Create lobby scene file**

Create `godot/scenes/shell/lobby.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://lobby"]

[ext_resource type="Script" path="res://scenes/shell/lobby.gd" id="1"]

[node name="Lobby" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="MarginContainer" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 40
theme_override_constants/margin_top = 40
theme_override_constants/margin_right = 40
theme_override_constants/margin_bottom = 40

[node name="VBox" type="VBoxContainer" parent="MarginContainer"]
layout_mode = 2

[node name="Title" type="Label" parent="MarginContainer/VBox"]
layout_mode = 2
text = "Lobby"
horizontal_alignment = 1

[node name="Spacer1" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 20)

[node name="CodeLabel" type="Label" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = ""
horizontal_alignment = 1

[node name="StatusLabel" type="Label" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Connecting..."
horizontal_alignment = 1

[node name="Spacer2" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 20)

[node name="BackButton" type="Button" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Back to Menu"
```

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/shell/lobby.*
git commit -m "feat: add lobby scene with room creation/joining and game transition"
```

---

## Task 5: Tic-Tac-Toe Game

**Files:**
- Create: `godot/scenes/games/tic_tac_toe/tic_tac_toe.tscn`
- Create: `godot/scenes/games/tic_tac_toe/tic_tac_toe.gd`

- [ ] **Step 1: Create tic-tac-toe script**

Create `godot/scenes/games/tic_tac_toe/tic_tac_toe.gd`:

```gdscript
extends GameInterface

const WIN_LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],  # rows
	[0, 3, 6], [1, 4, 7], [2, 5, 8],  # cols
	[0, 4, 8], [2, 4, 6],             # diagonals
]

var board: Array[String] = []
var current_turn: String = "X"
var my_symbol: String = ""
var game_active := false

@onready var grid: GridContainer = %Grid
@onready var status_label: Label = %StatusLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var back_button: Button = %BackButton

var _cells: Array[Button] = []

func _ready() -> void:
	WsClient.message_received.connect(on_peer_message)
	WsClient.peer_left.connect(on_peer_left)
	play_again_button.pressed.connect(_on_play_again)
	play_again_button.visible = false
	back_button.pressed.connect(_on_back)

	for i in 9:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(80, 80)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		_cells.append(btn)

func start_game(_is_host: bool) -> void:
	super.start_game(_is_host)
	my_symbol = "X" if is_host else "O"

	if is_host:
		_init_board()
		send_message({"type": "game_start", "board": board.duplicate()})
		_update_ui()

func _init_board() -> void:
	board.clear()
	for i in 9:
		board.append("")
	current_turn = "X"
	game_active = true
	play_again_button.visible = false

func on_peer_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"game_start":
			var b: Array = data["board"]
			board.clear()
			for cell in b:
				board.append(str(cell))
			current_turn = "X"
			game_active = true
			play_again_button.visible = false
			_update_ui()
		"move":
			if is_host and current_turn == "O":
				_process_move(int(data["position"]))
		"state_update":
			if not is_host:
				var b: Array = data["board"]
				board.clear()
				for cell in b:
					board.append(str(cell))
				current_turn = str(data["turn"])
				_update_ui()
		"game_over":
			game_active = false
			var winner: String = str(data["winner"])
			if winner == "draw":
				status_label.text = "It's a draw!"
			elif winner == my_symbol:
				status_label.text = "You win!"
			else:
				status_label.text = "You lose!"
			if is_host:
				play_again_button.visible = true
			else:
				play_again_button.visible = false
				status_label.text += " Waiting for host..."
			_update_cells()

func _on_cell_pressed(index: int) -> void:
	if not game_active:
		return
	if current_turn != my_symbol:
		return
	if board[index] != "":
		return

	if is_host:
		_process_move(index)
	else:
		send_message({"type": "move", "position": index})

func _process_move(index: int) -> void:
	if not game_active:
		return
	if board[index] != "":
		return

	var expected_turn := current_turn
	board[index] = current_turn

	var winner := _check_winner()
	if winner != "":
		game_active = false
		send_message({"type": "state_update", "board": board.duplicate(), "turn": current_turn})
		send_message({"type": "game_over", "winner": winner})
		on_peer_message({"type": "game_over", "winner": winner})
		return

	if _is_board_full():
		game_active = false
		send_message({"type": "state_update", "board": board.duplicate(), "turn": current_turn})
		send_message({"type": "game_over", "winner": "draw"})
		on_peer_message({"type": "game_over", "winner": "draw"})
		return

	current_turn = "O" if current_turn == "X" else "X"
	send_message({"type": "state_update", "board": board.duplicate(), "turn": current_turn})
	_update_ui()

func _check_winner() -> String:
	for line in WIN_LINES:
		var a: String = board[line[0]]
		var b: String = board[line[1]]
		var c: String = board[line[2]]
		if a != "" and a == b and b == c:
			return a
	return ""

func _is_board_full() -> bool:
	for cell in board:
		if cell == "":
			return false
	return true

func _update_ui() -> void:
	_update_cells()
	if game_active:
		if current_turn == my_symbol:
			status_label.text = "Your turn (%s)" % my_symbol
		else:
			status_label.text = "Opponent's turn (%s)" % current_turn

func _update_cells() -> void:
	for i in 9:
		_cells[i].text = board[i] if board[i] != "" else ""
		_cells[i].disabled = not game_active or board[i] != "" or current_turn != my_symbol

func _on_play_again() -> void:
	if is_host:
		_init_board()
		send_message({"type": "game_start", "board": board.duplicate()})
		_update_ui()

func on_peer_left() -> void:
	game_active = false
	status_label.text = "Host disconnected." if not is_host else "Guest disconnected."
	await get_tree().create_timer(2.0).timeout
	WsClient.close()
	get_tree().change_scene_to_file("res://scenes/shell/main_menu.tscn")

func _on_back() -> void:
	WsClient.close()
	get_tree().change_scene_to_file("res://scenes/shell/main_menu.tscn")

func _exit_tree() -> void:
	if WsClient.message_received.is_connected(on_peer_message):
		WsClient.message_received.disconnect(on_peer_message)
	if WsClient.peer_left.is_connected(on_peer_left):
		WsClient.peer_left.disconnect(on_peer_left)
```

- [ ] **Step 2: Create tic-tac-toe scene file**

Create `godot/scenes/games/tic_tac_toe/tic_tac_toe.tscn`:

```
[gd_scene load_steps=2 format=3 uid="uid://tictactoe"]

[ext_resource type="Script" path="res://scenes/games/tic_tac_toe/tic_tac_toe.gd" id="1"]

[node name="TicTacToe" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")

[node name="MarginContainer" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 40
theme_override_constants/margin_top = 40
theme_override_constants/margin_right = 40
theme_override_constants/margin_bottom = 40

[node name="VBox" type="VBoxContainer" parent="MarginContainer"]
layout_mode = 2
alignment = 1

[node name="Title" type="Label" parent="MarginContainer/VBox"]
layout_mode = 2
text = "Tic-Tac-Toe"
horizontal_alignment = 1

[node name="Spacer1" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 10)

[node name="StatusLabel" type="Label" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Waiting..."
horizontal_alignment = 1

[node name="Spacer2" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 10)

[node name="CenterContainer" type="CenterContainer" parent="MarginContainer/VBox"]
layout_mode = 2

[node name="Grid" type="GridContainer" parent="MarginContainer/VBox/CenterContainer"]
unique_name_in_owner = true
layout_mode = 2
columns = 3

[node name="Spacer3" type="Control" parent="MarginContainer/VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 10)

[node name="PlayAgainButton" type="Button" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Play Again"

[node name="BackButton" type="Button" parent="MarginContainer/VBox"]
unique_name_in_owner = true
layout_mode = 2
text = "Back to Menu"
```

- [ ] **Step 3: Commit**

```bash
git add godot/scenes/games/tic_tac_toe/
git commit -m "feat: add tic-tac-toe game with host-authoritative state"
```

---

## Task 6: Integration Test (Manual)

- [ ] **Step 1: Start relay server**

```bash
cd server && node server.js
```

Expected: `Relay server listening on ws://localhost:8080`

- [ ] **Step 2: Configure Web export preset and run in browser**

Open `godot/project.godot` in Godot 4. Go to Project → Export → Add Preset → Web. This creates `export_presets.cfg`. Then use "Run in Browser" or export to `godot/export/web/`.

- [ ] **Step 3: Test host flow**

1. Open browser tab 1
2. Select "Tic-Tac-Toe" from game list
3. Click "Host Game"
4. Note the 4-character room code displayed

- [ ] **Step 4: Test guest flow**

1. Open browser tab 2
2. Enter room code from step 3
3. Click "Join Game"
4. Both tabs should transition to the tic-tac-toe board

- [ ] **Step 5: Play a full game**

1. Tab 1 (host/X) clicks a cell — both boards update
2. Tab 2 (guest/O) clicks a cell — both boards update
3. Continue until win or draw
4. Verify correct winner/draw message on both sides
5. Host clicks "Play Again" — board resets on both sides

- [ ] **Step 6: Test disconnect**

1. Close tab 2 (guest)
2. Tab 1 should show "Guest disconnected." and return to main menu

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: integration test fixes"
```

(Only if fixes were needed.)
