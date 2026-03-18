extends CanvasLayer

var _log_lines: PackedStringArray = []
var _panel: PanelContainer
var _label: RichTextLabel
var _copy_button: Button
var _toggle_button: Button
var _visible := false

func _ready() -> void:
	layer = 100

	# Toggle button (always visible, bottom-right)
	_toggle_button = Button.new()
	_toggle_button.text = "Log"
	_toggle_button.pressed.connect(_toggle)
	_toggle_button.z_index = 100
	add_child(_toggle_button)

	# Log panel
	_panel = PanelContainer.new()
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Debug Log"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_copy_button = Button.new()
	_copy_button.text = "Copy to Clipboard"
	_copy_button.pressed.connect(_copy_log)
	header.add_child(_copy_button)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.pressed.connect(_toggle)
	header.add_child(close_btn)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.scroll_following = true
	_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.custom_minimum_size = Vector2(0, 300)
	vbox.add_child(_label)

	_update_layout()
	get_tree().root.size_changed.connect(_update_layout)

	log_msg("DebugLog ready")
	log_msg("Server URL: %s" % WsClient.SERVER_URL)

func _update_layout() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	_toggle_button.position = Vector2(vp_size.x - 80, vp_size.y - 40)
	_toggle_button.size = Vector2(70, 30)
	_panel.position = Vector2(10, vp_size.y * 0.5)
	_panel.size = Vector2(vp_size.x - 20, vp_size.y * 0.5 - 10)

func _toggle() -> void:
	_visible = not _visible
	_panel.visible = _visible

func log_msg(msg: String) -> void:
	var timestamp := "%.2f" % (Time.get_ticks_msec() / 1000.0)
	var line := "[%s] %s" % [timestamp, msg]
	_log_lines.append(line)
	if _label:
		_label.text = "\n".join(_log_lines)
	print(line)

func _copy_log() -> void:
	var full_log := "\n".join(_log_lines)
	DisplayServer.clipboard_set(full_log)
	_copy_button.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	_copy_button.text = "Copy to Clipboard"
