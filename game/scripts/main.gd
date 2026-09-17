extends Control

const DISCONNECTED_COLOR := Color("e06c6c")
const CONNECTING_COLOR := Color("e6b45e")
const CONNECTED_COLOR := Color("5ec8a0")

@onready var _counter: Label = %Counter
@onready var _click_button: Button = %ClickButton
@onready var _status_dot: Panel = %StatusDot
@onready var _status_text: Label = %StatusText
@onready var _you: Label = %You
@onready var _last_click: Label = %LastClick
@onready var _player_list: VBoxContainer = %PlayerList

var _client := NetClient.new()
var _me_id := ""

func _ready() -> void:
	add_child(_client)
	_client.connection_changed.connect(_on_connection_changed)
	_client.welcomed.connect(_on_welcomed)
	_client.counter_changed.connect(_on_counter_changed)
	_client.roster_changed.connect(_render_players)

	_click_button.pressed.connect(_client.click)
	_on_connection_changed(_client.state)
	_client.connect_to_server(NetConfig.server_url())

func _on_connection_changed(state: NetClient.State) -> void:
	# The button stays disabled until the server has confirmed us, so a click
	# can never be silently dropped into a dead socket.
	_click_button.disabled = state != NetClient.State.CONNECTED

	match state:
		NetClient.State.CONNECTED:
			_set_status("connected", CONNECTED_COLOR)
		NetClient.State.CONNECTING:
			_set_status("connecting…", CONNECTING_COLOR)
		NetClient.State.DISCONNECTED:
			_set_status("reconnecting…", DISCONNECTED_COLOR)
			_you.text = "—"

func _on_welcomed(you: Dictionary, counter: int, players: Array) -> void:
	_me_id = str(you.get("id", ""))
	_you.text = str(you.get("name", "—"))
	_counter.text = str(counter)
	_render_players(players)

func _on_counter_changed(value: int, by: String) -> void:
	_counter.text = str(value)
	_last_click.text = "last click: %s" % by

func _render_players(players: Array) -> void:
	for child in _player_list.get_children():
		child.queue_free()

	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var row := Label.new()
		var is_me: bool = str(player.get("id", "")) == _me_id
		row.text = "%s%s" % [str(player.get("name", "?")), " (you)" if is_me else ""]
		row.modulate = CONNECTED_COLOR if is_me else Color("adbbcd")
		_player_list.add_child(row)

func _set_status(text: String, color: Color) -> void:
	_status_text.text = text
	_status_dot.modulate = color
