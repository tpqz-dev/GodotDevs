extends Control

var address_field: LineEdit
var port_field: LineEdit
var name_field: LineEdit
var color_picker: ColorPickerButton
var status_label: Label
var menu_panel: VBoxContainer
var lobby_panel: VBoxContainer
var player_list: VBoxContainer
var ready_button: Button
var profile_button: Button
var lobby_title: Label
var request_pending := false
var host_button: Button
var join_button: Button
var cancel_button: Button
var start_button: Button

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	NetworkManager.lobby_updated.connect(_lobby_updated)
	NetworkManager.status_changed.connect(_set_status)
	NetworkManager.session_closed.connect(_session_closed)
	NetworkManager.game_started.connect(_start_game_scene)
	_refresh()
	if not NetworkManager.last_session_message.is_empty():
		_set_status(NetworkManager.last_session_message)
		NetworkManager.last_session_message = ""

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("192839")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(460, 0)
	content.add_theme_constant_override("separation", 10)
	center.add_child(content)
	var title := Label.new()
	title.text = "Multijoueur coopératif"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Hébergez ou rejoignez un lobby par adresse IP."
	content.add_child(status_label)
	menu_panel = VBoxContainer.new()
	menu_panel.add_theme_constant_override("separation", 8)
	content.add_child(menu_panel)
	name_field = _add_field(menu_panel, "Pseudo", "Joueur")
	name_field.max_length = 24
	var color_row := HBoxContainer.new()
	menu_panel.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "Couleur"
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_label)
	color_picker = ColorPickerButton.new()
	color_picker.color = Color("4cb9ee")
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(80, 32)
	color_row.add_child(color_picker)
	address_field = _add_field(menu_panel, "Adresse IP / nom d'hôte", "127.0.0.1")
	port_field = _add_field(menu_panel, "Port UDP", str(NetworkManager.DEFAULT_PORT))
	var buttons := HBoxContainer.new()
	menu_panel.add_child(buttons)
	host_button = _add_button(buttons, "Héberger", _host)
	join_button = _add_button(buttons, "Rejoindre", _join)
	cancel_button = _add_button(menu_panel, "Annuler la connexion", _cancel_connection)
	_add_button(menu_panel, "Jouer en solo", _play_solo)
	lobby_panel = VBoxContainer.new()
	lobby_panel.add_theme_constant_override("separation", 8)
	content.add_child(lobby_panel)
	lobby_title = Label.new()
	lobby_panel.add_child(lobby_title)
	player_list = VBoxContainer.new()
	lobby_panel.add_child(player_list)
	var actions := HBoxContainer.new()
	lobby_panel.add_child(actions)
	ready_button = _add_button(actions, "Prêt", _toggle_ready)
	profile_button = _add_button(lobby_panel, "Modifier pseudo / couleur", _edit_profile)
	start_button = _add_button(lobby_panel, "Lancer la partie", _start)
	_add_button(lobby_panel, "Quitter le lobby", _leave)

func _add_field(parent: Node, title: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field

func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _port() -> int:
	if not port_field.text.is_valid_int():
		return 0
	return port_field.text.to_int()

func _host() -> void:
	_show_error(NetworkManager.host_game(_port(), name_field.text, color_picker.color))

func _join() -> void:
	_show_error(NetworkManager.join_game(address_field.text, _port(), name_field.text, color_picker.color))
	_refresh()

func _play_solo() -> void:
	if NetworkManager.connection_deadline > 0:
		NetworkManager.close_session()
	var result := get_tree().change_scene_to_file("res://Main.tscn")
	if result != OK:
		_set_status("Impossible de lancer la partie solo (erreur %d)." % result)

func _toggle_ready() -> void:
	var info: Dictionary = NetworkManager.players.get(multiplayer.get_unique_id(), {})
	if info.is_empty() or request_pending:
		return
	_send_profile(info.name, info.color, not info.ready)

func _edit_profile() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Modifier le profil"
	var layout := VBoxContainer.new()
	dialog.add_child(layout)
	var info: Dictionary = NetworkManager.players.get(multiplayer.get_unique_id(), {})
	var edit_name := _add_field(layout, "Pseudo", info.get("name", "Joueur"))
	edit_name.max_length = 24
	var edit_color := ColorPickerButton.new()
	edit_color.edit_alpha = false
	edit_color.color = info.get("color", Color.WHITE)
	edit_color.custom_minimum_size = Vector2(100, 40)
	layout.add_child(edit_color)
	dialog.confirmed.connect(func() -> void:
		_send_profile(edit_name.text, edit_color.color, false)
	)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(430, 180))

func _send_profile(player_name: String, color: Color, ready: bool) -> void:
	request_pending = true
	_refresh()
	var error: String = NetworkManager.update_profile(player_name, color, ready)
	if not error.is_empty():
		request_pending = false
		_show_error(error)
		_refresh()

func _leave() -> void:
	NetworkManager.close_session("Vous avez quitté le lobby.")

func _start() -> void:
	_show_error(NetworkManager.start_game())

func _start_game_scene() -> void:
	var result := get_tree().change_scene_to_file("res://MultiplayerGame.tscn")
	if result != OK:
		NetworkManager.close_session("Impossible de charger la partie (erreur %d)." % result)

func _cancel_connection() -> void:
	NetworkManager.close_session("Connexion annulée.")

func _session_closed(message: String) -> void:
	request_pending = false
	if not message.is_empty():
		_set_status(message)
	_refresh()

func _lobby_updated() -> void:
	request_pending = false
	_refresh()

func _show_error(error: String) -> void:
	if not error.is_empty():
		_set_status(error)

func _set_status(message: String) -> void:
	status_label.text = message

func _refresh() -> void:
	var in_lobby: bool = NetworkManager.connected
	var connecting: bool = NetworkManager.connection_deadline > 0
	menu_panel.visible = not in_lobby
	lobby_panel.visible = in_lobby
	host_button.disabled = connecting
	join_button.disabled = connecting
	cancel_button.visible = connecting
	if not in_lobby:
		return
	lobby_title.text = "Lobby %s — %d / %d joueurs" % ["(hôte)" if NetworkManager.hosting else "", NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	for child in player_list.get_children():
		child.queue_free()
	for id in NetworkManager.players:
		var info: Dictionary = NetworkManager.players[id]
		var label := Label.new()
		label.text = "%s%s — %s" % [info.name, " (hôte)" if id == 1 else "", "prêt" if info.ready else "pas prêt"]
		label.add_theme_color_override("font_color", info.color)
		player_list.add_child(label)
	var own_info: Dictionary = NetworkManager.players.get(multiplayer.get_unique_id(), {})
	ready_button.text = "Annuler prêt" if own_info.get("ready", false) else "Prêt"
	ready_button.disabled = request_pending
	profile_button.disabled = request_pending
	start_button.visible = NetworkManager.hosting
	start_button.disabled = not NetworkManager.can_start_game()
