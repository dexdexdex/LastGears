class_name Mech
extends Node2D
## A squad mech. Driven either by the player's input or by a SquadBrain.

class WeaponState:
	var id := ""
	var data := {}
	var ammo := 0
	var cooldown := 0.0
	var reload_t := 0.0

	func reload_total() -> float:
		return float(data.get("reload", 0.0))

var callsign := "VANGUARD"
var pilot := ""
var role_tag := ""
var color := Color(0.45, 0.85, 1.0)
var is_player := false
var loadout: Loadout
var stats := {}
var weapons := {"primary": null, "secondary": null}
var brain: SquadBrain

var hp := 100.0
var max_hp := 100.0
var shield := 0.0
var max_shield := 0.0
var shield_delay := 0.0
var heat := 0.0
var overheated := 0.0
var radius := 11.0
var vel := Vector2.ZERO
var facing := Vector2.RIGHT
var move_input := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var aim_dist := 300.0
var want_primary := false
var want_secondary := false
var alive := true
var busy_menu := false
var walk_phase := 0.0
var damage_flash := 0.0
var last_hit_time := -99.0
var muzzle_flash := 0.0
var kills := 0
var state_label := "FOLLOWING"

# Field work: { slot_key: {"part": id, "t": remaining, "total": total} }
var installing := {}
var repairing := 0.0
var repair_beam_target: Mech = null

# Dodge roll: short burst, brief invulnerability, cooldown, some heat.
const DODGE_TIME := 0.32
const DODGE_IFRAMES := 0.24
const DODGE_COOLDOWN := 2.0
const DODGE_HEAT := 10.0
var _last_flash := -1.0
var want_dodge := false
var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector2.ZERO
var dodge_speed := 0.0
var ghosts: Array = []            # afterimage positions (global)


func setup(p_callsign: String, p_pilot: String, p_color: Color, p_loadout: Loadout, p_player: bool) -> void:
	callsign = p_callsign
	pilot = p_pilot
	color = p_color
	loadout = p_loadout
	is_player = p_player
	apply_loadout(true)


func apply_loadout(full: bool = false) -> void:
	var ratio := hp / max_hp if max_hp > 0 else 1.0
	stats = loadout.compute()
	max_hp = stats.hp
	hp = max_hp if full else clampf(max_hp * ratio, 1.0, max_hp)
	max_shield = stats.shield
	shield = minf(shield, max_shield) if not full else max_shield
	radius = float(PartsDB.CHASSIS[loadout.chassis_id]["radius"])
	for key in ["primary", "secondary"]:
		var id := loadout.get_slot(key)
		if id == "":
			weapons[key] = null
			continue
		var ws: WeaponState = weapons[key]
		var keep_ammo := ws != null and ws.id == id
		if ws == null or ws.id != id:
			ws = WeaponState.new()
		ws.id = id
		ws.data = loadout.weapon_stats(id, stats)
		if not keep_ammo or full:
			ws.ammo = int(ws.data.mag)
			ws.reload_t = 0.0
		ws.ammo = mini(ws.ammo, int(ws.data.mag))
		weapons[key] = ws


func speed() -> float:
	var s: float = stats.speed
	if overheated > 0.0:
		s *= 0.45
	if busy_menu or repairing > 0.0:
		s = 0.0
	return s


