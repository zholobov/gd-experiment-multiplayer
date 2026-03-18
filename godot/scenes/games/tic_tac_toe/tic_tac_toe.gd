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
