class_name ProjectileManager
extends Node2D
## All bullets, rockets, shells and visual effects, simulated and drawn in bulk.

class Proj:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var dmg := 0.0
	var life := 1.0
	var team := 0            # 0 = squad, 1 = enemy
	var splash := 0.0
	var pierce := false
	var lob := false
	var target := Vector2.ZERO
	var start := Vector2.ZERO
	var color := Color.WHITE
	var width := 2.0
	var owner: Mech
	var hit := {}            # enemies already hit (pierce)
	var radius := 4.0
	var kind := ""           # weapon id (drives the look: flames, smoke...)
	var homing := 0.0        # turn rate, rad/s
	var tgt = null
	var retarget := 0.0
	var bomblets := 0
	var age := 0.0
	var life0 := 1.0
	var smoke := 0.0

var shots: Array = []
var fx: Array = []           # {type, pos, r, color, t, dur, (b | pts | seed)}
var pending: Array = []      # delayed bomblet blasts {pos, t, dmg, r}


func spawn_shot(from: Vector2, dir: Vector2, d: Dictionary, team: int, owner: Mech, aim_point: Vector2) -> void:
	var mode: String = d.get("mode", "")
	if mode == "beam":
		_fire_beam(from, dir, d, owner)
		return
	if mode == "chain":
		_fire_chain(from, dir, d, owner)
		return
	var p := Proj.new()
	p.kind = d.get("id", "")
	p.homing = float(d.get("turn", 0.0))
	p.bomblets = int(d.get("bomblets", 0))
	p.pos = from
	p.start = from
	p.team = team
	p.owner = owner
	p.dmg = float(d.dmg)
	p.splash = float(d.get("splash", 0.0))
	p.pierce = bool(d.get("pierce", false))
	p.lob = bool(d.get("lob", false))
	p.color = d.get("color", Color.WHITE)
	p.width = float(d.get("width", 2.0))
	var spd := float(d.speed) * randf_range(0.94, 1.06)
	p.vel = dir * spd
	p.life = float(d.range) / spd
	if p.lob:
		var dist := clampf(from.distance_to(aim_point), float(d.get("min_range", 0.0)), float(d.range))
		p.target = from + dir * dist
		p.life = dist / spd
	p.life0 = p.life
	shots.append(p)


func _fire_beam(from: Vector2, dir: Vector2, d: Dictionary, owner: Mech) -> void:
	var dist := G.world.ray_dist(from, dir, float(d.range))
	var end := from + dir * dist
	var dmg := float(d.dmg)
	var n := 0
	for e in G.enemies.query_segment(from, end, 4.0):
		G.enemies.damage(e, dmg, owner)
		if n < 12:
			add_fx("spark", e.pos, 6.0, d.color, 0.2)
		n += 1
		dmg *= 0.93
	var f := add_fx("beam", from, float(d.width), d.color, 0.3)
	f["b"] = end
	add_fx("ring", end, 26.0, d.color, 0.3)
	if G.lighting:
		G.lighting.flash(end, 170.0, 0.7)
		G.lighting.flash((from + end) * 0.5, 280.0, 0.35)
	if owner == G.player and G.camera:
		G.camera.shake(0.14)


