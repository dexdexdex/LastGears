class_name Hud
extends Control
## Screen-space HUD, drawn by hand for a terse military-terminal look.

const C_TEXT := Color(0.82, 0.9, 0.8)
const C_DIM := Color(0.5, 0.58, 0.5)
const C_PANEL := Color(0.03, 0.05, 0.04, 0.72)
const C_LINE := Color(0.45, 0.6, 0.45, 0.5)
const C_WARN := Color(1, 0.45, 0.3)
const C_AMBER := Color(1, 0.8, 0.4)

var font: Font
var banner_text := ""
var banner_color := Color.WHITE
var banner_t := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	G.banner.connect(func(t, c):
		banner_text = t
		banner_color = c
		banner_t = 3.5)


func _process(delta: float) -> void:
	banner_t = maxf(0.0, banner_t - delta)
	queue_redraw()


func _txt(p: Vector2, s: String, size: int = 13, col: Color = C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, col)


func _bar(r: Rect2, frac: float, col: Color, bg := Color(0, 0, 0, 0.5)) -> void:
	draw_rect(r, bg)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y)), col)


func _panel(r: Rect2) -> void:
	draw_rect(r, C_PANEL)
	draw_rect(r, C_LINE, false, 1.0)
	# corner ticks
	for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), C_LINE.lightened(0.3))


func _draw() -> void:
	var vs := size
	if G.player == null:
		return
	_draw_materials(vs)
	_draw_squad(vs)
	_draw_player(vs)
	_draw_radio(vs)
	_draw_director(vs)
	if G.tactical or (G.camera and G.camera.tac_blend > 0.05):
		_draw_map(vs)
	_draw_objective(vs)
	_txt(Vector2(16, vs.y - 10), "L-stick move · R-stick aim · R1 fire · L1 alt fire · hold R2 tactical · START field refit     (KB: WASD · mouse · LMB/RMB · Tab · Esc/I · F3 director · F2 filter · F5 restart)", 11, C_DIM)
	if banner_t > 0.0:
		var a := clampf(banner_t, 0, 1)
		var y := vs.y * 0.3
		draw_rect(Rect2(0, y - 30, vs.x, 44), Color(0, 0, 0, 0.45 * a))
		_txt(Vector2(0, y), banner_text, 26, Color(banner_color, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if G.game_state != "play":
		_draw_end(vs)


func _draw_materials(vs: Vector2) -> void:
	var r := Rect2(vs.x * 0.5 - 200, 10, 400, 30)
	_panel(r)
	var x := r.position.x + 18
	for k in ["scrap", "circuits", "cells"]:
		draw_rect(Rect2(x, 20, 8, 8), G.MATERIAL_COLORS[k])
		_txt(Vector2(x + 14, 30), "%s %d" % [G.MATERIAL_NAMES[k], G.materials.get(k, 0)], 14, G.MATERIAL_COLORS[k])
		x += 130


func _draw_squad(_vs: Vector2) -> void:
	var y := 12.0
	for m in G.squad:
		var r := Rect2(12, y, 250, 52)
		_panel(r)
		var col: Color = m.color if m.alive else C_DIM
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), col)
		var title := "%s  ·  %s" % [m.callsign, m.pilot]
		_txt(r.position + Vector2(12, 16), title, 13, col)
		var tag: String = ("YOU" if m.is_player else m.role_tag).to_upper()
		_txt(Vector2(r.position.x, r.position.y + 16), tag, 10, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8)
		if m.alive:
			_bar(Rect2(r.position + Vector2(12, 24), Vector2(150, 5)), m.hp_ratio(), Color(0.45, 1, 0.55) if m.hp_ratio() > 0.35 else C_WARN)
			if m.max_shield > 0:
				_bar(Rect2(r.position + Vector2(12, 30), Vector2(150, 2)), m.shield / m.max_shield, Color(0.4, 0.85, 1))
			_bar(Rect2(r.position + Vector2(170, 24), Vector2(68, 5)), m.heat / 100.0, C_WARN if m.heat > 75 else Color(1, 0.65, 0.3))
			var st: String = "SHUTDOWN — VENTING" if m.overheated > 0 else ("REFITTING" if m.busy_menu or not m.installing.is_empty() else ("FIELD REPAIR" if m.repairing > 0 else m.state_label))
			if m.is_player:
				st = "REFITTING — SQUAD COVERING" if m.busy_menu else ("FIELD REPAIR" if m.repairing > 0 else "LEAD")
			_txt(r.position + Vector2(12, 46), st, 11, C_AMBER if st != "FOLLOWING" else C_DIM)
		else:
			_txt(r.position + Vector2(12, 40), "SIGNAL LOST", 13, C_WARN)
		y += 58


