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


const RADAR_RANGES := [700.0, 1400.0, 2800.0]   # px; Q / R2 cycles
const RADAR_PERIOD := 7.2                        # seconds per sweep (slow: info goes stale)
const RADAR_R := 112.0
var sweep := 0.0
var blips := {}          # Enemy -> [pos, time seen, is_big]


func _process(delta: float) -> void:
	banner_t = maxf(0.0, banner_t - delta)
	if not get_tree().paused and G.game_state == "play":
		_radar_update(delta)
	queue_redraw()


func _radar_update(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_radar_update_body(delta)
	G.pe("radar", _t0)


func _radar_update_body(delta: float) -> void:
	## Proximity sensor: hostile positions only refresh as the sweep passes.
	if G.player == null or G.enemies == null:
		return
	var prev := sweep
	sweep = fposmod(sweep + TAU / RADAR_PERIOD * delta, TAU)
	var rng: float = RADAR_RANGES[G.radar_zoom]
	var c := G.player.position
	for e in G.enemies.list:
		var v: Vector2 = e.pos - c
		if v.length_squared() > rng * rng:
			continue
		var a := fposmod(v.angle(), TAU)
		var hit := (a > prev and a <= sweep) if sweep >= prev else (a > prev or a <= sweep)
		if hit:
			blips[e] = [e.pos, G.game_time, e.type == "warden"]
	for e in blips.keys():
		if not e.alive or G.game_time - blips[e][1] > RADAR_PERIOD * 1.05:
			blips.erase(e)


func _draw_radar(vs: Vector2) -> void:
	var c := Vector2(20 + RADAR_R, vs.y - 40 - RADAR_R)
	var R := RADAR_R
	var rng: float = RADAR_RANGES[G.radar_zoom]
	var k := R / rng
	var pc := G.player.position
	var green := Color(0.45, 1.0, 0.6)
	draw_circle(c, R + 6, Color(0, 0, 0, 0.6))
	draw_circle(c, R, Color(0.02, 0.07, 0.045, 0.92))
	for f in [1.0 / 3.0, 2.0 / 3.0, 1.0]:
		draw_arc(c, R * f, 0, TAU, 48, Color(green, 0.18 if f < 1.0 else 0.45), 1.0)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(green, 0.1), 1.0)
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(green, 0.1), 1.0)
	# sweep wedge
	for i in 28:
		var a := sweep - i * 0.025
		draw_line(c, c + Vector2.from_angle(a) * R, Color(green, 0.32 * (1.0 - i / 28.0)), 2.0)
	# hostile blips (stale positions, fading until the sweep comes round again)
	for e in blips:
		var b: Array = blips[e]
		var v: Vector2 = (b[0] - pc) * k
		if v.length() > R:
			continue
		var age := clampf((G.game_time - b[1]) / RADAR_PERIOD, 0.0, 1.0)
		var col := Color(1, 0.3, 0.25, 1.0 - age * 0.85)
		draw_circle(c + v, 3.5 if b[2] else 1.8, col)
	# destination
	var gv := (G.world.goal_c - pc) * k
	var gcol := Color(1, 0.82, 0.4)
	if gv.length() < R - 6:
		draw_rect(Rect2(c + gv - Vector2(4, 4), Vector2(8, 8)), gcol, false, 1.5)
	else:
		var gd := gv.normalized()
		var tip := c + gd * (R + 2)
		draw_colored_polygon(PackedVector2Array([tip + gd * 8, tip + gd.orthogonal() * 5, tip - gd.orthogonal() * 5]), gcol)
	# squad (live) with aim ticks
	for m in G.squad:
		if not m.alive:
			continue
		var v2: Vector2 = (m.position - pc) * k
		if v2.length() > R:
			v2 = v2.normalized() * R
		draw_line(c + v2, c + v2 + m.aim_dir * 10.0, Color(m.color, 0.8), 1.5)
		draw_circle(c + v2, 3.5 if m.is_player else 3.0, m.color)
	var rm := int(rng * 0.25)
	_txt(Vector2(c.x - R, c.y - R - 8), "RADAR · %d m · Q" % rm, 10, C_DIM)
	_txt(Vector2(c.x + R - 70, c.y - R - 8), "%d contacts" % blips.size(), 10, Color(1, 0.4, 0.3, 0.9))


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
	var _t0 := Time.get_ticks_usec()
	_draw_body()
	G.pe("hud draw", _t0)