func _fire_chain(from: Vector2, dir: Vector2, d: Dictionary, owner: Mech) -> void:
	var rng_ := float(d.range)
	var best = null
	var bs := INF
	for e in G.enemies.query_radius(from + dir * rng_ * 0.5, rng_ * 0.6):
		var v: Vector2 = e.pos - from
		var dist := v.length()
		if dist > rng_ or dist < 1.0:
			continue
		var ang := absf(dir.angle_to(v))
		if ang > 0.4:
			continue
		var sc := ang * 300.0 + dist * 0.3
		if sc < bs and G.world.has_los(from, e.pos):
			bs = sc
			best = e
	var pts := PackedVector2Array([from])
	if best == null:
		_jag(pts, from, from + dir * rng_ * 0.45)
		var f0 := add_fx("arc", from, 2.0, d.color, 0.12)
		f0["pts"] = pts
		return
	var hit := {}
	var cur := from
	var e2 = best
	var dmg := float(d.dmg)
	for hop in int(d.get("chains", 5)) + 1:
		_jag(pts, cur, e2.pos)
		G.enemies.damage(e2, dmg, owner)
		hit[e2] = true
		cur = e2.pos
		dmg *= 0.9
		var nxt = null
		var nd := INF
		for o in G.enemies.query_radius(cur, float(d.get("chain_r", 120.0))):
			if hit.has(o) or not o.alive:
				continue
			var dd: float = o.pos.distance_squared_to(cur)
			if dd < nd and G.world.has_los(cur, o.pos):
				nd = dd
				nxt = o
		if nxt == null:
			break
		e2 = nxt
	var f := add_fx("arc", from, 2.0, d.color, 0.16)
	f["pts"] = pts
	if G.lighting:
		G.lighting.flash(cur, 140.0, 0.5)


func _jag(pts: PackedVector2Array, a: Vector2, b: Vector2) -> void:
	var n := (b - a).orthogonal().normalized()
	for k in [0.33, 0.66]:
		pts.append(a.lerp(b, k) + n * randf_range(-9.0, 9.0))
	pts.append(b)


func _nearest_enemy(p: Vector2, r: float):
	var best = null
	var bd := INF
	for e in G.enemies.query_radius(p, r):
		var dd: float = e.pos.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = e
	return best


func spawn_enemy_bolt(from: Vector2, dir: Vector2, dmg: float, spd: float) -> void:
	var p := Proj.new()
	p.pos = from
	p.start = from
	p.team = 1
	p.dmg = dmg
	p.vel = dir * spd
	p.life = 2.2
	p.color = Color(1.0, 0.55, 0.2)
	p.width = 3.0
	p.radius = 3.0
	shots.append(p)


func add_fx(type: String, pos: Vector2, r: float, color: Color, dur: float) -> Dictionary:
	var f := {"type": type, "pos": pos, "r": r, "color": color, "t": 0.0, "dur": dur}
	fx.append(f)
	if fx.size() > 600:
		# keep wrecks, drop oldest transient fx
		for i in fx.size():
			if fx[i].type != "wreck":
				fx.remove_at(i)
				break
	return f


func explode(pos: Vector2, radius: float, dmg: float, team: int, hurt_mechs: bool) -> void:
	add_fx("explosion", pos, radius, Color(1, 0.65, 0.3), 0.45)
	if G.lighting:
		G.lighting.flash(pos, radius * 3.0, 1.0)
	G.enemies.damage_radius(pos, radius, dmg)
	if hurt_mechs or team == 1:
		for m in G.squad:
			if m.alive:
				var d: float = m.position.distance_to(pos)
				if d < radius + m.radius:
					m.take_damage(dmg * (1.0 - 0.6 * d / radius), pos)
	if G.camera and G.player:
		var cd := G.player.position.distance_to(pos)
		if cd < 500:
			G.camera.shake(clampf(radius / 260.0, 0.05, 0.4) * (1.0 - cd / 500.0))


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_body(delta)
	G.pe("shots sim", _t0)


func _process_body(delta: float) -> void:
	delta = minf(delta, 0.05)
	if G.game_state != "play":
		return
	var keep: Array = []
	for p in shots:
		if _step(p, delta):
			keep.append(p)
	shots = keep
	if not pending.is_empty():
		var still: Array = []
		for b in pending:
			b.t -= delta
			if b.t <= 0.0:
				explode(b.pos, b.r, b.dmg, 0, false)
			else:
				still.append(b)
		pending = still
	var keep_fx: Array = []
	for f in fx:
		f.t += delta
		if f.t < f.dur:
			keep_fx.append(f)
	fx = keep_fx
	queue_redraw()


