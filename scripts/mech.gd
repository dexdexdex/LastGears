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
	_shape_r = -1.0
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
	if G.world and G.world.in_water(position):
		s *= 0.62
	return s


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_body(delta)
	G.pe("mechs+AI", _t0)


func _process_body(delta: float) -> void:
	delta = minf(delta, 0.05)
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
		if Engine.get_process_frames() % 2 == 0:
			ghosts.append(position)
		var k := clampf(dodge_t / DODGE_TIME, 0.0, 1.0)
		vel = dodge_dir * dodge_speed * (0.35 + 0.65 * k)
		if dodge_t <= 0.0:
			vel = dodge_dir * speed() * 0.6
	if dodge_t <= 0.0 and not ghosts.is_empty() and Engine.get_process_frames() % 3 == 0:
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
	var _t0 := Time.get_ticks_usec()
	_draw_body()
	G.pe("mechs draw", _t0)


# ---------------------------------------------------------------- look

# Silhouettes in "facing space" (x = forward, y = side), unit radius,
# rounded with Chaikin smoothing for a clean abstract look.
const SHAPES := {
	"vanguard": [Vector2(1.05, 0), Vector2(0.55, 0.62), Vector2(-0.5, 0.78), Vector2(-0.92, 0.36), Vector2(-0.92, -0.36), Vector2(-0.5, -0.78), Vector2(0.55, -0.62)],
	"bulwark": [Vector2(0.9, 0), Vector2(0.62, 0.86), Vector2(-0.5, 0.98), Vector2(-0.98, 0.46), Vector2(-0.98, -0.46), Vector2(-0.5, -0.98), Vector2(0.62, -0.86)],
	"kestrel": [Vector2(1.25, 0), Vector2(0.2, 0.52), Vector2(-0.72, 0.84), Vector2(-0.42, 0.18), Vector2(-0.82, 0), Vector2(-0.42, -0.18), Vector2(-0.72, -0.84), Vector2(0.2, -0.52)],
	"sparrow": [Vector2(1.05, 0), Vector2(0.12, 0.72), Vector2(-0.78, 0.82), Vector2(-0.52, 0), Vector2(-0.78, -0.82), Vector2(0.12, -0.72)],
}
const LEGS := {"vanguard": 4, "bulwark": 4, "kestrel": 2, "sparrow": 2}
var _shape := PackedVector2Array()
var _inner := PackedVector2Array()
var _shape_r := -1.0


static func _chaikin(pts: Array, iters: int) -> Array:
	var cur := pts
	for it in iters:
		var nxt: Array = []
		for i in cur.size():
			var p0: Vector2 = cur[i]
			var p1: Vector2 = cur[(i + 1) % cur.size()]
			nxt.append(p0.lerp(p1, 0.25))
			nxt.append(p0.lerp(p1, 0.75))
		cur = nxt
	return cur


func _ensure_shape() -> void:
	if is_equal_approx(_shape_r, radius) and not _shape.is_empty():
		return
	_shape_r = radius
	var base: Array = _chaikin(SHAPES.get(loadout.chassis_id, SHAPES["vanguard"]), 2)
	_shape = PackedVector2Array()
	_inner = PackedVector2Array()
	for v in base:
		_shape.append(v * radius * 1.25)
		_inner.append(v * radius * 0.7 + Vector2(-radius * 0.12, 0))


