extends Control

var game_scene: String = ""
var is_host := false
var room_code: String = ""

@onready var status_label: Label = %StatusLabel
@onready var code_label: Label = %CodeLabel
@onready var back_button: Button = %BackButton

func _log(msg: String) -> void:
	if has_node("/root/DebugLog"):
		get_node("/root/DebugLog").log_msg("[Lobby] " + msg)

func _ready() -> void:
	_log("Ready. is_host=%s game_scene=%s room_code=%s" % [is_host, game_scene, room_code])
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
	_log("Connected callback")
	if is_host:
		status_label.text = "Connected. Creating room..."
		WsClient.create_room()
	else:
		status_label.text = "Connected. Joining room %s..." % room_code
		WsClient.join_room(room_code)

func _on_room_created(code: String) -> void:
	_log("Room created: %s" % code)
	room_code = code
	code_label.text = "Room Code: %s" % code
	status_label.text = "Waiting for other player to join..."

func _on_peer_joined(your_role: String) -> void:
	_log("Peer joined, your_role=%s" % your_role)
	status_label.text = "Player joined! Starting game..."
	if is_host:
		WsClient.send_relay({"type": "game_selected", "scene": game_scene})
		_start_game()
	# Guest waits for game_selected message

func _on_message_received(data: Dictionary) -> void:
	_log("Message received: %s" % JSON.stringify(data))
	if data.get("type", "") == "game_selected":
		game_scene = data["scene"]
		_start_game()

func _start_game() -> void:
	_log("Starting game: %s" % game_scene)
	var scene := load(game_scene) as PackedScene
	if not scene:
		_log("ERROR: could not load game scene")
		status_label.text = "Error: could not load game"
		return
	var game_node := scene.instantiate()
	if game_node.has_method("start_game"):
		game_node.call_deferred("start_game", is_host)
	WsClient.message_received.disconnect(_on_message_received)
	get_tree().root.add_child(game_node)
	queue_free()

func _on_disconnected() -> void:
	_log("Disconnected from server")
	status_label.text = "Disconnected from server."

func _on_peer_left() -> void:
	_log("Peer left")
	status_label.text = "Other player left."

func _on_back_pressed() -> void:
	_log("Back pressed")
	WsClient.close()
	get_tree().change_scene_to_file("res://scenes/shell/main_menu.tscn")

func _exit_tree() -> void:
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