func _step(p: Proj, delta: float) -> bool:
	p.life -= delta
	p.age += delta
	if p.homing > 0.0:
		p.retarget -= delta
		if p.retarget <= 0.0 or p.tgt == null or not p.tgt.alive:
			p.retarget = 0.2
			p.tgt = _nearest_enemy(p.pos + p.vel.normalized() * 110.0, 240.0)
		if p.tgt != null:
			var want: Vector2 = (p.tgt.pos - p.pos)
			var turn := clampf(p.vel.angle_to(want), -p.homing * delta, p.homing * delta)
			p.vel = p.vel.rotated(turn)
	if p.kind in ["rockets", "swarm"]:
		p.smoke -= delta
		if p.smoke <= 0.0:
			p.smoke = 0.035
			add_fx("smoke", p.pos, 3.0, Color(0.55, 0.55, 0.52), 0.55)
	var np := p.pos + p.vel * delta
	if p.lob:
		p.pos = np
		if p.life <= 0.0:
			if p.bomblets > 0:
				explode(p.target, p.splash * 0.7, p.dmg, p.team, false)
				for i in p.bomblets:
					var off := Vector2.from_angle(randf() * TAU) * randf_range(20.0, 85.0)
					pending.append({"pos": p.target + off, "t": randf_range(0.08, 0.45), "dmg": p.dmg, "r": p.splash})
			else:
				explode(p.target, p.splash, p.dmg, p.team, false)
			return false
		return true
	if G.world.segment_blocked(p.pos, np):
		var hp := G.world.segment_hit_point(p.pos, np)
		if p.splash > 0.0:
			explode(hp, p.splash, p.dmg, p.team, false)
		else:
			add_fx("spark", hp, 4.0, p.color, 0.15)
		return false
	if p.team == 0:
		var hits := G.enemies.query_segment(p.pos, np, p.radius)
		for e in hits:
			if p.hit.has(e):
				continue
			if p.splash > 0.0:
				explode(e.pos, p.splash, p.dmg, 0, false)
				return false
			G.enemies.damage(e, p.dmg, p.owner)
			add_fx("spark", e.pos, 3.0, p.color, 0.12)
			if not p.pierce:
				return false
			p.hit[e] = true
			p.dmg *= 0.85
	else:
		for m in G.squad:
			if m.alive and Geometry2D.get_closest_point_to_segment(m.position, p.pos, np).distance_to(m.position) < m.radius + p.radius:
				m.take_damage(p.dmg, p.pos)
				add_fx("spark", np, 5.0, p.color, 0.15)
				return false
	p.pos = np
	if p.life <= 0.0:
		if p.splash > 0.0:
			explode(p.pos, p.splash, p.dmg, p.team, false)
		return false
	return true


func _draw() -> void:
	var _t0 := Time.get_ticks_usec()
	_draw_body()
	G.pe("shots draw", _t0)


