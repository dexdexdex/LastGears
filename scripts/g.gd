extends Node
## Global game state + input setup. Autoloaded as `G`.

signal radio_msg(text: String, color: Color)
signal banner(text: String, color: Color)

var world: World
var enemies: EnemyManager
var projectiles: ProjectileManager
var pickups: Pickups
var director: Director
var camera: GameCamera
var hud: Hud
var menu: FieldMenu
var station: StationMenu
var campaign: Campaign          # persists across legs (scene reloads)
var threat := 1
var leg_kills := {}
var player: Mech
var squad: Array = []          # all mechs incl. player
var materials := {"scrap": 24, "circuits": 8, "cells": 5}
var radio: Array = []          # [{text, color, t}]
var game_time := 0.0
var kills := 0
var using_mouse := false
var tactical := false
var view_mode := 0              # 0 field, 2 region map (M / touchpad)
var lighting: Lighting
var radar_zoom := 1             # index into Hud.RADAR_RANGES (Q / R2 cycles)
const FORMATIONS := ["FOLLOW", "GROUP UP", "SPREAD OUT", "HOLD"]
var formation := 0
var hold_pos := Vector2.ZERO
var overworld := false
var atlas: Atlas                # regional network of havens and zones (persists across restarts)
var menu_closed_t := -99.0
var game_state := "play"       # play | won | lost
var bot_mode := false          # --bot : AI drives the player (for automated tests)
var show_director := true

const MATERIAL_NAMES := {"scrap": "SCRAP", "circuits": "CIRCUITS", "cells": "CELLS"}
const MATERIAL_COLORS := {
	"scrap": Color(0.78, 0.72, 0.62),
	"circuits": Color(0.45, 0.85, 0.6),
	"cells": Color(0.45, 0.75, 1.0),
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	using_mouse = Input.get_connected_joypads().is_empty()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	bot_mode = "--bot" in OS.get_cmdline_user_args()


func reset() -> void:
	squad.clear()
	radio.clear()
	leg_kills = {}
	game_time = 0.0
	kills = 0
	tactical = false
	view_mode = 0
	overworld = false
	formation = 0
	menu_closed_t = -99.0
	game_state = "play"


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if Input.is_action_just_pressed("pause") and game_state == "play" and not (menu and menu.open):
		get_tree().paused = not get_tree().paused
	if Input.is_action_just_pressed("restart"):
		if game_state == "station":
			return
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if get_tree().paused:
		return
	if game_state == "play":
		game_time += delta


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 2.0:
		using_mouse = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.4 and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
		using_mouse = false


# ---------------------------------------------------------------- radio / economy

func say(who: String, text: String, color: Color = Color(0.85, 0.9, 0.85)) -> void:
	var line := ("%s: %s" % [who, text]) if who != "" else text
	radio.append({"text": line, "color": color, "t": game_time})
	if radio.size() > 40:
		radio.pop_front()
	radio_msg.emit(line, color)


func announce(text: String, color: Color = Color(1, 0.85, 0.4)) -> void:
	banner.emit(text, color)


func add_materials(d: Dictionary) -> void:
	for k in d:
		materials[k] = materials.get(k, 0) + int(d[k])


func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if materials.get(k, 0) < int(cost[k]):
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		materials[k] -= int(cost[k])
	return true


func cost_string(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts: Array = []
	for k in ["scrap", "circuits", "cells"]:
		if cost.has(k):
			parts.append("%d %s" % [cost[k], MATERIAL_NAMES[k].to_lower()])
	return ", ".join(parts)


func alive_squad() -> Array:
	return squad.filter(func(m): return m.alive)


func squad_centroid() -> Vector2:
	var a := alive_squad()
	if a.is_empty():
		return Vector2.ZERO
	var c := Vector2.ZERO
	for m in a:
		c += m.position
	return c / a.size()


# ---------------------------------------------------------------- input map

func _setup_input() -> void:
	_key("move_up", [KEY_W])
	_key("move_down", [KEY_S])
	_key("move_left", [KEY_A])
	_key("move_right", [KEY_D])
	_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	_button("fire_primary", [JOY_BUTTON_RIGHT_SHOULDER])     # R1
	_mouse("fire_primary", MOUSE_BUTTON_LEFT)
	_button("fire_secondary", [JOY_BUTTON_LEFT_SHOULDER])    # L1
	_mouse("fire_secondary", MOUSE_BUTTON_RIGHT)
	_axis("radar_zoom", JOY_AXIS_TRIGGER_RIGHT, 1.0)         # R2
	_key("radar_zoom", [KEY_Q])
	_key("formation_cycle", [KEY_E])
	_button("form_group", [JOY_BUTTON_DPAD_UP])
	_button("form_spread", [JOY_BUTTON_DPAD_DOWN])
	_button("form_hold", [JOY_BUTTON_DPAD_LEFT])
	_button("form_follow", [JOY_BUTTON_DPAD_RIGHT])
	_key("overworld_toggle", [KEY_M])
	_button("overworld_toggle", [JOY_BUTTON_TOUCHPAD])
	_key("dodge", [KEY_SPACE, KEY_SHIFT])
	_button("dodge", [JOY_BUTTON_B])                         # Circle
	_key("pause", [KEY_ENTER, KEY_KP_ENTER])
	_button("pause", [JOY_BUTTON_BACK])
	_key("toggle_fullscreen", [KEY_F11])
	_button("open_menu", [JOY_BUTTON_START])
	_key("open_menu", [KEY_ESCAPE, KEY_I])

	_key("menu_up", [KEY_UP, KEY_W])
	_key("menu_down", [KEY_DOWN, KEY_S])
	_button("menu_up", [JOY_BUTTON_DPAD_UP])
	_button("menu_down", [JOY_BUTTON_DPAD_DOWN])
	_axis("menu_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis("menu_down", JOY_AXIS_LEFT_Y, 1.0)
	_key("menu_accept", [KEY_E, KEY_SPACE])
	_mouse("menu_accept", MOUSE_BUTTON_LEFT)
	_button("menu_accept", [JOY_BUTTON_A])
	_key("menu_back", [KEY_BACKSPACE])
	_key("tab_left", [KEY_A, KEY_LEFT])
	_button("tab_left", [JOY_BUTTON_LEFT_SHOULDER])
	_key("tab_right", [KEY_D, KEY_RIGHT, KEY_TAB])
	_button("tab_right", [JOY_BUTTON_RIGHT_SHOULDER])
	_key("new_campaign", [KEY_N])
	_mouse("menu_back", MOUSE_BUTTON_RIGHT)
	_button("menu_back", [JOY_BUTTON_B])

	_key("restart", [KEY_F5])
	_key("toggle_director", [KEY_F3])
	_key("toggle_filter", [KEY_F2])


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


func _key(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _button(action: String, buttons: Array) -> void:
	_ensure(action)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)


func _mouse(action: String, button: int) -> void:
	_ensure(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _axis(action: String, axis: int, value: float) -> void:
	_ensure(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)