func _draw_body() -> void:
	_ensure_shape()
	var r := radius
	var col := color
	if damage_flash > 0.0:
		col = col.lerp(Color.WHITE, damage_flash * 0.7)
	var hot := clampf((heat - 45.0) / 55.0, 0.0, 1.0)
	var rim := col.lerp(Color(1.0, 0.5, 0.2), hot * 0.7)
	var t := Time.get_ticks_msec() / 1000.0

	# aim cone edges, so you can tell whose light is whose
	if alive:
		var e1 := aim_dir.rotated(Lighting.VIS_HALF)
		var e2 := aim_dir.rotated(-Lighting.VIS_HALF)
		draw_multiline(PackedVector2Array([e1 * (r + 10.0), e1 * 170.0, e2 * (r + 10.0), e2 * 170.0]), Color(color, 0.2), 1.0)
	# dodge afterimages: silhouette ghosts
	for i in ghosts.size():
		var k := float(i + 1) / ghosts.size()
		draw_set_transform(ghosts[i] - position, facing.angle(), Vector2.ONE)
		draw_colored_polygon(_shape, Color(col, 0.06 + 0.16 * k))
	var dot := EnemyManager.dot_texture()
	match _style():
		1: _style_glyph(col, rim, hot, t, dot)
		2: _style_monolith(col, rim, hot, t, dot)
		3: _style_orb(col, rim, hot, t, dot)
		_: _style_hull(col, rim, hot, t, dot)
	if muzzle_flash > 0.0:
		draw_circle(aim_dir * (r + 11.0), 5.0 * muzzle_flash, Color(1, 0.92, 0.65, muzzle_flash))

	# shield: segmented shimmer ring
	if shield > 1.0:
		var sa := 0.2 + 0.4 * shield / max_shield
		var segs := PackedVector2Array()
		for k3 in 6:
			var a0 := t * 0.8 + TAU * k3 / 6.0
			for q in 4:
				var qa := a0 + (TAU / 6.0 - 0.25) * q / 4.0
				var qb := a0 + (TAU / 6.0 - 0.25) * (q + 1) / 4.0
				segs.append(Vector2.from_angle(qa) * (r + 6.0))
				segs.append(Vector2.from_angle(qb) * (r + 6.0))
		draw_multiline(segs, Color(0.45, 0.85, 1.0, sa), 1.5)
	# player marker
	if is_player:
		var rr := r + 10.0 + sin(t * 4.0)
		draw_arc(Vector2.ZERO, rr, -0.4, 0.4, 8, Color(col, 0.7), 1.5, true)
		draw_arc(Vector2.ZERO, rr, PI - 0.4, PI + 0.4, 8, Color(col, 0.7), 1.5, true)
		var ws: WeaponState = weapons["secondary"]
		if ws and ws.data.get("lob", false):
			var tp := aim_dir * clampf(aim_dist, ws.data.get("min_range", 0.0), ws.data.range)
			draw_arc(tp, 10, 0, TAU, 16, Color(1, 0.6, 0.3, 0.45), 1.0, true)
		draw_circle(aim_dir * 70.0, 1.8, Color(col, 0.6))
	# health: slim bar + small label
	var bw := 24.0
	var by := -r - 12.0
	draw_rect(Rect2(-bw / 2, by - 1.5, bw, 3.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-bw / 2, by - 1.0, bw * hp_ratio(), 2.0), Color(0.45, 1.0, 0.6) if hp_ratio() > 0.35 else Color(1, 0.35, 0.3))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-bw / 2, by - 4), callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(col, 0.7))
	# field work progress
	var work := 0.0
	for k in installing:
		work = maxf(work, 1.0 - installing[k].t / installing[k].total)
	if repairing > 0.0:
		work = 1.0 - repairing / PartsDB.REPAIR_TIME
	if not installing.is_empty() or repairing > 0.0:
		draw_arc(Vector2.ZERO, r + 4.0, -PI / 2, -PI / 2 + TAU * work, 24, Color(0.6, 1.0, 0.7, 0.9), 2.0, true)
	if overheated > 0.0 and int(Time.get_ticks_msec() / 150) % 2 == 0:
		draw_string(font, Vector2(-20, r + 16), "OVERHEAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.5, 0.3))
	# repair beam
	if repair_beam_target and repair_beam_target.alive:
		var tp2 := repair_beam_target.position - position
		draw_dashed_line(Vector2.ZERO, tp2, Color(0.5, 1.0, 0.6, 0.6), 1.5, 5.0)


# ---------------------------------------------------------------- styles
# G.mech_style picks the look (F6 cycles in game): 0 Hull, 1 Glyph,
# 2 Monolith, 3 Orb. style_override (>= 0) forces one (gallery).
const STYLE_NAMES := ["HULL", "GLYPH", "MONOLITH", "ORB"]
var style_override := -1


func _style() -> int:
	return style_override if style_override >= 0 else G.mech_style


func _style_hull(col: Color, rim: Color, hot: float, t: float, dot: Texture2D) -> void:
	var r := radius
	# soft shadow
	draw_set_transform(Vector2(3, 5), facing.angle(), Vector2.ONE)
	draw_colored_polygon(_shape, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2.ONE)

	# legs: articulated, abstract
	var nl: int = LEGS.get(loadout.chassis_id, 2)
	var legc := col.darkened(0.35)
	var leg_pts := PackedVector2Array()
	var joints: Array = []
	for li in nl:
		var sgn2 := -1.0 if li % 2 == 0 else 1.0
		var fore := 0.0 if nl == 2 else (0.38 if li < 2 else -0.38)
		var phase := walk_phase + (0.0 if (li % 2 == 0) == (li < 2) else PI)
		var hip := Vector2(fore * r, sgn2 * r * 0.55)
		var foot := Vector2(fore * r + sin(phase) * r * 0.42, sgn2 * r * 1.12)
		var knee := (hip + foot) * 0.5 + Vector2(r * 0.12, sgn2 * r * 0.28)
		leg_pts.append_array([hip, knee, knee, foot])
		joints.append([foot, 1.6])
		joints.append([knee, 1.0])
	draw_multiline(leg_pts, legc, 2.0)
	for j in joints:
		var jr: float = j[1]
		draw_texture_rect(dot, Rect2(j[0] - Vector2(jr, jr), Vector2(jr, jr) * 2.0), false, col.darkened(0.25))

	# hull: gradient fill (lighter toward the front), inset panel, clean rim
	var cols := PackedColorArray()
	for v in _shape:
		var k2 := clampf((v.x / r + 1.0) * 0.5, 0.0, 1.0)
		cols.append(col.darkened(0.72).lerp(col.darkened(0.18), k2))
	draw_polygon(_shape, cols)
	draw_colored_polygon(_inner, Color(col.darkened(0.78), 0.95))
	var outline := _shape.duplicate()
	outline.append(_shape[0])
	draw_polyline(outline, rim, 1.4, true)
	var inl := _inner.duplicate()
	inl.append(_inner[0])
	draw_polyline(inl, Color(rim, 0.35), 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# core: glows, pulses, runs orange when hot
	var core_c := col.lightened(0.45).lerp(Color(1.0, 0.55, 0.2), hot)
	var pulse := 0.5 + 0.5 * sin(t * (3.0 + hot * 6.0))
	var core_p := -facing * r * 0.35
	var gr := r * (0.26 + 0.05 * pulse)
	draw_texture_rect(dot, Rect2(core_p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(core_c, 0.16 + 0.12 * hot))
	var cr := r * 0.12
	draw_texture_rect(dot, Rect2(core_p - Vector2(cr, cr), Vector2(cr, cr) * 2.0), false, core_c)

	# weapons: barrels match the fitted gun, kick back on fire
	var perp := aim_dir.orthogonal()
	var kick := muzzle_flash * 3.0
	var wp: WeaponState = weapons["primary"]
	if wp:
		var id: String = wp.id
		var blen := r + (16.0 if id == "railgun" else (6.0 if id in ["flak", "flamer"] else 10.0)) - kick
		var base_p := perp * 2.5
		if id in ["gatling", "autocannon", "swarm"]:
			for o in [-1.6, 1.6]:
				draw_line(base_p + perp * o + aim_dir * r * 0.2, base_p + perp * o + aim_dir * blen, col.lightened(0.25), 1.6, true)
		else:
			draw_line(base_p + aim_dir * r * 0.2, base_p + aim_dir * blen, col.lightened(0.25), 3.0 if id in ["flak", "flamer", "rockets", "railgun"] else 2.2, true)
		draw_circle(base_p + aim_dir * blen, 1.6, col.lightened(0.5))
	var ws2: WeaponState = weapons["secondary"]
	if ws2:
		var sb := -perp * 4.5
		draw_line(sb + aim_dir * r * 0.1, sb + aim_dir * (r + 2.0 - kick * 0.5), col.darkened(0.05), 4.0, true)
		draw_circle(sb + aim_dir * (r + 2.0 - kick * 0.5), 2.0, col.lightened(0.2))
	draw_circle(Vector2.ZERO, r * 0.24, col.darkened(0.55))
	draw_arc(Vector2.ZERO, r * 0.24, 0, TAU, 18, Color(col.lightened(0.2), 0.9), 1.1, true)


func _barrels(col: Color, r: float, kick: float, thin: bool) -> void:
	var perp := aim_dir.orthogonal()
	var wp: WeaponState = weapons["primary"]
	if wp:
		var id: String = wp.id
		var blen := r + (16.0 if id == "railgun" else (6.0 if id in ["flak", "flamer"] else 10.0)) - kick
		var base_p := perp * 2.5
		var pts := PackedVector2Array()
		if id in ["gatling", "autocannon", "swarm"]:
			for o in [-1.6, 1.6]:
				pts.append_array([base_p + perp * o + aim_dir * r * 0.2, base_p + perp * o + aim_dir * blen])
			draw_multiline(pts, col, 1.2 if thin else 1.6)
		else:
			draw_line(base_p + aim_dir * r * 0.2, base_p + aim_dir * blen, col, (1.4 if thin else (3.0 if id in ["flak", "flamer", "rockets", "railgun"] else 2.2)), true)
	var ws2: WeaponState = weapons["secondary"]
	if ws2:
		var sb := -perp * 4.5
		draw_line(sb + aim_dir * r * 0.1, sb + aim_dir * (r + 2.0 - kick * 0.5), col.darkened(0.15), 1.4 if thin else 3.5, true)


func _style_glyph(col: Color, rim: Color, hot: float, t: float, dot: Texture2D) -> void:
	## Vector line-art: luminous outlines, no mass. Reads like a tactical display.
	var r := radius
	var lc := col.lightened(0.25).lerp(Color(1.0, 0.55, 0.2), hot * 0.6)
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2.ONE)
	draw_colored_polygon(_shape, Color(col, 0.10))
	var o1 := _shape.duplicate()
	o1.append(_shape[0])
	draw_polyline(o1, Color(lc, 0.95), 1.5, true)
	var o2 := _inner.duplicate()
	o2.append(_inner[0])
	draw_polyline(o2, Color(lc, 0.35), 1.0, true)
	# stride ticks instead of legs
	var nl: int = LEGS.get(loadout.chassis_id, 2)
	var ticks := PackedVector2Array()
	for li in nl:
		var sgn2 := -1.0 if li % 2 == 0 else 1.0
		var fore := 0.0 if nl == 2 else (0.38 if li < 2 else -0.38)
		var ph := walk_phase + (0.0 if (li % 2 == 0) == (li < 2) else PI)
		var base := Vector2((fore + sin(ph) * 0.25) * r, sgn2 * r * 1.05)
		ticks.append_array([base, base + Vector2(0, sgn2 * r * 0.35)])
	draw_multiline(ticks, Color(lc, 0.7), 1.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# diamond core aligned to aim
	var d := aim_dir * r * 0.3
	var n := aim_dir.orthogonal() * r * 0.2
	var core_c := col.lightened(0.5).lerp(Color(1.0, 0.55, 0.2), hot)
	draw_colored_polygon(PackedVector2Array([d, n, -d, -n]), core_c)
	# aim line with a chevron at the tip
	var kick := muzzle_flash * 3.0
	var tip := aim_dir * (r + 12.0 - kick)
	var ch := aim_dir.orthogonal() * 3.0
	draw_multiline(PackedVector2Array([aim_dir * r * 0.35, tip, tip - aim_dir * 4.0 + ch, tip, tip - aim_dir * 4.0 - ch, tip]), Color(lc, 0.95), 1.3)
	if weapons["secondary"] != null:
		var sp := -aim_dir.orthogonal() * 5.0 + aim_dir * r * 0.7
		draw_texture_rect(dot, Rect2(sp - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), false, Color(lc, 0.8))


func _style_monolith(col: Color, rim: Color, hot: float, t: float, dot: Texture2D) -> void:
	## Flat, solid, sculpted: two-tone lit from the upper left, no outlines,
	## a glowing visor slit that tracks the aim.
	var r := radius
	var light := Vector2(-0.6, -0.8)
	draw_set_transform(Vector2(4, 6), facing.angle(), Vector2.ONE)
	draw_colored_polygon(_shape, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, facing.angle(), Vector2.ONE)
	var cols := PackedColorArray()
	var dark := col.darkened(0.62)
	var lit := col.darkened(0.05)
	for v in _shape:
		var wv := v.rotated(facing.angle())
		var k := clampf(0.5 + 0.5 * wv.normalized().dot(light), 0.0, 1.0)
		cols.append(dark.lerp(lit, k * k))
	draw_polygon(_shape, cols)
	# accent stripe
	draw_line(Vector2(-r * 0.35, -r * 0.55), Vector2(-r * 0.35, r * 0.55), Color(col.lightened(0.45), 0.55), 1.0)
	# pads instead of legs (hovering slabs)
	var nl: int = LEGS.get(loadout.chassis_id, 2)
	for li in nl:
		var sgn2 := -1.0 if li % 2 == 0 else 1.0
		var fore := 0.0 if nl == 2 else (0.38 if li < 2 else -0.38)
		var ph := walk_phase + (0.0 if (li % 2 == 0) == (li < 2) else PI)
		var pc := Vector2((fore + sin(ph) * 0.12) * r, sgn2 * r * 1.0)
		draw_texture_rect(dot, Rect2(pc - Vector2(r * 0.26, r * 0.16), Vector2(r * 0.52, r * 0.32)), false, col.darkened(0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# visor slit toward aim
	var vc := col.lightened(0.6).lerp(Color(1.0, 0.55, 0.2), hot)
	var a0 := aim_dir * r * 0.15
	var a1 := aim_dir * r * 0.8
	var w := aim_dir.orthogonal() * 1.4
	draw_colored_polygon(PackedVector2Array([a0 + w, a1 + w * 0.6, a1 - w * 0.6, a0 - w]), vc)
	var gr := r * 0.5
	draw_texture_rect(dot, Rect2(a1 - Vector2(gr, gr) * 0.5, Vector2(gr, gr)), false, Color(vc, 0.25 + 0.15 * sin(t * 4.0)))
	_barrels(col.darkened(0.2), r, muzzle_flash * 3.0, false)


func _style_orb(col: Color, rim: Color, hot: float, t: float, dot: Texture2D) -> void:
	## Hovering sphere drone: soft shaded body, rotating armour plates, one eye.
	var r := radius
	var hover := sin(t * 2.2 + float(hash(callsign) % 100)) * 1.2
	draw_texture_rect(dot, Rect2(Vector2(-r * 0.95, r * 0.35 + 3.0), Vector2(r * 1.9, r * 0.9)), false, Color(0, 0, 0, 0.35))
	var c := Vector2(0, -hover)
	var br := r * 0.82
	draw_texture_rect(dot, Rect2(c - Vector2(br, br), Vector2(br, br) * 2.0), false, col.darkened(0.6))
	var sh := br * 0.62
	draw_texture_rect(dot, Rect2(c + Vector2(-br * 0.38, -br * 0.42) - Vector2(sh, sh), Vector2(sh, sh) * 2.0), false, Color(col.darkened(0.15), 0.55))
	# armour plates orbit with the walk and turn with facing
	var spin := facing.angle() + walk_phase * 0.15
	var plates := 3 if loadout.chassis_id in ["bulwark", "vanguard"] else 2
	var pc := col.lerp(Color(1.0, 0.5, 0.2), hot * 0.6)
	for k in plates:
		var a := spin + TAU * k / plates
		draw_arc(c, r * 1.08, a - 0.55, a + 0.55, 10, pc, 3.0, true)
	draw_arc(c, r * 1.08, 0, TAU, 32, Color(pc, 0.18), 1.0, true)
	# the eye
	var ec := col.lightened(0.65).lerp(Color(1.0, 0.55, 0.2), hot)
	var ep := c + aim_dir * r * 0.42
	var g2 := r * 0.42
	draw_texture_rect(dot, Rect2(ep - Vector2(g2, g2), Vector2(g2, g2) * 2.0), false, Color(ec, 0.25))
	var e2 := r * 0.17
	draw_texture_rect(dot, Rect2(ep - Vector2(e2, e2), Vector2(e2, e2) * 2.0), false, ec)
	var kick := muzzle_flash * 3.0
	draw_line(ep + aim_dir * e2, c + aim_dir * (r + 9.0 - kick), Color(ec, 0.8), 1.6, true)


func _draw_rot_rect(center: Vector2, dir: Vector2, half: Vector2, col: Color) -> void:
	var s := dir.orthogonal()
	var pts := PackedVector2Array([
		center + dir * half.x + s * half.y,
		center + dir * half.x - s * half.y,
		center - dir * half.x - s * half.y,
		center - dir * half.x + s * half.y,
	])
	draw_colored_polygon(pts, col)