func _physics_process(delta: float) -> void:
	if not alive or G.game_state != "play":
		return
	if brain:
		brain.think(delta)
	elif is_player:
		_read_player_input()

	# heat
	heat = maxf(0.0, heat - float(stats.cooling) * delta + float(stats.heat_passive) * delta)
	if overheated > 0.0:
		overheated -= delta
		heat = maxf(heat - 18.0 * delta, 0.0)
	elif heat >= 100.0:
		overheated = 2.6
		heat = 100.0
		G.say(callsign, "Overheat! Venting!", Color(1, 0.5, 0.3))

	# dodge
	dodge_cd = maxf(0.0, dodge_cd - delta)
	if want_dodge:
		want_dodge = false
		try_dodge()
	if dodge_t > 0.0:
		dodge_t -= delta
		if Engine.get_physics_frames() % 2 == 0:
			ghosts.append(position)
		var k := clampf(dodge_t / DODGE_TIME, 0.0, 1.0)
		vel = dodge_dir * dodge_speed * (0.35 + 0.65 * k)
		if dodge_t <= 0.0:
			vel = dodge_dir * speed() * 0.6
	if dodge_t <= 0.0 and not ghosts.is_empty() and Engine.get_physics_frames() % 3 == 0:
		ghosts.pop_front()

	# movement
	var target_v := move_input.limit_length(1.0) * speed()
	var accel := 520.0 if target_v.length() > vel.length() else 900.0
	if dodge_t <= 0.0:
		vel = vel.move_toward(target_v, accel * delta)
	position = G.world.move_circle(position, vel * delta, radius)
	_separate()
	if vel.length() > 8.0:
		facing = facing.slerp(vel.normalized(), clampf(6.0 * delta, 0, 1))
		walk_phase += vel.length() * delta * 0.09

	# shields / regen
	shield_delay -= delta
	if max_shield > 0 and shield_delay <= 0.0:
		shield = minf(max_shield, shield + 14.0 * delta)
	if stats.regen > 0:
		hp = minf(max_hp, hp + float(stats.regen) * delta)

	_update_installs(delta)
	_update_weapons(delta)
	if want_primary:
		fire("primary")
	if want_secondary:
		fire("secondary")

	damage_flash = maxf(0.0, damage_flash - delta * 4.0)
	muzzle_flash = maxf(0.0, muzzle_flash - delta * 12.0)
	queue_redraw()


func _read_player_input() -> void:
	if busy_menu:
		move_input = Vector2.ZERO
		want_primary = false
		want_secondary = false
		return
	move_input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.25:
		aim_dir = rs.normalized()
		aim_dist = lerpf(140.0, 600.0, clampf((rs.length() - 0.25) / 0.7, 0, 1))
	elif G.using_mouse:
		var m := get_global_mouse_position() - global_position
		if m.length() > 4.0:
			aim_dir = m.normalized()
			aim_dist = m.length()
	if Input.is_action_just_pressed("dodge") and G.game_time - G.menu_closed_t > 0.25:
		want_dodge = true
	want_primary = Input.is_action_pressed("fire_primary")
	want_secondary = Input.is_action_pressed("fire_secondary")


func _separate() -> void:
	for m in G.squad:
		if m == self or not m.alive:
			continue
		var d: Vector2 = position - m.position
		var min_d: float = radius + m.radius + 4.0
		var l := d.length()
		if l < min_d and l > 0.01:
			position = G.world.move_circle(position, d / l * (min_d - l) * 0.5, radius)


func _update_weapons(delta: float) -> void:
	for key in ["primary", "secondary"]:
		var ws: WeaponState = weapons[key]
		if ws == null:
			continue
		ws.cooldown -= delta
		if ws.reload_t > 0.0:
			ws.reload_t -= delta
			if ws.reload_t <= 0.0:
				ws.ammo = int(ws.data.mag)


func can_dodge() -> bool:
	return alive and dodge_t <= 0.0 and dodge_cd <= 0.0 and overheated <= 0.0 \
		and not busy_menu and repairing <= 0.0


func try_dodge(dir: Vector2 = Vector2.ZERO) -> bool:
	if not can_dodge():
		return false
	if dir == Vector2.ZERO:
		dir = move_input if move_input.length() > 0.2 else -aim_dir
	dodge_dir = dir.normalized()
	# lighter, faster frames roll further
	dodge_speed = 250.0 + float(stats.speed) * 1.3
	dodge_t = DODGE_TIME
	dodge_cd = DODGE_COOLDOWN
	heat += DODGE_HEAT
	ghosts.clear()
	G.projectiles.add_fx("puff", position, radius * 1.6, Color(0.55, 0.52, 0.45), 0.5)
	return true


func is_invulnerable() -> bool:
	return dodge_t > DODGE_TIME - DODGE_IFRAMES


func can_fire(key: String) -> bool:
	var ws: WeaponState = weapons[key]
	if ws == null or installing.has(key) or overheated > 0.0 or busy_menu or repairing > 0.0 or dodge_t > 0.0:
		return false
	return ws.reload_t <= 0.0 and ws.cooldown <= 0.0


