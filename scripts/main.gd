extends Node2D
## Builds the vertical slice: world, squad, managers, camera, HUD.

var filter_rect: ColorRect
var bot_report_t := 0.0


func _ready() -> void:
	get_tree().paused = false
	G.reset()
	if G.campaign == null:
		randomize()
		var cseed := randi()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--seed="):
				cseed = int(a.substr(7))
		G.atlas = Atlas.new(cseed)          # every campaign gets its own region
		G.campaign = Campaign.new(G.atlas, cseed)
	var camp: Campaign = G.campaign
	camp.sync_atlas(G.atlas)
	G.materials = camp.materials.duplicate()
	G.threat = camp.threat(G.atlas)
	var seed_value := camp.leg_seed
	var from_n: Dictionary = G.atlas.nodes[camp.node_idx]
	var to_n: Dictionary = G.atlas.nodes[camp.dest_idx]

	var world := World.new()
	world.generate(seed_value, from_n.name, to_n.name, G.atlas.leg_dir(camp.node_idx, camp.dest_idx))
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

	# Tracers and blasts draw above the darkness so they glow.
	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 2
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	var projectiles := ProjectileManager.new()
	glow_layer.add_child(projectiles)
	G.projectiles = projectiles

	var offsets := [Vector2.ZERO, Vector2(-40, -45), Vector2(-60, 45), Vector2(-90, 0)]
	for i in camp.squad.size():
		var entry: Dictionary = camp.squad[i]
		if not entry.alive:
			continue
		var d: Array = entry.def
		var m := Mech.new()
		m.setup(d[0], entry.pilot, d[3], entry.loadout.copy(), i == 0)
		m.hp = maxf(1.0, m.max_hp * entry.hp_ratio)
		m.position = world.start_pos + offsets[i]
		mech_layer.add_child(m)
		G.squad.append(m)
		if i == 0:
			G.player = m
			if G.bot_mode:
				m.brain = SquadBrain.new(m, "lead")
		else:
			m.brain = SquadBrain.new(m, d[2])

	var lighting := Lighting.new()
	add_child(lighting)
	if not ("--nolights" in OS.get_cmdline_user_args()):
		lighting.setup(world, G.squad)
	G.lighting = lighting

	var cam := GameCamera.new()
	add_child(cam)
	cam.global_position = G.player.position
	cam.make_current()
	G.camera = cam

	var director := Director.new()
	add_child(director)
	G.director = director
	director.populate_zone()

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
	mat.set_shader_parameter("fx_on", true)
	mat.set_shader_parameter("lit", lighting.vp != null)
	if lighting.vp:
		mat.set_shader_parameter("light_tex", lighting.light_texture())
	mat.set_shader_parameter("ambient", Vector3(Lighting.AMBIENT.r, Lighting.AMBIENT.g, Lighting.AMBIENT.b))

	var hl := CanvasLayer.new()
	hl.layer = 3
	add_child(hl)
	var hud := Hud.new()
	hl.add_child(hud)
	hud.process_mode = Node.PROCESS_MODE_ALWAYS   # keeps drawing the pause screen
	G.hud = hud
	var menu := FieldMenu.new()
	hl.add_child(menu)
	G.menu = menu
	var station := StationMenu.new()
	hl.add_child(station)
	G.station = station

	var edge := camp.current_edge(G.atlas)
	G.say("", "Leg %d: %s → %s through %s (threat %d/5)." % [camp.legs + 1, from_n.name, to_n.name, edge.zone, edge.threat], Color(0.7, 0.8, 0.7))
	var chatter := ["Scanners are quiet. Won't stay that way.", "Keep it tight. Long walk ahead.", "Eyes open. This zone's got teeth.", "Another day, another dead city."]
	var talker: Mech = G.squad[G.squad.size() - 1]
	if talker != G.player:
		G.say(talker.callsign, chatter[camp.legs % chatter.size()], talker.color.lightened(0.3))
	for mm in G.squad:
		G.say("", "%s armed: %s / %s" % [mm.callsign, PartsDB.part(mm.loadout.primary).get("short", "—"), PartsDB.part(mm.loadout.secondary).get("short", "—")], mm.color.darkened(0.1))
	if G.bot_mode and "--station" in OS.get_cmdline_user_args() and camp.legs == 0:
		_arrive.call_deferred()      # test hook: jump straight to the first station
	if G.bot_mode:
		print("[bot] LEG %d %s -> %s threat %d seed %d squad %d credits %d" % [camp.legs + 1, from_n.name, to_n.name, edge.threat, seed_value, G.squad.size(), camp.credits])


