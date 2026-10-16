extends Node2D
## Builds the vertical slice: world, squad, managers, camera, HUD.

const SQUAD := [
	# callsign, pilot, personality, color, chassis, primary, secondary, modules
	["VANGUARD", "You", "", Color(0.45, 0.85, 1.0), "vanguard", "autocannon", "rockets", ["heat_sink", "targeting"]],
	["ROOK", "Ilya Rooker", "rook", Color(1.0, 0.55, 0.35), "bulwark", "flak", "rockets", ["armor_plate", "heat_sink", "ammo_rack"]],
	["WREN", "Sade Okonkwo", "wren", Color(0.75, 0.95, 0.45), "kestrel", "laser", "mortar", ["targeting", "reactor"]],
	["MAGS", "Magda Vell", "mags", Color(0.9, 0.7, 1.0), "sparrow", "gatling", "", ["repair_drone", "shield", "heat_sink"]],
]

var filter_rect: ColorRect
var bot_report_t := 0.0


func _ready() -> void:
	get_tree().paused = false
	G.reset()
	randomize()
	var seed_value := randi()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))

	var world := World.new()
	world.generate(seed_value)
	add_child(world)
	G.world = world

	var pickups := Pickups.new()
	add_child(pickups)
	pickups.populate(world.cache_spots, world.rng)
	G.pickups = pickups

	var enemies := EnemyManager.new()
	add_child(enemies)
	G.enemies = enemies

	var mech_layer := Node2D.new()
	add_child(mech_layer)

	var projectiles := ProjectileManager.new()
	add_child(projectiles)
	G.projectiles = projectiles

	var offsets := [Vector2.ZERO, Vector2(-40, -45), Vector2(-60, 45), Vector2(-90, 0)]
	for i in SQUAD.size():
		var d: Array = SQUAD[i]
		var m := Mech.new()
		m.setup(d[0], d[1], d[3], Loadout.new(d[4], d[5], d[6], d[7]), i == 0)
		m.position = world.start_pos + offsets[i]
		mech_layer.add_child(m)
		G.squad.append(m)
		if i == 0:
			G.player = m
			if G.bot_mode:
				m.brain = SquadBrain.new(m, "lead")
		else:
			m.brain = SquadBrain.new(m, d[2])

	var overlay := TacticalOverlay.new()
	add_child(overlay)

	var cam := GameCamera.new()
	add_child(cam)
	cam.global_position = G.player.position
	cam.make_current()
	G.camera = cam

	var director := Director.new()
	add_child(director)
	G.director = director

	# Satellite-feed filter over the world, HUD crisp on top.
	var fl := CanvasLayer.new()
	fl.layer = 1
	add_child(fl)
	filter_rect = ColorRect.new()
	filter_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/satellite.gdshader")
	filter_rect.material = mat
	fl.add_child(filter_rect)

	var hl := CanvasLayer.new()
	hl.layer = 2
	add_child(hl)
	var hud := Hud.new()
	hl.add_child(hud)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps drawing the pause screen
	G.hud = hud
	var menu := FieldMenu.new()
	hl.add_child(menu)
	G.menu = menu

	G.say("", "Left Outpost Gravel. Haven-7 is east along the old freight road.", Color(0.7, 0.8, 0.7))
	G.say("WREN", "Scanners are quiet. Won't stay that way.", SQUAD[2][3].lightened(0.3))
	if G.bot_mode:
		print("[bot] seed %d, caches %d, buildings %d" % [seed_value, world.cache_spots.size(), world.buildings.size()])


func _process(delta: float) -> void:
	if G.game_state != "play":
		if Input.is_action_just_pressed("open_menu") or Input.is_action_just_pressed("pause"):
			get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed("toggle_director"):
		G.show_director = not G.show_director
	if Input.is_action_just_pressed("toggle_filter"):
		filter_rect.visible = not filter_rect.visible
	if Input.is_action_just_pressed("open_menu"):
		G.menu.toggle()
	elif G.menu.open:
		G.menu.handle_input()
	if Input.is_action_just_pressed("tactical_toggle"):
		G.tactical_latched = not G.tactical_latched
	if G.menu.open:
		G.tactical_latched = false
	G.tactical = (Input.is_action_pressed("tactical") or G.tactical_latched) and not G.menu.open
	if G.bot_mode:
		_bot_screenshots()

	if G.player.alive and G.world.goal_zone.has_point(G.player.position):
		G.game_state = "won"
		G.announce("HAVEN-7 — GATES OPENING", Color(1, 0.85, 0.45))
		if G.bot_mode:
			print("[bot] WON at %.1fs kills=%d alive=%d" % [G.game_time, G.kills, G.alive_squad().size()])

	if G.bot_mode:
		_bot_refit_test()
		bot_report_t -= delta
		if bot_report_t <= 0.0:
			bot_report_t = 10.0
			var states := []
			for m in G.squad:
				states.append("%s:%s hp%.0f%%" % [m.callsign, m.state_label if m.alive else "DEAD", m.hp_ratio() * 100])
			print("[bot] t=%5.1f fps=%d prog=%.0f%% enemies=%d dir=%s int=%.0f mats=%s | %s" % [
				G.game_time, Engine.get_frames_per_second(), G.world.progress_of(G.player.position) * 100,
				G.enemies.alive_count(), Director.PHASE_NAMES[G.director.phase], G.director.intensity,
				str(G.materials), ", ".join(states)])


var _shots_taken := {}
var _peak_seen_at := -1.0

func _bot_screenshots() -> void:
	## With `--shots=<dir>`, saves a few frames for visual review.
	var dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	if dir == "":
		return
	if G.director.phase == Director.Phase.PEAK and _peak_seen_at < 0.0:
		_peak_seen_at = G.game_time
	var t := G.game_time
	if t > 36.0 and t < 40.0:
		G.tactical = true
	var want := {"01_field": t > 8.0, "02_refit": t > 28.0, "03_tactical": t > 39.5,
		"04_horde": _peak_seen_at > 0.0 and t > _peak_seen_at + 9.0}
	for k in want:
		if want[k] and not _shots_taken.has(k):
			_shots_taken[k] = true
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, k])
			print("[bot] screenshot %s at %.1fs" % [k, t])


var _bot_refit_step := 0

func _bot_refit_test() -> void:
	## Drives the field menu like a player would, to exercise the refit flow.
	var menu := G.menu
	if _bot_refit_step == 0 and G.game_time > 25.0:
		menu.toggle()                        # open
		menu.slot_idx = 0
		menu._accept()                       # R1 hardpoint -> part list
		menu.part_idx = menu.rows.find("gatling")
		menu._accept()                       # fabricate + install
		menu.slot_idx = 4
		menu._accept()                       # module bay 3 -> part list
		menu.part_idx = menu.rows.find("servos")
		menu._accept()
		print("[bot] refit: %s | installing=%s mats=%s" % [menu.flash_msg, str(G.player.installing.keys()), str(G.materials)])
		_bot_refit_step = 1
	elif _bot_refit_step == 1 and G.game_time > 31.0:
		menu.toggle()                        # close
		var lo := G.player.loadout
		print("[bot] refit done: primary=%s modules=%s speed=%.0f weight=%d/%d" % [lo.primary, str(lo.modules), G.player.stats.speed, G.player.stats.weight, G.player.stats.max_weight])
		_bot_refit_step = 2