func _draw_player(vs: Vector2) -> void:
	var m := G.player
	var r := Rect2(12, vs.y - 168, 420, 140)
	_panel(r)
	var x := r.position.x + 12
	var y := r.position.y + 18
	_txt(Vector2(x, y), "%s — %s FRAME" % [m.callsign, PartsDB.CHASSIS[m.loadout.chassis_id]["name"].to_upper()], 13, m.color)
	y += 10
	_txt(Vector2(x, y + 10), "HULL", 10, C_DIM)
	_bar(Rect2(x + 46, y + 2, 200, 8), m.hp_ratio(), Color(0.45, 1, 0.55) if m.hp_ratio() > 0.35 else C_WARN)
	_txt(Vector2(x + 252, y + 10), "%d/%d" % [m.hp, m.max_hp], 10, C_TEXT)
	y += 14
	if m.max_shield > 0:
		_txt(Vector2(x, y + 10), "SHIELD", 10, C_DIM)
		_bar(Rect2(x + 46, y + 2, 200, 6), m.shield / m.max_shield, Color(0.4, 0.85, 1))
	y += 12
	_txt(Vector2(x, y + 10), "HEAT", 10, C_DIM)
	var heat_col := C_WARN if m.heat > 75 else Color(1, 0.65, 0.3)
	if m.overheated > 0 and int(Time.get_ticks_msec() / 150) % 2 == 0:
		heat_col = Color.WHITE
	_bar(Rect2(x + 46, y + 2, 200, 8), m.heat / 100.0, heat_col)
	if m.overheated > 0:
		_txt(Vector2(x + 252, y + 10), "SHUTDOWN", 10, C_WARN)
	y += 22
	for key in ["primary", "secondary"]:
		var lbl := "R1" if key == "primary" else "L1"
		var ws: Mech.WeaponState = m.weapons[key]
		if m.installing.has(key):
			var ins: Dictionary = m.installing[key]
			_txt(Vector2(x, y), "%s  installing…" % lbl, 12, C_AMBER)
			_bar(Rect2(x + 150, y - 8, 100, 6), 1.0 - ins.t / ins.total, C_AMBER)
		elif ws == null:
			_txt(Vector2(x, y), "%s  — empty hardpoint —" % lbl, 12, C_DIM)
		else:
			_txt(Vector2(x, y), "%s  %s" % [lbl, ws.data.name], 12, C_TEXT)
			if int(ws.data.mag) == 0:
				_txt(Vector2(x + 220, y), "ENERGY", 11, Color(0.5, 1, 0.95))
			elif ws.reload_t > 0:
				_bar(Rect2(x + 220, y - 8, 80, 6), 1.0 - ws.reload_t / ws.reload_total(), C_AMBER)
				_txt(Vector2(x + 306, y), "RELOAD", 10, C_AMBER)
			else:
				_txt(Vector2(x + 220, y), "%d / %d" % [ws.ammo, ws.data.mag], 11, C_TEXT)
		y += 17
	var s := m.stats
	var wcol := C_WARN if s.overweight > 0 else C_DIM
	var pcol := C_WARN if s.power_draw > s.power_out else C_DIM
	_txt(Vector2(x, y + 2), "WEIGHT %d/%d" % [s.weight, s.max_weight], 11, wcol)
	_txt(Vector2(x + 110, y + 2), "POWER %d/%d" % [s.power_draw, s.power_out], 11, pcol)
	_txt(Vector2(x + 210, y + 2), "COOL %.0f/s" % s.cooling, 11, C_DIM)
	_txt(Vector2(x + 300, y + 2), "SPD %.0f" % s.speed, 11, C_DIM)


