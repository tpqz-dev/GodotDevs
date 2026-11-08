extends Node

signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal lobby_updated
signal status_changed(message: String)
signal session_closed(message: String)
signal game_started
signal game_peer_ready(id: int)
signal game_finished(results: Dictionary)
signal lobby_returned
signal lobby_return_preparing

const VERSION := "game-6"
const MAX_PLAYERS := 4
const DEFAULT_PORT := 7777
const CONNECTION_TIMEOUT := 8.0
const UPDATE_INTERVAL_MSEC := 200

var players: Dictionary = {}
var connected := false
var hosting := false
var pending_name := ""
var pending_color := Color.WHITE
var connection_deadline := 0
var last_updates: Dictionary = {}
var registration_deadlines: Dictionary = {}
var in_game := false
var last_session_message := ""
var game_ready_ids: Dictionary = {}
var match_finished := false
var returning_to_lobby := false
var return_ready_ids: Dictionary = {}
var return_deadline := 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	if connection_deadline > 0 and Time.get_ticks_msec() >= connection_deadline:
		close_session("Connexion impossible ou serveur complet.")
	if hosting:
		if return_deadline > 0 and Time.get_ticks_msec() >= return_deadline:
			close_session("Retour au lobby interrompu : un joueur ne répond pas.")
			return
		for id in registration_deadlines.keys():
			if Time.get_ticks_msec() >= registration_deadlines[id]:
				registration_deadlines.erase(id)
				var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
				peer.disconnect_peer(id, true)

func host_game(port: int, player_name: String, color: Color) -> String:
	var error := _validate_profile(port, player_name, color)
	if not error.is_empty():
		return error
	if hosting or connected or connection_deadline > 0:
		return "Une session est déjà ouverte."
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		return "Impossible d'héberger sur le port %d (erreur %d)." % [port, result]
	multiplayer.multiplayer_peer = peer
	hosting = true
	connected = true
	players[1] = _profile(player_name, color)
	player_joined.emit(1, players[1])
	lobby_updated.emit()
	status_changed.emit("Lobby hébergé sur le port UDP %d." % port)
	return ""

func join_game(address: String, port: int, player_name: String, color: Color) -> String:
	var error := _validate_profile(port, player_name, color)
	if not error.is_empty():
		return error
	if address.strip_edges().is_empty() or address.length() > 253:
		return "Saisissez une adresse IP ou un nom d'hôte valide."
	if hosting or connected or connection_deadline > 0:
		return "Une session est déjà ouverte."
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address.strip_edges(), port)
	if result != OK:
		return "Impossible de démarrer la connexion (erreur %d)." % result
	pending_name = player_name.strip_edges()
	pending_color = color
	multiplayer.multiplayer_peer = peer
	connection_deadline = Time.get_ticks_msec() + int(CONNECTION_TIMEOUT * 1000)
	status_changed.emit("Connexion en cours…")
	return ""

func update_profile(player_name: String, color: Color, ready: bool) -> String:
	if not connected or in_game:
		return "Vous n'êtes pas connecté au lobby."
	var error := _validate_profile(DEFAULT_PORT, player_name, color)
	if not error.is_empty():
		return error
	if hosting:
		_apply_profile(1, player_name, color, ready)
	else:
		_request_profile.rpc_id(1, player_name.strip_edges(), color, ready)
	return ""

func close_session(message: String = "") -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	for id in players:
		player_left.emit(id)
	players.clear()
	last_updates.clear()
	registration_deadlines.clear()
	game_ready_ids.clear()
	connected = false
	hosting = false
	in_game = false
	match_finished = false
	returning_to_lobby = false
	return_ready_ids.clear()
	return_deadline = 0
	connection_deadline = 0
	last_session_message = message
	lobby_updated.emit()
	session_closed.emit(message)

func _validate_profile(port: int, player_name: String, color: Color) -> String:
	if port < 1 or port > 65535:
		return "Le port doit être compris entre 1 et 65535."
	var trimmed := player_name.strip_edges()
	if trimmed.is_empty() or trimmed.length() > 24 or "\n" in trimmed or "\r" in trimmed:
		return "Le pseudo doit contenir entre 1 et 24 caractères sur une ligne."
	if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b):
		return "Couleur invalide."
	return ""

func _profile(player_name: String, color: Color, ready: bool = false) -> Dictionary:
	return {"name": player_name.strip_edges(), "color": Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0)), "ready": ready}

func _on_connected() -> void:
	status_changed.emit("Connecté, inscription au lobby…")
	_register.rpc_id(1, VERSION, pending_name, pending_color)

func _on_connection_failed() -> void:
	close_session("Connexion impossible ou serveur complet.")

func _on_server_disconnected() -> void:
	close_session("Connexion perdue : l'hôte a quitté la partie.")

func _on_peer_connected(id: int) -> void:
	if hosting:
		registration_deadlines[id] = Time.get_ticks_msec() + int(CONNECTION_TIMEOUT * 1000)

func _on_peer_disconnected(id: int) -> void:
	if not hosting:
		return
	registration_deadlines.erase(id)
	last_updates.erase(id)
	if players.has(id):
		players.erase(id)
		player_left.emit(id)
		_broadcast_lobby()
		if returning_to_lobby:
			_check_return_ready()

