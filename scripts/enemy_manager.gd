class_name EnemyManager
extends Node2D
## The machine swarm. Hundreds of tiny dots simulated and drawn in one node.

const TYPES := {
	# Swarm fodder. Fast, fragile, bites.
	"skitter": {
		"name": "Skitter", "hp": 14.0, "speed": 150.0, "r": 3.0, "armor": 0.0,
		"color": Color(0.95, 0.28, 0.22), "melee": 7.0, "melee_cd": 0.6, "drop": 0.04,
	},
	# Ranged. Keeps its distance and lobs slow bolts.
	"spitter": {
		"name": "Spitter", "hp": 34.0, "speed": 70.0, "r": 4.0, "armor": 0.0,
		"color": Color(1.0, 0.62, 0.15), "ranged": true, "shot_dmg": 9.0, "shot_cd": 1.9,
		"keep": 250.0, "shot_speed": 270.0, "drop": 0.06,
	},
	# Suicide runner. Explodes on contact or death (and chains).
	"tick": {
		"name": "Tick", "hp": 16.0, "speed": 168.0, "r": 3.5, "armor": 0.0,
		"color": Color(1.0, 0.95, 0.35), "bomb": true, "bomb_dmg": 42.0, "bomb_r": 70.0, "drop": 0.04,
	},
	# Armoured brute. Shrugs off small rounds; slams.
	"warden": {
		"name": "Warden", "hp": 320.0, "speed": 54.0, "r": 8.0, "armor": 5.0,
		"color": Color(0.85, 0.35, 0.98), "melee": 34.0, "melee_cd": 1.4, "drop": 1.0,
	},
}

class Enemy:
	var type := ""
	var d := {}
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var r := 3.0
	var cd := 0.0
	var los_t := 0.0
	var los := false
	var target: Mech
	var alive := true
	var flash := 0.0
	var t := 0.0
	var jitter := 1.0
	var strafe := 1.0

var list: Array = []
var buckets := {}
const BUCKET := 48.0
var flow_timer := 0.0