func _draw_body() -> void:
	var vs := size
	if G.player == null:
		return
	_draw_materials(vs)
	_draw_squad(vs)
	_draw_player(vs)
	_draw_radar(vs)
	_draw_radio(vs)
	_draw_director(vs)
	_draw_fps(vs)
	_draw_objective(vs)
	if G.overworld:
		_draw_overworld(vs)
	_txt(Vector2(16, vs.y - 10), "WASD move · mouse aim · LMB/RMB weapons · Space dodge · E squad formation · Q radar range · M region map · Esc refit · Enter pause · F5 restart     (pad: sticks · R1/L1 · ○ dodge · D-pad formations · R2 radar · touchpad map · START)", 11, C_DIM)
	if banner_t > 0.0:
		var a := clampf(banner_t, 0, 1)
		var y := vs.y * 0.3
		draw_rect(Rect2(0, y - 30, vs.x, 44), Color(0, 0, 0, 0.45 * a))
		_txt(Vector2(0, y), banner_text, 26, Color(banner_color, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if G.game_state == "station":
		return
	if G.game_state != "play":
		_draw_end(vs)
	elif get_tree().paused:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
		_txt(Vector2(0, vs.y * 0.45), "PAUSED", 40, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		_txt(Vector2(0, vs.y * 0.45 + 34), "Enter to resume · F5 restart", 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if G.using_mouse and not get_tree().paused:
		_draw_crosshair(get_local_mouse_position())


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
	_txt(Vector2(16, y + 14), "FORMATION  %s   (E / D-pad)" % G.FORMATIONS[G.formation], 12, Color(0.6, 0.9, 1.0))


func _draw_player(vs: Vector2) -> void:
	var m := G.player
	var r := Rect2(20 + RADAR_R * 2 + 16, vs.y - 168, 420, 140)
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
	# dodge readiness
	var dfrac := 1.0 - m.dodge_cd / Mech.DODGE_COOLDOWN
	var dcol := Color(0.5, 0.85, 1.0) if dfrac >= 1.0 else C_DIM
	_bar(Rect2(x + 330, y + 4, 60, 4), dfrac, dcol)
	_txt(Vector2(x + 330, y - 2), "DODGE" if dfrac >= 1.0 else "dodge", 9, dcol)
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


func _draw_fps(vs: Vector2) -> void:
	var fps := Engine.get_frames_per_second()
	var col := Color(0.5, 1, 0.6) if fps >= 110 else (C_AMBER if fps >= 55 else C_WARN)
	var x := vs.x - 262.0
	var y := 104.0 if G.show_director else 24.0
	_txt(Vector2(x, y), "FPS %d · %.1f ms · %s (F1/F9)" % [fps, G.fps_ms, "fast" if G.render_fast else "sharp"], 13, col)
	if not G.show_profiler:
		return
	var keys: Array = G.prof_avg.keys()
	keys.sort_custom(func(a, b): return G.prof_avg[a] > G.prof_avg[b])
	var r := Rect2(x - 8, y + 6, 258, 18 + keys.size() * 15 + 34)
	draw_rect(r, C_PANEL)
	var yy := y + 22
	var total := 0.0
	for k in keys:
		total += G.prof_avg[k]
		_txt(Vector2(x, yy), k, 11, C_DIM)
		_txt(Vector2(x, yy), "%.2f ms" % G.prof_avg[k], 11, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 240)
		yy += 15
	_txt(Vector2(x, yy + 4), "scripts total", 11, C_AMBER)
	_txt(Vector2(x, yy + 4), "%.2f ms" % total, 11, C_AMBER, HORIZONTAL_ALIGNMENT_RIGHT, 240)
	var gpu := RenderingServer.get_frame_setup_time_cpu()
	_txt(Vector2(x, yy + 20), "render setup %.2f ms · objects %d" % [gpu, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))], 10, C_DIM)


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
	_txt(Vector2(r.position.x, r.position.y + 14), "OBJECTIVE  Reach %s  ·  %.2f km %s  ·  %d cr" % [G.world.to_name.to_upper(), dist_km, G.world.compass(goal - p.position), G.campaign.credits], 12, C_AMBER, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
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
	_txt(r.position + Vector2(0, -12), "ZONE SURVEY — %s → %s" % [G.world.from_name.to_upper(), G.world.to_name.to_upper()], 11, Color(C_TEXT, a))
	var k := scale / World.CELL
	var sa := Rect2(r.position + G.world.start_zone.position * k, G.world.start_zone.size * k)
	var sb := Rect2(r.position + G.world.goal_zone.position * k, G.world.goal_zone.size * k)
	draw_rect(sa, Color(0.6, 0.8, 0.6, 0.7 * a), false, 1.5)
	draw_rect(sb, Color(1, 0.8, 0.4, 0.9 * a), false, 1.5)
	_txt(sa.position + Vector2(0, -3), G.world.from_name.to_upper(), 9, Color(0.6, 0.8, 0.6, a))
	_txt(sb.position + Vector2(-30, -3), G.world.to_name.to_upper(), 9, Color(1, 0.8, 0.4, a))
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


const KIND_COL := {
	"haven": Color(1.0, 0.82, 0.42),
	"outpost": Color(0.65, 0.85, 0.6),
	"hive": Color(1.0, 0.32, 0.28),
	"ruin": Color(0.6, 0.62, 0.66),
}


func _draw_overworld(vs: Vector2) -> void:
	## Region map: every haven and zone. Real time — the fight keeps going.
	var at := G.atlas
	if at == null:
		return
	var tsec := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.035, 0.03, 0.94))
	var r := Rect2(Vector2(70, 110), vs - Vector2(140, 210))
	# survey grid + faint contours
	var gc := Color(0.4, 0.55, 0.4, 0.06)
	for i in 21:
		var gx := r.position.x + r.size.x * i / 20.0
		draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), gc, 1.0)
	for i in 13:
		var gy := r.position.y + r.size.y * i / 12.0
		draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), gc, 1.0)
	var cr := RandomNumberGenerator.new()
	cr.seed = 77
	for i in 9:
		var c := r.position + Vector2(cr.randf(), cr.randf()) * r.size
		for k in 4:
			draw_arc(c, 40.0 + k * 34.0 + cr.randf() * 10.0, 0, TAU, 48, Color(0.45, 0.6, 0.45, 0.05), 1.0)
	draw_rect(r, C_LINE, false, 1.0)
	_txt(Vector2(r.position.x, r.position.y - 46), "THE LONG ROAD — REGIONAL NETWORK", 22, C_AMBER)
	_txt(Vector2(r.position.x, r.position.y - 24), "Havens, outposts and the machine-held ground between them.   Q / M / touchpad: close   ·   the fight keeps running while you look", 12, C_DIM)

	var P := func(i: int) -> Vector2: return r.position + at.nodes[i].pos * r.size
	# hive influence
	for n in at.nodes:
		if n.kind == "hive":
			var hp: Vector2 = r.position + n.pos * r.size
			draw_circle(hp, r.size.x * 0.065, Color(1, 0.25, 0.2, 0.035))
			draw_circle(hp, r.size.x * 0.035, Color(1, 0.25, 0.2, 0.05))
	# zones (edges)
	for i in at.edges.size():
		var e: Dictionary = at.edges[i]
		var a: Vector2 = P.call(e.a)
		var b: Vector2 = P.call(e.b)
		var is_cur: bool = i == at.current_edge
		var tcol := Color(0.55, 0.65, 0.55).lerp(Color(1, 0.35, 0.28), (e.threat - 1) / 4.0)
		if is_cur:
			draw_line(a, b, Color(C_AMBER, 0.25), 9.0)
			draw_line(a, b, C_AMBER, 2.5)
		elif e.known:
			draw_line(a, b, Color(tcol, 0.75), 1.6)
		else:
			draw_dashed_line(a, b, Color(0.5, 0.55, 0.5, 0.35), 1.2, 7.0)
		var mid := (a + b) * 0.5
		var lab: String = e.zone if (e.known or is_cur) else "unscouted"
		var lcol := C_AMBER if is_cur else (Color(tcol, 0.9) if e.known else Color(C_DIM, 0.6))
		_txt(mid + Vector2(-60, -6), lab, 11 if not is_cur else 13, lcol, HORIZONTAL_ALIGNMENT_CENTER, 120)
		if e.known or is_cur:
			for k in 5:
				var pc := tcol if k < e.threat else Color(0.3, 0.33, 0.3, 0.6)
				draw_rect(Rect2(mid + Vector2(-17 + k * 7, 2), Vector2(5, 4)), pc)
	# squad marker along the current zone
	var ce: Dictionary = at.current()
	var sa: Vector2 = P.call(at.start_idx)
	var sb: Vector2 = P.call(at.goal_idx)
	var prog := G.world.progress_of(G.squad_centroid()) if G.world else 0.0
	var sp := sa.lerp(sb, prog)
	var pulse := 0.5 + 0.5 * sin(tsec * 5.0)
	draw_circle(sp, 6.0 + pulse * 3.0, Color(0.45, 0.85, 1.0, 0.25))
	draw_circle(sp, 5.0, Color(0.45, 0.85, 1.0))
	_txt(sp + Vector2(9, -8), "SQUAD (%d)" % G.alive_squad().size(), 11, Color(0.6, 0.9, 1.0))
	# nodes
	var hover := -1
	var mp := get_local_mouse_position()
	for i in at.nodes.size():
		var n: Dictionary = at.nodes[i]
		var p: Vector2 = P.call(i)
		var col: Color = KIND_COL[n.kind]
		match n.kind:
			"haven":
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), col.darkened(0.6))
				draw_rect(Rect2(p - Vector2(8, 8), Vector2(16, 16)), col, false, 2.0)
				draw_circle(p, 2.5, col)
			"outpost":
				draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), col, false, 1.5)
			"hive":
				var hr := 8.0 + 2.0 * sin(tsec * 3.0 + i)
				var pts := PackedVector2Array()
				for k in 6:
					pts.append(p + Vector2.from_angle(TAU * k / 6.0 + tsec * 0.3) * hr)
				draw_colored_polygon(pts, col.darkened(0.5))
				pts.append(pts[0])
				draw_polyline(pts, col, 1.5)
			"ruin":
				draw_circle(p, 6.0, col.darkened(0.6))
				draw_arc(p, 6.0, 0, TAU, 16, col, 1.2)
		var ncol := col if n.kind != "ruin" else col.lightened(0.2)
		_txt(p + Vector2(12, 4), n.name, 13 if n.kind == "haven" else 11, ncol)
		if i == at.start_idx or i == at.goal_idx:
			_txt(p + Vector2(12, 18), "DEPARTED" if i == at.start_idx else "DESTINATION", 9, C_DIM)
		if mp.distance_to(p) < 16.0:
			hover = i
	if hover >= 0:
		var n2: Dictionary = at.nodes[hover]
		var bp: Vector2 = P.call(hover) + Vector2(16, 24)
		var box := Rect2(bp, Vector2(250, 58))
		if box.end.x > vs.x - 10:
			box.position.x -= 280
		draw_rect(box, Color(0.02, 0.04, 0.03, 0.95))
		draw_rect(box, KIND_COL[n2.kind], false, 1.0)
		_txt(box.position + Vector2(8, 16), "%s · %s" % [n2.name, n2.kind.to_upper()], 12, KIND_COL[n2.kind])
		if n2.pop > 0:
			_txt(box.position + Vector2(8, 32), "pop. %d" % n2.pop, 11, C_TEXT)
		_txt(box.position + Vector2(8, 48), n2.note, 11, C_DIM)
	# current leg readout
	var pr := Rect2(Vector2(r.position.x, r.end.y + 14), Vector2(560, 56))
	draw_rect(pr, C_PANEL)
	draw_rect(pr, C_LINE, false, 1.0)
	_txt(pr.position + Vector2(10, 18), "CURRENT LEG  %s → %s" % [at.nodes[at.start_idx].name, at.nodes[at.goal_idx].name], 12, C_AMBER)
	_txt(pr.position + Vector2(10, 36), "Zone: %s  ·  %s  ·  threat %d/5" % [ce.zone, ce.terrain, ce.threat], 12, C_TEXT)
	_bar(Rect2(pr.position + Vector2(10, 44), Vector2(540, 4)), prog, C_AMBER)
	# legend
	var lx := r.end.x - 420
	var ly := r.end.y + 34
	for k in ["haven", "outpost", "hive", "ruin"]:
		draw_rect(Rect2(Vector2(lx, ly - 8), Vector2(9, 9)), KIND_COL[k])
		_txt(Vector2(lx + 14, ly), {"haven": "Haven", "outpost": "Outpost", "hive": "Machine hive", "ruin": "Ruin"}[k], 11, C_DIM)
		lx += 100
	_txt(Vector2(r.end.x - 420, ly + 18), "▪▪▪▪▪ zone threat · dashed = unscouted", 10, C_DIM)


func _draw_end(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	_txt(Vector2(0, vs.y * 0.42), "SIGNAL LOST", 40, C_WARN, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var camp: Campaign = G.campaign
	var sub := "Vanguard down in %s · %d legs travelled · %d credits banked · %d machines destroyed this leg" % [
		camp.current_edge(G.atlas).zone, camp.legs, camp.credits, G.kills]
	_txt(Vector2(0, vs.y * 0.42 + 40), sub, 16, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	_txt(Vector2(0, vs.y * 0.42 + 72), "Enter / F5: retry this leg from %s      N: new campaign" % G.world.from_name, 14, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_crosshair(p: Vector2) -> void:
	var col := Color(0.6, 1.0, 0.75, 0.9)
	if G.player and G.player.alive and (G.player.overheated > 0.0 or G.player.busy_menu):
		col = Color(1, 0.5, 0.3, 0.9)
	draw_arc(p, 9.0, 0, TAU, 20, col, 1.5)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + d * 5.0, p + d * 14.0, col, 1.5)
	draw_circle(p, 1.5, col)
