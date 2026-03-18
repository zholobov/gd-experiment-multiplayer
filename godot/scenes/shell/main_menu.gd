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
