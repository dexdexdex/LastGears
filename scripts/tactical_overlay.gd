class_name TacticalOverlay
extends Node2D
## World-space markers drawn while the tactical view (R2) is held:
## enemy blips sized to stay readable when zoomed out, squad intent lines,
## supply caches and the route to Haven.

var alpha := 0.0


func _process(delta: float) -> void:
	alpha = move_toward(alpha, 1.0 if G.tactical else 0.0, delta * 4.0)
	if alpha > 0.0 or visible:
		queue_redraw()
	visible = alpha > 0.0


func _draw() -> void:
	if alpha <= 0.0 or G.camera == null:
		return
	var k := 1.0 / G.camera.zoom.x        # screen-constant sizes
	var font := ThemeDB.fallback_font
	var a := alpha
	# route
	draw_rect(G.world.goal_zone, Color(1, 0.85, 0.4, 0.6 * a), false, 2.0 * k)
	draw_string(font, G.world.goal_zone.position + Vector2(0, -8 * k), "HAVEN-7", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), Color(1, 0.85, 0.4, a))
	# caches
	for it in G.pickups.items:
		if it.kind == "cache":
			draw_rect(Rect2(it.pos - Vector2(4, 4) * k, Vector2(8, 8) * k), Color(1, 0.8, 0.35, 0.8 * a), false, 1.5 * k)
	# enemies
	for e in G.enemies.list:
		var c: Color = e.d.color
		var r := (3.5 if e.type != "warden" else 7.0) * k
		draw_circle(e.pos, r, Color(c, 0.85 * a))
	# squad
	for m in G.squad:
		if not m.alive:
			continue
		draw_arc(m.position, 12.0 * k, 0, TAU, 20, Color(m.color, a), 2.0 * k)
		draw_string(font, m.position + Vector2(14, -6) * k, m.callsign, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * k), Color(m.color, a))
		if not m.is_player:
			draw_string(font, m.position + Vector2(14, 8) * k, m.state_label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(9 * k), Color(0.8, 0.85, 0.8, 0.8 * a))
			var b: SquadBrain = m.brain
			if b and b.target != null and b.target.alive:
				draw_dashed_line(m.position, b.target.pos, Color(m.color, 0.35 * a), 1.0 * k, 6.0 * k)
	# scan ring
	var t := fmod(Time.get_ticks_msec() / 1000.0, 2.0) / 2.0
	if G.player:
		draw_arc(G.player.position, 900.0 * t, 0, TAU, 64, Color(0.6, 1.0, 0.7, (1.0 - t) * 0.25 * a), 2.0 * k)
