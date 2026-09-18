class_name NetClient
extends Node

## Thin WebSocket client for the counter room.
##
## Owns the socket lifecycle (connect, poll, reconnect with backoff) and turns
## the server's JSON messages into signals. Knows nothing about the UI.

signal connection_changed(state: State)
signal welcomed(you: Dictionary, counter: int, players: Array)
signal counter_changed(value: int, by: String)
signal roster_changed(players: Array)

enum State { DISCONNECTED, CONNECTING, CONNECTED }

const KEEPALIVE_SECONDS := 30.0
const RECONNECT_MIN_SECONDS := 1.0
const RECONNECT_MAX_SECONDS := 15.0

var state: State = State.DISCONNECTED:
	set(value):
		if state == value:
			return
		state = value
		connection_changed.emit(state)

var _socket := WebSocketPeer.new()
var _url := ""
var _reconnect_in := 0.0
var _reconnect_delay := RECONNECT_MIN_SECONDS
var _keepalive_in := KEEPALIVE_SECONDS

func connect_to_server(url: String) -> void:
	_url = url
	_open()

func click() -> void:
	_send({"type": "click"})

func _open() -> void:
	state = State.CONNECTING
	var err := _socket.connect_to_url(_url)
	if err != OK:
		push_warning("Could not start connection to %s: %s" % [_url, error_string(err)])
		_schedule_reconnect()

func _process(delta: float) -> void:
	if _reconnect_in > 0.0:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			_open()
		return

	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state != State.CONNECTED:
				state = State.CONNECTED
				# A successful connection resets the backoff, so a later blip
				# retries quickly instead of inheriting the old delay.
				_reconnect_delay = RECONNECT_MIN_SECONDS
			_pump_keepalive(delta)
			while _socket.get_available_packet_count() > 0:
				_receive(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_schedule_reconnect()

func _pump_keepalive(delta: float) -> void:
	_keepalive_in -= delta
	if _keepalive_in > 0.0:
		return
	_keepalive_in = KEEPALIVE_SECONDS
	# Matches the server's auto-response pair: answered without waking the
	# Durable Object out of hibernation.
	_socket.send_text("ping")

func _schedule_reconnect() -> void:
	state = State.DISCONNECTED
	_reconnect_in = _reconnect_delay
	_reconnect_delay = minf(_reconnect_delay * 2.0, RECONNECT_MAX_SECONDS)
	_keepalive_in = KEEPALIVE_SECONDS

func _send(payload: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))

func _receive(text: String) -> void:
	if text == "pong":
		return

	var msg: Variant = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY:
		return

	match msg.get("type", ""):
		"welcome":
			welcomed.emit(
				msg.get("you", {}),
				int(msg.get("counter", 0)),
				msg.get("players", []),
			)
		"counter":
			counter_changed.emit(int(msg.get("value", 0)), str(msg.get("by", "")))
		"roster":
			roster_changed.emit(msg.get("players", []))
