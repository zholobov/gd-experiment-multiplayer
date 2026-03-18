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
