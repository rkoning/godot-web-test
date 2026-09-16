extends Control

@onready var _status: Label = $Center/Panel/Margin/Rows/Status

func _ready() -> void:
	_status.text = "Godot %s · %s" % [
		_engine_version(),
		OS.get_name(),
	]

func _engine_version() -> String:
	var info := Engine.get_version_info()
	return "%d.%d.%d" % [info.major, info.minor, info.patch]