func fire(key: String) -> void:
	if not can_fire(key):
		return
	var ws: WeaponState = weapons[key]
	var d := ws.data
	if int(d.mag) > 0 and ws.ammo <= 0:
		ws.reload_t = ws.reload_total()
		return
	ws.cooldown = 1.0 / maxf(float(d.rof), 0.05)
	heat += float(d.heat)
	var muzzle := position + aim_dir * (radius + 6.0)
	for i in int(d.pellets):
		var spread := deg_to_rad(float(d.spread)) * 0.5
		var dir := aim_dir.rotated(randf_range(-spread, spread))
		G.projectiles.spawn_shot(muzzle, dir, d, 0, self, position + aim_dir * aim_dist)
	if int(d.mag) > 0:
		ws.ammo -= 1
		if ws.ammo <= 0:
			ws.reload_t = ws.reload_total()
	muzzle_flash = 1.0
	if G.lighting and G.game_time - _last_flash > 0.15:
		_last_flash = G.game_time
		G.lighting.flash(position + aim_dir * 30.0, 120.0, 0.45)


func manual_reload() -> void:
	for key in ["primary", "secondary"]:
		var ws: WeaponState = weapons[key]
		if ws and int(ws.data.mag) > 0 and ws.ammo < int(ws.data.mag) and ws.reload_t <= 0:
			ws.reload_t = ws.reload_total()


# ---------------------------------------------------------------- field refit

func begin_install(slot_key: String, part_id: String) -> void:
	var t := PartsDB.install_time(part_id)
	installing[slot_key] = {"part": part_id, "t": t, "total": t}


func begin_repair() -> void:
	repairing = PartsDB.REPAIR_TIME


func _update_installs(delta: float) -> void:
	for key in installing.keys():
		installing[key].t -= delta
		if installing[key].t <= 0.0:
			loadout.set_slot(key, installing[key].part)
			installing.erase(key)
			apply_loadout()
			if is_player:
				var nm: String = PartsDB.part(loadout.get_slot(key)).get("name", "Slot cleared")
				G.say(callsign, "%s online." % nm, Color(0.6, 1.0, 0.7))
	if repairing > 0.0:
		repairing -= delta
		hp = minf(max_hp, hp + PartsDB.REPAIR_AMOUNT / PartsDB.REPAIR_TIME * delta)