func _draw_body() -> void:
	var view := G.camera.view_rect().grow(120.0) if G.camera else Rect2(-1e9, -1e9, 2e9, 2e9)
	var tr_pts := PackedVector2Array()
	var tr_cols := PackedColorArray()
	var core_pts := PackedVector2Array()
	var sh_pts := PackedVector2Array()
	var sh_cols := PackedColorArray()
	for f in fx:
		if not view.has_point(f.pos):
			continue
		if f.type == "wreck":
			draw_circle(f.pos, f.r, f.color)
			draw_circle(f.pos + Vector2(3, -2), f.r * 0.5, Color(0, 0, 0, 0.5))
	for p in shots:
		if not view.has_point(p.pos):
			continue
		if p.lob:
			var total: float = p.start.distance_to(p.target)
			var k := clampf(p.start.distance_to(p.pos) / maxf(total, 1.0), 0, 1)
			var h := sin(k * PI) * 60.0
			draw_circle(p.pos, 2.5, Color(0, 0, 0, 0.4))
			draw_circle(p.pos - Vector2(0, h), 3.5, p.color)
			draw_arc(p.target, p.splash * (1.0 - k * 0.5), 0, TAU, 24, Color(1, 0.5, 0.2, 0.35), 1.0)
		elif p.kind == "flamer":
			var k2: float = clampf(p.age / maxf(p.life0, 0.01), 0.0, 1.0)
			var fc: Color = Color(1.0, 0.85, 0.4).lerp(Color(0.9, 0.25, 0.08), k2)
			draw_circle(p.pos, 2.5 + k2 * 13.0, Color(fc, 0.55 * (1.0 - k2)))
			draw_circle(p.pos, 1.5 + k2 * 5.0, Color(1, 0.95, 0.7, 0.6 * (1.0 - k2)))
		elif p.homing > 0.0 or p.kind == "rockets":
			var dv: Vector2 = p.vel.normalized()
			draw_line(p.pos - dv * 7.0, p.pos, p.color, p.width + 1.0)
			draw_circle(p.pos - dv * 8.0, 2.5, Color(1, 0.6, 0.2, 0.9))
		else:
			# plain tracers: collected and drawn in one batched call below
			var tail: Vector2 = p.vel.normalized() * minf(p.vel.length() * 0.025, 18.0)
			tr_pts.append(p.pos - tail)
			tr_pts.append(p.pos)
			tr_cols.append(p.color)
			core_pts.append(p.pos - tail * 0.4)
			core_pts.append(p.pos)
	for f in fx:
		if not view.has_point(f.pos):
			continue
		var k: float = f.t / f.dur
		match f.type:
			"explosion":
				draw_circle(f.pos, f.r * (0.3 + 0.7 * k), Color(f.color, (1.0 - k) * 0.35))
				draw_arc(f.pos, f.r * (0.4 + 0.6 * k), 0, TAU, 32, Color(1, 0.9, 0.7, 1.0 - k), 2.0)
			"spark":
				draw_circle(f.pos, f.r * (1.0 - k), Color(f.color, 1.0 - k))
			"puff":
				draw_circle(f.pos, f.r * (0.5 + k), Color(f.color, (1.0 - k) * 0.6))
			"ring":
				draw_arc(f.pos, f.r * k, 0, TAU, 32, Color(f.color, 1.0 - k), 2.0)
			"smoke":
				draw_circle(f.pos, f.r * (1.0 + k * 2.5), Color(f.color, 0.22 * (1.0 - k)))
			"beam":
				var w: float = f.r * (1.0 - k) + 1.0
				draw_line(f.pos, f.b, Color(f.color, 0.45 * (1.0 - k)), w * 3.0)
				draw_line(f.pos, f.b, Color(f.color, 1.0 - k), w)
				draw_line(f.pos, f.b, Color(1, 1, 1, 1.0 - k), maxf(1.0, w * 0.4))
			"arc":
				var flick := 1.0 if int(f.t * 60.0) % 2 == 0 else 0.6
				draw_polyline(f.pts, Color(f.color, (1.0 - k) * flick), 3.0)
				draw_polyline(f.pts, Color(1, 1, 1, (1.0 - k) * flick), 1.2)
			"shards":
				var rs := int(f.pos.x * 31.0 + f.pos.y * 17.0)
				for q in 5:
					var a := float((rs + q * 97) % 628) / 100.0
					var dq := Vector2.from_angle(a)
					var p0: Vector2 = f.pos + dq * f.r * (0.2 + k * 1.2)
					sh_pts.append(p0)
					sh_pts.append(p0 + dq * 3.0)
					sh_cols.append(Color(f.color, 1.0 - k))
	if not tr_pts.is_empty():
		draw_multiline_colors(tr_pts, tr_cols, 2.0)
		draw_multiline(core_pts, Color(1, 1, 1, 0.7), 1.0)
	if not sh_pts.is_empty():
		draw_multiline_colors(sh_pts, sh_cols, 1.5)
