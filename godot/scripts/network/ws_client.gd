extends Node

signal connected
signal disconnected
signal room_created(code: String)
signal peer_joined(your_role: String)
signal peer_left
signal message_received(data: Dictionary)

const SERVER_URL := "wss://gd-experiment-relay.fly.dev"

var _socket := WebSocketPeer.new()
var _connected := false
var _last_state := -1

func _log(msg: String) -> void:
	if Engine.has_singleton("DebugLog") or has_node("/root/DebugLog"):
		get_node("/root/DebugLog").log_msg("[WS] " + msg)

func _ready() -> void:
	set_process(false)

func connect_to_server() -> void:
	_log("Connecting to %s" % SERVER_URL)
	_socket = WebSocketPeer.new()
	_connected = false
	_last_state = -1
	var err := _socket.connect_to_url(SERVER_URL)
	if err != OK:
		_log("connect_to_url failed: error code %s" % err)
		push_error("WebSocket connection failed: %s" % err)
		return
	_log("connect_to_url returned OK, polling started")
	set_process(true)

func _process(_delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state != _last_state:
		_log("State changed: %s -> %s" % [_state_name(_last_state), _state_name(state)])
		if state == WebSocketPeer.STATE_CLOSED:
			var close_code := _socket.get_close_code()
			var close_reason := _socket.get_close_reason()
			_log("Close code: %s, reason: '%s'" % [close_code, close_reason])
		_last_state = state

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			_log("Connected!")
			connected.emit()
		while _socket.get_available_packet_count() > 0:
			var raw := _socket.get_packet().get_string_from_utf8()
			_log("Recv: %s" % raw)
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				_handle_message(parsed)
			else:
				_log("Failed to parse as Dictionary: %s" % raw)
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			_log("Disconnected")
			disconnected.emit()
		set_process(false)

func _handle_message(msg: Dictionary) -> void:
	var msg_type: String = msg.get("type", "")
	_log("Handle message type: %s" % msg_type)
	match msg_type:
		"room_created":
			room_created.emit(msg["code"])
		"peer_joined":
			peer_joined.emit(msg["your_role"])
		"peer_left":
			peer_left.emit()
		"relay":
			message_received.emit(msg["data"])
		"error":
			_log("Server error: %s" % msg.get("message", "unknown"))
			push_error("Server error: %s" % msg.get("message", "unknown"))
		_:
			_log("Unknown message type: %s" % msg_type)

func create_room() -> void:
	_log("Sending create_room")
	_send({"type": "create_room"})

func join_room(code: String) -> void:
	_log("Sending join_room code=%s" % code)
	_send({"type": "join_room", "code": code})

func send_relay(data: Dictionary) -> void:
	_log("Sending relay: %s" % JSON.stringify(data))
	_send({"type": "relay", "data": data})

func close() -> void:
	_log("Closing socket")
	_socket.close()

func _send(data: Dictionary) -> void:
	var json := JSON.stringify(data)
	_log("Send: %s" % json)
	_socket.send_text(json)

func _state_name(state: int) -> String:
	match state:
		-1: return "INIT"
		WebSocketPeer.STATE_CONNECTING: return "CONNECTING"
		WebSocketPeer.STATE_OPEN: return "OPEN"
		WebSocketPeer.STATE_CLOSING: return "CLOSING"
		WebSocketPeer.STATE_CLOSED: return "CLOSED"
		_: return "UNKNOWN(%s)" % state
