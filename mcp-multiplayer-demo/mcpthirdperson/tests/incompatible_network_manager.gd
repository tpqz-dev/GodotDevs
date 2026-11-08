extends "res://scripts/network_manager.gd"

func _on_connected() -> void:
	_register.rpc_id(1, "version-incompatible", pending_name, pending_color)