func _process(delta: float) -> void:
	if G.game_state == "station":
		return
	if G.game_state == "lost":
		if G.bot_mode:
			print("[bot] LOST leg %d at %.1fs — retrying" % [G.campaign.legs + 1, G.game_time])
			get_tree().reload_current_scene()
			return
		if Input.is_action_just_pressed("pause"):
			get_tree().reload_current_scene()        # retry this leg
		elif Input.is_action_just_pressed("new_campaign"):
			G.campaign = null
			get_tree().reload_current_scene()
		return
	if Input.is_action_just_pressed("toggle_director"):
		G.show_director = not G.show_director
	if Input.is_action_just_pressed("toggle_filter"):
		var fm: ShaderMaterial = filter_rect.material
		fm.set_shader_parameter("fx_on", not fm.get_shader_parameter("fx_on"))
	if Input.is_action_just_pressed("open_menu"):
		G.menu.toggle()
	elif G.menu.open:
		G.menu.handle_input()
	if Input.is_action_just_pressed("radar_zoom"):
		G.radar_zoom = (G.radar_zoom + 1) % Hud.RADAR_RANGES.size()
	if Input.is_action_just_pressed("overworld_toggle"):
		G.view_mode = 0 if G.view_mode == 2 else 2
	if G.menu.open:
		G.view_mode = 0
	else:
		_formation_input()
	G.tactical = false
	G.overworld = G.view_mode == 2
	if G.bot_mode:
		_bot_screenshots()

	if G.player.alive and G.world.goal_zone.has_point(G.player.position):
		_arrive()

	if G.bot_mode:
		_bot_refit_test()
		for pair in [[50.0, 1], [65.0, 2], [80.0, 3], [86.0, 0]]:
			if G.game_time >= pair[0] and G.game_time - delta < pair[0]:
				set_formation(pair[1])
				print("[bot] formation -> %s" % G.FORMATIONS[pair[1]])
		bot_report_t -= delta
		if bot_report_t <= 0.0:
			bot_report_t = 10.0
			var states := []
			for m in G.squad:
				states.append("%s:%s hp%.0f%% dodges%d" % [m.callsign, m.state_label if m.alive else "DEAD", m.hp_ratio() * 100, m.brain.dodges if m.brain else 0])
			print("[bot] t=%5.1f fps=%d prog=%.0f%% enemies=%d dir=%s int=%.0f mats=%s | %s" % [
				G.game_time, Engine.get_frames_per_second(), G.world.progress_of(G.player.position) * 100,
				G.enemies.alive_count(), Director.PHASE_NAMES[G.director.phase], G.director.intensity,
				str(G.materials), ", ".join(states)])
			var parts: Array = []
			for k in G.prof_avg:
				parts.append("%s %.2f" % [k, G.prof_avg[k]])
			print("[prof] frame %.2f ms | %s" % [G.fps_ms, ", ".join(parts)])


func _formation_input() -> void:
	var f := -1
	if Input.is_action_just_pressed("formation_cycle"):
		f = (G.formation + 1) % G.FORMATIONS.size()
	for pair in [["form_follow", 0], ["form_group", 1], ["form_spread", 2], ["form_hold", 3]]:
		if Input.is_action_just_pressed(pair[0]):
			f = pair[1]
	if f >= 0:
		set_formation(f)


func set_formation(f: int) -> void:
	G.formation = f
	G.hold_pos = G.player.position
	G.announce("SQUAD: " + G.FORMATIONS[f], Color(0.6, 0.9, 1.0))
	var talkers := G.alive_squad().filter(func(x): return x.brain != null and x != G.player)
	if not talkers.is_empty():
		talkers[randi() % talkers.size()].brain.bark("form_%d" % f, true)


func _arrive() -> void:
	var camp: Campaign = G.campaign
	var summary := camp.arrive(G.atlas, G.squad, G.materials, G.leg_kills)
	G.materials = camp.materials.duplicate()
	G.game_state = "station"
	G.menu.open = false
	G.view_mode = 0
	get_tree().paused = true
	G.station.open_station(summary)
	if G.bot_mode:
		print("[bot] ARRIVED %s at %.1fs (leg %d) kills=%d alive=%d +%d delivery +%d bounty credits=%d" % [
			G.atlas.nodes[camp.node_idx].name, G.game_time, camp.legs, G.kills, G.alive_squad().size(),
			summary.delivery, summary.bounty, camp.credits])
		_bot_shot("06_station")


func _bot_shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [a.substr(8), name])
			print("[bot] screenshot %s" % name)


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
		G.radar_zoom = 2
	elif t >= 40.0 and t < 44.0:
		G.view_mode = 2
	elif t >= 44.0 and t < 44.5:
		G.view_mode = 0
	var want := {"01_field": t > 3.0, "02_refit": t > 28.0, "03_radar_far": t > 39.5, "05_overworld": t > 43.5,
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