func spawn(type: String, pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.type = type
	e.d = TYPES[type]
	e.pos = pos
	e.hp = e.d.hp * (1.0 + G.world.progress_of(pos) * 0.4)
	e.max_hp = e.hp
	e.r = e.d.r
	e.jitter = randf_range(0.85, 1.15)
	e.strafe = 1.0 if randf() < 0.5 else -1.0
	e.t = randf() * 10.0
	e.los_t = randf() * 0.4
	list.append(e)
	return e


func _physics_process(delta: float) -> void:
	if G.game_state != "play":
		return
	flow_timer -= delta
	if flow_timer <= 0.0:
		flow_timer = 0.45
		var srcs: Array = []
		for m in G.squad:
			if m.alive:
				srcs.append(m.position)
		G.world.update_flow(srcs)
	_rebuild_buckets()
	var alive_mechs := G.alive_squad()
	if alive_mechs.is_empty():
		return
	for e in list:
		if e.alive:
			_think(e, delta, alive_mechs)
	var keep: Array = []
	for e in list:
		if e.alive:
			keep.append(e)
	list = keep
	queue_redraw()


func _think(e: Enemy, delta: float, mechs: Array) -> void:
	e.t += delta
	e.cd -= delta
	e.flash = maxf(0.0, e.flash - delta * 6.0)
	# nearest mech
	var best: Mech = null
	var bd := INF
	for m in mechs:
		var dd: float = e.pos.distance_squared_to(m.position)
		if dd < bd:
			bd = dd
			best = m
	e.target = best
	var to_t := best.position - e.pos
	var dist := sqrt(bd)
	e.los_t -= delta
	if e.los_t <= 0.0:
		e.los_t = 0.35
		e.los = dist < 420.0 and G.world.has_los(e.pos, best.position)

	var desired := Vector2.ZERO
	var spd: float = e.d.speed * e.jitter
	if e.los:
		desired = to_t / maxf(dist, 0.01)
	else:
		desired = G.world.flow_dir(e.pos)
		if desired == Vector2.ZERO:
			desired = to_t / maxf(dist, 0.01)

	if e.d.get("ranged", false) and e.los:
		var keep: float = e.d.keep
		if dist < keep - 40.0:
			desired = -to_t.normalized()
		elif dist < keep + 60.0:
			desired = to_t.normalized().orthogonal() * e.strafe * 0.6
			if randf() < 0.005:
				e.strafe *= -1.0
		if dist < keep + 140.0 and e.cd <= 0.0:
			e.cd = e.d.shot_cd * randf_range(0.8, 1.2)
			var lead: Vector2 = best.position + best.vel * (dist / e.d.shot_speed) * 0.6
			G.projectiles.spawn_enemy_bolt(e.pos, (lead - e.pos).normalized(), e.d.shot_dmg, e.d.shot_speed)
	elif e.d.get("bomb", false):
		spd *= 1.0 + 0.4 * clampf(1.0 - dist / 200.0, 0, 1)
		if dist < best.radius + 14.0:
			kill(e, null)
			return
	elif e.d.has("melee") and dist < best.radius + e.r + 4.0:
		desired = Vector2.ZERO
		if e.cd <= 0.0:
			e.cd = e.d.melee_cd
			best.take_damage(e.d.melee, e.pos)
			e.vel = to_t.normalized() * 60.0

	# separation (bucket neighbours, capped)
	var sep := Vector2.ZERO
	var checked := 0
	var bk := Vector2i(int(e.pos.x / BUCKET), int(e.pos.y / BUCKET))
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			var arr = buckets.get(bk + Vector2i(ox, oy))
			if arr == null:
				continue
			for o in arr:
				if o == e:
					continue
				var dv: Vector2 = e.pos - o.pos
				var md: float = e.r + o.r + 3.0
				var l2 := dv.length_squared()
				if l2 < md * md and l2 > 0.0001:
					sep += dv / sqrt(l2) * (md - sqrt(l2)) / md
				checked += 1
				if checked > 10:
					break
	var want := (desired * spd) + sep * 90.0
	e.vel = e.vel.lerp(want, clampf(5.0 * delta, 0, 1))
	e.pos = G.world.move_circle(e.pos, e.vel * delta, e.r)


func _rebuild_buckets() -> void:
	buckets.clear()
	for e in list:
		if not e.alive:
			continue
		var k := Vector2i(int(e.pos.x / BUCKET), int(e.pos.y / BUCKET))
		if buckets.has(k):
			buckets[k].append(e)
		else:
			buckets[k] = [e]


func query_radius(p: Vector2, r: float) -> Array:
	var out: Array = []
	var x0 := int((p.x - r) / BUCKET)
	var x1 := int((p.x + r) / BUCKET)
	var y0 := int((p.y - r) / BUCKET)
	var y1 := int((p.y + r) / BUCKET)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var arr = buckets.get(Vector2i(x, y))
			if arr == null:
				continue
			for e in arr:
				if e.alive and e.pos.distance_to(p) <= r + e.r:
					out.append(e)
	return out


func query_segment(a: Vector2, b: Vector2, pad: float) -> Array:
	var mid := (a + b) * 0.5
	var near := query_radius(mid, a.distance_to(b) * 0.5 + 12.0)
	var out: Array = []
	for e in near:
		if Geometry2D.get_closest_point_to_segment(e.pos, a, b).distance_to(e.pos) <= e.r + pad:
			out.append(e)
	out.sort_custom(func(x, y): return x.pos.distance_squared_to(a) < y.pos.distance_squared_to(a))
	return out


func count_near(p: Vector2, r: float) -> int:
	var n := 0
	var r2 := r * r
	for e in list:
		if e.alive and e.pos.distance_squared_to(p) < r2:
			n += 1
	return n


func damage(e: Enemy, amount: float, by: Mech) -> void:
	if not e.alive:
		return
	var armor: float = e.d.armor
	var dealt := maxf(amount - armor, amount * 0.2)
	e.hp -= dealt
	e.flash = 1.0
	if e.hp <= 0.0:
		kill(e, by)


func damage_radius(p: Vector2, r: float, dmg: float) -> void:
	for e in query_radius(p, r):
		var d: float = e.pos.distance_to(p)
		damage(e, dmg * (1.0 - 0.5 * d / r), null)


func kill(e: Enemy, by: Mech) -> void:
	if not e.alive:
		return
	e.alive = false
	G.kills += 1
	if by:
		by.kills += 1
		if by.brain:
			by.brain.on_kill(e)
	if G.director:
		G.director.report_kill()
	G.projectiles.add_fx("puff", e.pos, e.r * 2.5, e.d.color, 0.4)
	if e.d.get("bomb", false):
		G.projectiles.explode(e.pos, e.d.bomb_r, e.d.bomb_dmg, 1, true)
	if randf() < e.d.drop:
		var loot := {"scrap": randi_range(1, 3)}
		if e.type == "warden":
			loot = {"scrap": randi_range(4, 7), "circuits": randi_range(1, 3)}
			if randf() < 0.5:
				loot["cells"] = 1
		G.pickups.add_salvage(e.pos, loot)


func alive_count() -> int:
	return list.size()


func _draw() -> void:
	var tsec := Time.get_ticks_msec() / 1000.0
	for e in list:
		var c: Color = e.d.color
		if e.flash > 0.0:
			c = c.lerp(Color.WHITE, e.flash)
		match e.type:
			"skitter":
				draw_circle(e.pos, e.r, c)
			"spitter":
				draw_circle(e.pos, e.r, c)
				draw_circle(e.pos, e.r * 0.45, Color(0.15, 0.05, 0.0))
			"tick":
				var blink := 0.5 + 0.5 * sin(e.t * (10.0 + 20.0 * float(e.los)))
				draw_circle(e.pos, e.r, c.lerp(Color.WHITE, blink * 0.6))
				draw_arc(e.pos, e.r + 2.0, 0, TAU, 10, Color(1, 0.9, 0.3, 0.4 * blink), 1.0)
			"warden":
				var a: float = e.vel.angle() if e.vel.length() > 1.0 else 0.0
				var pts := PackedVector2Array()
				for i in 4:
					pts.append(e.pos + Vector2.from_angle(a + TAU * i / 4.0) * e.r * (1.3 if i % 2 == 0 else 0.9))
				draw_colored_polygon(pts, c.darkened(0.3))
				pts.append(pts[0])
				draw_polyline(pts, c, 1.5)
				draw_arc(e.pos, e.r + 4.0, -PI / 2, -PI / 2 + TAU * e.hp / e.max_hp, 20, Color(c, 0.6), 1.5)
				draw_circle(e.pos, 2.0, Color(1, 1, 1, 0.5 + 0.5 * sin(tsec * 6.0)))