@rpc("any_peer", "call_remote", "reliable")
func _register(version: String, player_name: String, color: Color) -> void:
	if not hosting or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or players.has(sender):
		return
	if in_game:
		_reject.rpc_id(sender, "La partie a déjà commencé.")
		return
	if version != VERSION:
		_reject.rpc_id(sender, "Version incompatible.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject.rpc_id(sender, "Serveur complet.")
		return
	var error := _validate_profile(DEFAULT_PORT, player_name, color)
	if not error.is_empty():
		_reject.rpc_id(sender, error)
		return
	players[sender] = _profile(player_name, color)
	registration_deadlines.erase(sender)
	player_joined.emit(sender, players[sender])
	_broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func _reject(message: String) -> void:
	close_session(message)

@rpc("any_peer", "call_remote", "reliable")
func _request_profile(player_name: String, color: Color, ready: bool) -> void:
	if not hosting or not multiplayer.is_server() or in_game:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var now := Time.get_ticks_msec()
	if last_updates.has(sender) and now - int(last_updates[sender]) < UPDATE_INTERVAL_MSEC:
		_profile_rejected.rpc_id(sender, "Veuillez patienter avant de modifier à nouveau votre profil.")
		_send_lobby.rpc_id(sender, players)
		return
	last_updates[sender] = now
	if not _validate_profile(DEFAULT_PORT, player_name, color).is_empty():
		_profile_rejected.rpc_id(sender, "Profil invalide.")
		_send_lobby.rpc_id(sender, players)
		return
	_apply_profile(sender, player_name, color, ready)

@rpc("authority", "call_remote", "reliable")
func _profile_rejected(message: String) -> void:
	status_changed.emit(message)

func _apply_profile(id: int, player_name: String, color: Color, ready: bool) -> void:
	players[id] = _profile(player_name, color, ready)
	_broadcast_lobby()

func _broadcast_lobby() -> void:
	lobby_updated.emit()
	for id in players:
		if id != 1:
			_send_lobby.rpc_id(id, players)

@rpc("authority", "call_remote", "reliable")
func _send_lobby(snapshot: Dictionary) -> void:
	var old_players := players
	players = snapshot
	for id in old_players:
		if not players.has(id):
			player_left.emit(id)
	for id in players:
		if not old_players.has(id):
			player_joined.emit(id, players[id])
	var was_connected := connected
	connected = true
	connection_deadline = 0
	lobby_updated.emit()
	if not was_connected:
		status_changed.emit("Connecté au lobby.")

func can_start_game() -> bool:
	if not hosting or in_game or players.size() < 2:
		return false
	for info in players.values():
		if not info.ready:
			return false
	return true

func start_game() -> String:
	if not can_start_game():
		return "Il faut au moins deux joueurs et tous doivent être prêts."
	in_game = true
	match_finished = false
	game_ready_ids.clear()
	for id in players:
		if id != 1:
			_begin_game.rpc_id(id)
	game_started.emit()
	return ""

@rpc("authority", "call_remote", "reliable")
func _begin_game() -> void:
	if connected and not hosting and not in_game:
		in_game = true
		match_finished = false
		game_ready_ids.clear()
		game_started.emit()

func notify_game_ready() -> void:
	if hosting and in_game:
		game_ready_ids[1] = true
		game_peer_ready.emit(1)
	elif connected and in_game:
		_game_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _game_ready() -> void:
	if hosting and in_game:
		var id := multiplayer.get_remote_sender_id()
		if players.has(id):
			game_ready_ids[id] = true
			game_peer_ready.emit(id)

func finish_game(results: Dictionary) -> String:
	if not hosting or not connected or not in_game or match_finished:
		return "Seul l'hôte peut terminer une partie en cours."
	_show_results.rpc(results)
	return ""

@rpc("authority", "call_local", "reliable")
func _show_results(results: Dictionary) -> void:
	if not connected or not in_game or match_finished:
		return
	match_finished = true
	game_finished.emit(results)

func return_to_lobby() -> String:
	if not hosting or not connected or not in_game or not match_finished or returning_to_lobby:
		return "Seul l'hôte peut ramener les joueurs au lobby après la partie."
	return_ready_ids.clear()
	return_deadline = Time.get_ticks_msec() + int(CONNECTION_TIMEOUT * 1000)
	_prepare_lobby_return.rpc()
	return ""

@rpc("authority", "call_local", "reliable")
func _prepare_lobby_return() -> void:
	if not connected or not in_game or not match_finished or returning_to_lobby:
		return
	returning_to_lobby = true
	lobby_return_preparing.emit()

func notify_lobby_return_ready() -> void:
	if not connected or not returning_to_lobby:
		return
	if hosting:
		return_ready_ids[1] = true
		_check_return_ready()
	else:
		_lobby_return_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _lobby_return_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	if hosting and returning_to_lobby and players.has(id):
		return_ready_ids[id] = true
		_check_return_ready()

func _check_return_ready() -> void:
	if not hosting or not returning_to_lobby:
		return
	for id in players:
		if not return_ready_ids.has(id):
			return
	for info in players.values():
		info.ready = false
	game_ready_ids.clear()
	last_updates.clear()
	_enter_lobby.rpc(players)

@rpc("authority", "call_local", "reliable")
func _enter_lobby(snapshot: Dictionary) -> void:
	if not connected or not in_game or not match_finished:
		return
	players = snapshot.duplicate(true)
	game_ready_ids.clear()
	in_game = false
	match_finished = false
	returning_to_lobby = false
	return_ready_ids.clear()
	return_deadline = 0
	last_session_message = "Partie terminée. Les joueurs doivent à nouveau se déclarer prêts."
	lobby_returned.emit()
	lobby_updated.emit()
