class_name Pickups
extends Node2D
## Supply caches in the ruins and salvage dropped by destroyed machines.

var items: Array = []   # {pos, loot, kind, taken, t (pulse phase)}
var check_t := 0.0


func populate(spots: Array, rng: RandomNumberGenerator) -> void:
	items.clear()
	for p in spots:
		var loot := {"scrap": rng.randi_range(2, 6)}
		var roll := rng.randf()
		if roll < 0.5:
			loot["circuits"] = rng.randi_range(1, 2)
		if roll > 0.65:
			loot["cells"] = 1
		items.append({"pos": p, "loot": loot, "kind": "cache", "taken": false, "t": rng.randf() * 5.0})


func add_salvage(pos: Vector2, loot: Dictionary) -> void:
	items.append({"pos": pos, "loot": loot, "kind": "salvage", "taken": false, "t": 0.0})


func nearest(pos: Vector2, max_d: float, kind: String = "") -> Variant:
	var best = null
	var bd := max_d
	for it in items:
		if it.taken or (kind != "" and it.kind != kind):
			continue
		var d: float = it.pos.distance_to(pos)
		if d < bd:
			bd = d
			best = it
	return best


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_body(delta)
	G.pe("pickups", _t0)


func _process_body(delta: float) -> void:
	delta = minf(delta, 0.05)
	if G.game_state != "play":
		return
	check_t -= delta
	if check_t > 0.0:
		queue_redraw()
		return
	check_t = 0.08
	var any := false
	for it in items:
		if it.taken:
			continue
		for m in G.squad:
			if m.alive and m.position.distance_squared_to(it.pos) < (m.radius + 16.0) * (m.radius + 16.0):
				_collect(it, m)
				any = true
				break
	if any:
		items = items.filter(func(i): return not i.taken)
	queue_redraw()


func _collect(it: Dictionary, m: Mech) -> void:
	it.taken = true
	G.add_materials(it.loot)
	G.projectiles.add_fx("ring", it.pos, 30.0, Color(1, 0.85, 0.4), 0.5)
	var parts: Array = []
	for k in ["scrap", "circuits", "cells"]:
		if it.loot.has(k):
			parts.append("+%d %s" % [it.loot[k], k])
	var txt := " ".join(parts)
	if m.is_player:
		G.say("", "Salvaged " + txt, Color(1, 0.85, 0.45))
	elif m.brain:
		m.brain.on_scavenged(txt, it.kind == "cache")


func _draw() -> void:
	var view := G.camera.view_rect().grow(30.0) if G.camera else Rect2(-1e9, -1e9, 2e9, 2e9)
	for it in items:
		if not view.has_point(it.pos):
			continue
		var pulse: float = 0.5 + 0.5 * sin(it.t + G.game_time * 3.0)
		if it.kind == "cache":
			var r := Rect2(it.pos - Vector2(6, 6), Vector2(12, 12))
			draw_rect(r.grow(2), Color(1, 0.8, 0.35, 0.15 + 0.15 * pulse))
			draw_rect(r, Color(0.55, 0.42, 0.2))
			draw_rect(r, Color(1, 0.8, 0.35), false, 1.2)
			draw_line(r.position, r.end, Color(1, 0.8, 0.35, 0.6), 1.0)
		else:
			draw_circle(it.pos, 3.5, Color(0.7, 0.68, 0.6))
			draw_arc(it.pos, 6.0 + pulse * 2.0, 0, TAU, 12, Color(0.8, 0.8, 0.7, 0.5), 1.0)
