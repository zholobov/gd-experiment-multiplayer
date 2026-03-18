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