func _draw_radio(vs: Vector2) -> void:
	var lines := G.radio.slice(maxi(0, G.radio.size() - 7))
	var r := Rect2(vs.x - 452, vs.y - 168, 440, 140)
	_panel(r)
	_txt(r.position + Vector2(10, 14), "SQUAD COMMS", 10, C_DIM)
	var y := r.position.y + 32
	for l in lines:
		var age: float = G.game_time - l.t
		var a := clampf(1.3 - age / 25.0, 0.35, 1.0)
		_txt(Vector2(r.position.x + 10, y), l.text, 12, Color(l.color, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20)
		y += 15


func _draw_director(vs: Vector2) -> void:
	if not G.show_director or G.director == null:
		return
	var d := G.director
	var r := Rect2(vs.x - 262, 12, 250, 74)
	_panel(r)
	var cols := [Color(0.5, 1, 0.6), C_AMBER, C_WARN]
	_txt(r.position + Vector2(10, 16), "DIRECTOR (F3)", 10, C_DIM)
	_txt(r.position + Vector2(110, 16), Director.PHASE_NAMES[d.phase], 13, cols[d.phase])
	_txt(r.position + Vector2(10, 36), "INTENSITY", 10, C_DIM)
	_bar(Rect2(r.position + Vector2(80, 28), Vector2(150, 7)), d.intensity / 100.0, cols[d.phase])
	var extra := ""
	match d.phase:
		Director.Phase.RELAX: extra = "next push in %.0fs" % maxf(0.0, d.relax_len - d.t)
		Director.Phase.BUILD: extra = "horde in ≤%.0fs" % maxf(0.0, d.build_len - d.t)
		Director.Phase.PEAK: extra = "horde %d/%d spawned" % [d.horde_spawned, d.horde_budget]
	_txt(r.position + Vector2(10, 54), "HOSTILES %d · %s" % [G.enemies.alive_count(), extra], 11, C_TEXT)
	_txt(r.position + Vector2(10, 68), "hordes survived: %d" % maxi(0, d.hordes - (1 if d.phase == Director.Phase.PEAK else 0)), 10, C_DIM)


func _draw_objective(vs: Vector2) -> void:
	var p := G.player
	var goal := G.world.goal_zone.get_center()
	var dist_km := p.position.distance_to(goal) / 24.0 * 6.0 / 1000.0   # 1 cell ≈ 6 m
	var r := Rect2(vs.x * 0.5 - 200, 46, 400, 22)
	_txt(Vector2(r.position.x, r.position.y + 14), "OBJECTIVE  Reach HAVEN-7  ·  %.2f km east" % dist_km, 12, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# off-screen arrow
	var view := G.camera.view_rect()
	if not view.has_point(goal):
		var dir := (goal - p.position).normalized()
		var c := vs * 0.5
		var edge := c + dir * Vector2(vs.x * 0.45, vs.y * 0.42)
		var pts := PackedVector2Array([edge + dir * 12, edge + dir.orthogonal() * 7, edge - dir.orthogonal() * 7])
		draw_colored_polygon(pts, Color(C_AMBER, 0.75))


func _draw_map(vs: Vector2) -> void:
	## Overworld map: the whole corridor between settlements.
	var a := G.camera.tac_blend
	var tex := G.world.map_texture
	var scale := minf(3.4, (vs.x - 560.0) / tex.get_width())
	var msz := Vector2(tex.get_width(), tex.get_height()) * scale
	var r := Rect2(Vector2(vs.x - msz.x - 16, 96), msz)
	draw_rect(r.grow(8), Color(0, 0, 0, 0.75 * a))
	draw_texture_rect(tex, r, false, Color(1, 1, 1, a))
	draw_rect(r.grow(8), Color(C_LINE, a), false, 1.0)
	_txt(r.position + Vector2(0, -12), "REGIONAL SURVEY — GRAVEL → HAVEN-7 CORRIDOR", 11, Color(C_TEXT, a))
	var k := scale / World.CELL
	var sa := Rect2(r.position + G.world.start_zone.position * k, G.world.start_zone.size * k)
	var sb := Rect2(r.position + G.world.goal_zone.position * k, G.world.goal_zone.size * k)
	draw_rect(sa, Color(0.6, 0.8, 0.6, 0.7 * a), false, 1.5)
	draw_rect(sb, Color(1, 0.8, 0.4, 0.9 * a), false, 1.5)
	_txt(sa.position + Vector2(0, -3), "GRAVEL", 9, Color(0.6, 0.8, 0.6, a))
	_txt(sb.position + Vector2(-10, -3), "HAVEN-7", 9, Color(1, 0.8, 0.4, a))
	for it in G.pickups.items:
		if it.kind == "cache":
			draw_rect(Rect2(r.position + it.pos * k - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 0.8, 0.35, 0.8 * a))
	for e in G.enemies.list:
		draw_rect(Rect2(r.position + e.pos * k - Vector2(1, 1), Vector2(2, 2)), Color(e.d.color, 0.8 * a))
	for m in G.squad:
		if m.alive:
			draw_circle(r.position + m.position * k, 3.0 if m.is_player else 2.2, Color(m.color, a))
	var view := G.camera.view_rect()
	draw_rect(Rect2(r.position + view.position * k, view.size * k), Color(1, 1, 1, 0.3 * a), false, 1.0)


func _draw_end(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var won := G.game_state == "won"
	var title := "HAVEN-7 REACHED" if won else "SIGNAL LOST"
	var col := Color(1, 0.85, 0.45) if won else C_WARN
	_txt(Vector2(0, vs.y * 0.42), title, 40, col, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var alive := G.alive_squad().size()
	var sub := "%d of %d mechs made it  ·  %d machines destroyed  ·  %d:%02d" % [alive, G.squad.size(), G.kills, int(G.game_time) / 60, int(G.game_time) % 60]
	_txt(Vector2(0, vs.y * 0.42 + 40), sub, 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_txt(Vector2(0, vs.y * 0.42 + 72), "Press START / F5 to trudge again", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