func receive_repair(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


# ---------------------------------------------------------------- damage

func take_damage(amount: float, _from: Vector2 = Vector2.ZERO) -> void:
	if not alive:
		return
	if is_invulnerable():
		return
	shield_delay = 3.0
	if shield > 0.0:
		var a := minf(shield, amount)
		shield -= a
		amount -= a
	hp -= amount
	damage_flash = 1.0
	last_hit_time = G.game_time
	if G.director:
		G.director.report_damage(amount, self)
	if is_player and amount > 6.0 and G.camera:
		G.camera.shake(minf(amount / 30.0, 0.6))
	if hp <= 0.0:
		die()


func die() -> void:
	alive = false
	hp = 0
	G.projectiles.add_fx("explosion", position, 70.0, Color(1, 0.6, 0.3), 0.9)
	G.projectiles.add_fx("wreck", position, radius, color.darkened(0.6), 9999.0)
	if G.camera:
		G.camera.shake(0.7)
	visible = false
	if is_player:
		G.say(callsign, "I'm going down—", Color(1, 0.35, 0.3))
		G.game_state = "lost"
		G.announce("VANGUARD LOST", Color(1, 0.35, 0.3))
	else:
		G.say(callsign, "%s is down!" % callsign, Color(1, 0.35, 0.3))
		for m in G.squad:
			if m.alive and m.brain:
				m.brain.on_ally_down(self)


func hp_ratio() -> float:
	return hp / max_hp if max_hp > 0 else 0.0


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var col := color
	if damage_flash > 0.0:
		col = col.lerp(Color.WHITE, damage_flash * 0.7)
	var side := facing.orthogonal()
	var r := radius
	# aim cone edges, so you can tell whose light is whose
	if alive:
		for sgn in [-1.0, 1.0]:
			var ed := aim_dir.rotated(Lighting.VIS_HALF * sgn)
			draw_line(ed * (r + 8.0), ed * 170.0, Color(color, 0.22), 1.0)
	# dodge afterimages
	for i in ghosts.size():
		var gp: Vector2 = ghosts[i] - position
		draw_circle(gp, r * 0.9, Color(col, 0.08 + 0.22 * float(i + 1) / ghosts.size()))
	# shadow
	draw_circle(Vector2(3, 4), r + 2, Color(0, 0, 0, 0.35))
	# legs (stomp animation)
	var stride := sin(walk_phase) * r * 0.55
	for s in [-1.0, 1.0]:
		var base: Vector2 = side * s * r * 0.75
		var foot: Vector2 = base + facing * stride * s
		draw_line(base * 0.6, foot, col.darkened(0.5), 3.0)
		_draw_rot_rect(foot, facing, Vector2(r * 0.55, r * 0.35), col.darkened(0.35))
	# hull
	var pts := PackedVector2Array()
	for i in 8:
		var a := facing.angle() + TAU * (i + 0.5) / 8.0
		var rr := r * (0.95 if i % 2 == 0 else 0.8)
		pts.append(Vector2.from_angle(a) * rr)
	draw_colored_polygon(pts, col.darkened(0.55))
	pts.append(pts[0])
	draw_polyline(pts, col, 1.6)
	# heat glow
	if heat > 55.0:
		var hcol := Color(1, 0.45, 0.15, (heat - 55.0) / 45.0 * 0.55)
		draw_circle(Vector2.ZERO, r * 0.6, hcol)
	# turret + barrels
	draw_circle(Vector2.ZERO, r * 0.45, col)
	var perp := aim_dir.orthogonal()
	draw_line(perp * 3.0, perp * 3.0 + aim_dir * (r + 7.0), col.lightened(0.2), 2.5)
	if weapons["secondary"] != null:
		draw_line(-perp * 3.5, -perp * 3.5 + aim_dir * (r + 2.0), col.darkened(0.1), 3.5)
	if muzzle_flash > 0.0:
		draw_circle(aim_dir * (r + 8.0), 4.0 * muzzle_flash, Color(1, 0.9, 0.6, muzzle_flash))
	# shield
	if shield > 1.0:
		draw_arc(Vector2.ZERO, r + 5.0, 0, TAU, 28, Color(0.4, 0.85, 1.0, 0.25 + 0.35 * shield / max_shield), 1.5)
	# player marker
	if is_player:
		var t := Time.get_ticks_msec() / 1000.0
		draw_arc(Vector2.ZERO, r + 9.0 + sin(t * 4.0), -0.4, 0.4, 6, Color(col, 0.7), 1.5)
		draw_arc(Vector2.ZERO, r + 9.0 + sin(t * 4.0), PI - 0.4, PI + 0.4, 6, Color(col, 0.7), 1.5)
		# aim reticle along stick
		var ws: WeaponState = weapons["secondary"]
		if ws and ws.data.get("lob", false):
			var tp := aim_dir * clampf(aim_dist, ws.data.get("min_range", 0.0), ws.data.range)
			draw_arc(tp, 10, 0, TAU, 16, Color(1, 0.6, 0.3, 0.45), 1.0)
		draw_circle(aim_dir * 70.0, 1.8, Color(col, 0.6))
	# health bar
	var bw := 26.0
	var by := -r - 10.0
	draw_rect(Rect2(Vector2(-bw / 2, by), Vector2(bw, 3)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(Vector2(-bw / 2, by), Vector2(bw * hp_ratio(), 3)), Color(0.4, 1.0, 0.5) if hp_ratio() > 0.35 else Color(1, 0.35, 0.3))
	# callsign
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-bw / 2, by - 3), callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col, 0.85))
	# field work progress
	var work := 0.0
	for k in installing:
		work = maxf(work, 1.0 - installing[k].t / installing[k].total)
	if repairing > 0.0:
		work = 1.0 - repairing / PartsDB.REPAIR_TIME
	if not installing.is_empty() or repairing > 0.0:
		draw_arc(Vector2.ZERO, r + 4.0, -PI / 2, -PI / 2 + TAU * work, 24, Color(0.6, 1.0, 0.7, 0.9), 2.0)
	if overheated > 0.0 and int(Time.get_ticks_msec() / 150) % 2 == 0:
		draw_string(font, Vector2(-20, r + 16), "OVERHEAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.5, 0.3))
	# repair beam
	if repair_beam_target and repair_beam_target.alive:
		var tp2 := repair_beam_target.position - position
		draw_dashed_line(Vector2.ZERO, tp2, Color(0.5, 1.0, 0.6, 0.6), 1.5, 5.0)


func _draw_rot_rect(center: Vector2, dir: Vector2, half: Vector2, col: Color) -> void:
	var s := dir.orthogonal()
	var pts := PackedVector2Array([
		center + dir * half.x + s * half.y,
		center + dir * half.x - s * half.y,
		center - dir * half.x - s * half.y,
		center - dir * half.x + s * half.y,
	])
	draw_colored_polygon(pts, col)
