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

var shots: Array = []
var fx: Array = []           # {type, pos, r, color, t, dur}


func spawn_shot(from: Vector2, dir: Vector2, d: Dictionary, team: int, owner: Mech, aim_point: Vector2) -> void:
	var p := Proj.new()
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
	shots.append(p)


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


func add_fx(type: String, pos: Vector2, r: float, color: Color, dur: float) -> void:
	fx.append({"type": type, "pos": pos, "r": r, "color": color, "t": 0.0, "dur": dur})
	if fx.size() > 600:
		# keep wrecks, drop oldest transient fx
		for i in fx.size():
			if fx[i].type != "wreck":
				fx.remove_at(i)
				break


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


func _physics_process(delta: float) -> void:
	if G.game_state != "play":
		return
	var keep: Array = []
	for p in shots:
		if _step(p, delta):
			keep.append(p)
	shots = keep
	var keep_fx: Array = []
	for f in fx:
		f.t += delta
		if f.t < f.dur:
			keep_fx.append(f)
	fx = keep_fx
	queue_redraw()


func _step(p: Proj, delta: float) -> bool:
	p.life -= delta
	var np := p.pos + p.vel * delta
	if p.lob:
		p.pos = np
		if p.life <= 0.0:
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
	for f in fx:
		if f.type == "wreck":
			draw_circle(f.pos, f.r, f.color)
			draw_circle(f.pos + Vector2(3, -2), f.r * 0.5, Color(0, 0, 0, 0.5))
	for p in shots:
		if p.lob:
			var total: float = p.start.distance_to(p.target)
			var k := clampf(p.start.distance_to(p.pos) / maxf(total, 1.0), 0, 1)
			var h := sin(k * PI) * 60.0
			draw_circle(p.pos, 2.5, Color(0, 0, 0, 0.4))
			draw_circle(p.pos - Vector2(0, h), 3.5, p.color)
			draw_arc(p.target, p.splash * (1.0 - k * 0.5), 0, TAU, 24, Color(1, 0.5, 0.2, 0.35), 1.0)
		else:
			var tail: Vector2 = p.vel.normalized() * minf(p.vel.length() * 0.025, 18.0)
			draw_line(p.pos - tail, p.pos, p.color, p.width)
	for f in fx:
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
