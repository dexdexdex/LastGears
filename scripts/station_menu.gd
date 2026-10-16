class_name StationMenu
extends Control
## Opens when the squad reaches a haven / outpost / ruin. The world is
## paused while you're inside the walls.
##   HANGAR  – swap any squad mech's gear from your spare-parts inventory (instant, free)
##   MARKET  – trade materials and parts for credits at this station's prices
##   REPAIRS – patch hulls for credits; havens can hire replacement pilots
##   DEPART  – pick the next route out (threat, terrain, payout)

const C_TEXT := Color(0.82, 0.9, 0.8)
const C_DIM := Color(0.5, 0.58, 0.5)
const C_SEL := Color(1, 0.82, 0.4)
const C_GOOD := Color(0.55, 1, 0.6)
const C_BAD := Color(1, 0.45, 0.3)
const C_LINE := Color(0.45, 0.6, 0.45, 0.5)
const C_CREDIT := Color(0.95, 0.9, 0.55)
const TABS := ["HANGAR", "MARKET", "REPAIRS", "DEPART"]

var open := false
var tab := 0
var stack: Array = []        # pages: {"id": String, ...params}
var sel := 0
var rows: Array = []         # built each frame: {label, right, enabled, act: Callable, hint, part, col, header}
var row_rects: Array = []
var tab_rects: Array = []
var hover := -1
var summary := {}
var flash_msg := ""
var flash_t := 0.0
var font: Font
var bot_t := 0.0
var bot_step := 0


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open_station(s: Dictionary) -> void:
	summary = s
	open = true
	visible = true
	tab = 0
	stack = [{"id": "hangar"}]
	sel = 0
	bot_t = 0.0
	bot_step = 0
	_build_rows()
	_skip_headers(1)


func camp() -> Campaign:
	return G.campaign


func here() -> Dictionary:
	return G.atlas.nodes[camp().node_idx]


func st() -> Dictionary:
	return camp().station(G.atlas, camp().node_idx)


func flash(s: String) -> void:
	flash_msg = s
	flash_t = 3.0


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	if not open:
		return
	flash_t = maxf(0.0, flash_t - delta)
	_build_rows()
	if G.bot_mode:
		_bot(delta)
		queue_redraw()
		return
	if Input.is_action_just_pressed("tab_left"):
		_set_tab(tab - 1)
	if Input.is_action_just_pressed("tab_right"):
		_set_tab(tab + 1)
	if Input.is_action_just_pressed("menu_up"):
		_move(-1)
	if Input.is_action_just_pressed("menu_down"):
		_move(1)
	if Input.is_action_just_pressed("menu_accept") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_accept()
	if Input.is_action_just_pressed("menu_back") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_back()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not open:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = get_local_mouse_position()
		hover = -1
		for i in row_rects.size():
			if row_rects[i].has_point(mp) and i < rows.size() and not rows[i].get("header", false):
				hover = i
				sel = i
	elif event is InputEventMouseButton and event.pressed:
		var mp2: Vector2 = get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			for i in tab_rects.size():
				if tab_rects[i].has_point(mp2):
					_set_tab(i)
					return
			for i in row_rects.size():
				if row_rects[i].has_point(mp2) and i < rows.size():
					sel = i
					_accept()
					return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_back()


func _set_tab(t: int) -> void:
	tab = wrapi(t, 0, TABS.size())
	stack = [{"id": TABS[tab].to_lower()}]
	sel = 0
	_build_rows()
	_skip_headers(1)


func _move(d: int) -> void:
	if rows.is_empty():
		return
	sel = wrapi(sel + d, 0, rows.size())
	_skip_headers(d)


func _skip_headers(d: int) -> void:
	for i in rows.size():
		if sel < rows.size() and rows[sel].get("header", false):
			sel = wrapi(sel + d, 0, rows.size())


func _accept() -> void:
	if sel < 0 or sel >= rows.size():
		return
	var r: Dictionary = rows[sel]
	if r.get("header", false):
		return
	if not r.get("enabled", true):
		flash(r.get("why", "Not available."))
		return
	var act: Callable = r.get("act", Callable())
	if act.is_valid():
		act.call()


func _back() -> void:
	if stack.size() > 1:
		stack.pop_back()
		sel = 0
		_build_rows()
		_skip_headers(1)


func _push(page: Dictionary) -> void:
	stack.append(page)
	sel = 0
	_build_rows()
	_skip_headers(1)


# ---------------------------------------------------------------- pages

func _build_rows() -> void:
	rows = []
	var page: Dictionary = stack.back()
	match page.id:
		"hangar": _rows_hangar()
		"mech": _rows_mech(page.i)
		"slot": _rows_slot(page.i, page.key)
		"market": _rows_market()
		"repairs": _rows_repairs()
		"depart": _rows_depart()
		"confirm": _rows_confirm(page.to)
	sel = clampi(sel, 0, maxi(0, rows.size() - 1))


func _hdr(t: String) -> void:
	rows.append({"label": t, "header": true})


func _rows_hangar() -> void:
	_hdr("SQUAD — pick a mech to refit")
	for i in camp().squad.size():
		var e: Dictionary = camp().squad[i]
		var lo: Loadout = e.loadout
		var ok: bool = e.alive
		var right := "%s / %s" % [PartsDB.part(lo.primary).get("short", "—"), PartsDB.part(lo.secondary).get("short", "—")] if ok else "KIA"
		rows.append({"label": "%s · %s" % [e.def[0], e.pilot], "right": right, "enabled": ok, "why": "Pilot lost. Hire a replacement at a haven.",
			"col": e.def[3], "act": func(): _push({"id": "mech", "i": i}), "mech": i})
	_hdr("SPARE PARTS: %s" % _inventory_line())


func _inventory_line() -> String:
	var parts: Array = []
	for id in camp().inventory:
		parts.append("%s ×%d" % [PartsDB.part(id).get("short", id), camp().inventory[id]])
	return "none" if parts.is_empty() else ", ".join(parts)


func _rows_mech(i: int) -> void:
	var e: Dictionary = camp().squad[i]
	var lo: Loadout = e.loadout
	_hdr("%s — %s FRAME · choose a slot" % [e.def[0], PartsDB.CHASSIS[lo.chassis_id]["name"].to_upper()])
	for key in lo.slot_keys():
		var id := lo.get_slot(key)
		var label: String = "WEAPON 1 (LMB/R1)" if key == "primary" else ("WEAPON 2 (RMB/L1)" if key == "secondary" else "MODULE BAY %d" % (int(key.substr(1)) + 1))
		rows.append({"label": label, "right": PartsDB.part(id).get("name", "— empty —") if id != "" else "— empty —",
			"act": func(): _push({"id": "slot", "i": i, "key": key}), "mech": i, "part": id})


func _rows_slot(i: int, key: String) -> void:
	var e: Dictionary = camp().squad[i]
	var lo: Loadout = e.loadout
	var cur := lo.get_slot(key)
	var weapon_slot := key in ["primary", "secondary"]
	_hdr("Fit from spare parts (current: %s)" % (PartsDB.part(cur).get("name", "empty") if cur != "" else "empty"))
	rows.append({"label": "— strip slot —", "right": "part goes to spares", "enabled": cur != "", "why": "Already empty.",
		"act": func(): _swap(i, key, ""), "mech": i, "preview": [key, ""]})
	var any := false
	for id in camp().inventory:
		if (PartsDB.WEAPONS.has(id)) != weapon_slot:
			continue
		any = true
		rows.append({"label": PartsDB.part(id).name, "right": "×%d in spares" % camp().inventory[id],
			"act": func(): _swap(i, key, id), "mech": i, "part": id, "preview": [key, id]})
	if not any:
		_hdr("No spare %s. Buy some in MARKET." % ("weapons" if weapon_slot else "modules"))


func _swap(i: int, key: String, id: String) -> void:
	var lo: Loadout = camp().squad[i].loadout
	var old := lo.get_slot(key)
	if id != "":
		camp().add_part(id, -1)
	camp().add_part(old, 1)
	lo.set_slot(key, id)
	flash("%s: %s fitted." % [camp().squad[i].def[0], PartsDB.part(id).get("name", "slot stripped")] if id != "" else "%s: slot stripped, part to spares." % camp().squad[i].def[0])
	_back()


func _rows_market() -> void:
	var s := st()
	if not s.market:
		_hdr("No traders at a ruin. Only scavengers and silence.")
		return
	_hdr("MATERIALS — sell / buy in lots of 5")
	for m in ["scrap", "circuits", "cells"]:
		var pr: Dictionary = s.prices[m]
		var have: int = G.materials.get(m, 0)
		rows.append({"label": "Sell 5 %s" % m, "right": "+%d cr   (have %d)" % [pr.sell * 5, have], "enabled": have >= 5,
			"why": "Need 5 %s." % m, "col": G.MATERIAL_COLORS[m], "act": func():
				G.materials[m] -= 5
				camp().credits += pr.sell * 5
				flash("Sold 5 %s." % m)})
		rows.append({"label": "Buy 5 %s" % m, "right": "−%d cr" % (pr.buy * 5), "enabled": camp().credits >= pr.buy * 5,
			"why": "Not enough credits.", "col": G.MATERIAL_COLORS[m], "act": func():
				G.materials[m] += 5
				camp().credits -= pr.buy * 5
				flash("Bought 5 %s." % m)})
	_hdr("PARTS FOR SALE — go to spares, fit them in HANGAR")
	for id in s.parts:
		var price := Campaign.part_price(id)
		rows.append({"label": PartsDB.part(id).name, "right": "%d cr" % price, "enabled": camp().credits >= price,
			"why": "Not enough credits.", "part": id, "act": func():
				camp().credits -= price
				camp().add_part(id, 1)
				flash("Bought %s." % PartsDB.part(id).name)})
	if s.parts.is_empty():
		_hdr("(nothing on the racks today)")
	if not camp().inventory.is_empty():
		_hdr("SELL SPARE PARTS")
		for id in camp().inventory.keys():
			var sp := Campaign.part_sell_price(id)
			rows.append({"label": "Sell %s (×%d)" % [PartsDB.part(id).name, camp().inventory[id]], "right": "+%d cr" % sp, "part": id, "act": func():
				camp().add_part(id, -1)
				camp().credits += sp
				flash("Sold %s." % PartsDB.part(id).name)})


func _rows_repairs() -> void:
	var s := st()
	var rate: float = s.repair_rate
	var total := 0
	for e in camp().squad:
		total += camp().repair_cost(e, rate)
	_hdr("HULL REPAIRS — %s rates" % ("haven" if rate < 0.8 else "outpost"))
	rows.append({"label": "Repair whole squad", "right": "%d cr" % total, "enabled": total > 0 and camp().credits >= total,
		"why": "Nothing to repair." if total == 0 else "Not enough credits.", "act": func():
			camp().credits -= total
			for e2 in camp().squad:
				if e2.alive:
					e2.hp_ratio = 1.0
			flash("Squad patched up.")})
	for e in camp().squad:
		if not e.alive:
			continue
		var c := camp().repair_cost(e, rate)
		rows.append({"label": "%s  hull %d%%" % [e.def[0], int(e.hp_ratio * 100)], "right": "%d cr" % c if c > 0 else "intact",
			"enabled": c > 0 and camp().credits >= c, "why": "Hull intact." if c == 0 else "Not enough credits.", "col": e.def[3], "act": func():
				camp().credits -= c
				e.hp_ratio = 1.0
				flash("%s repaired." % e.def[0])})
	var dead := camp().squad.filter(func(x): return not x.alive)
	if not dead.is_empty():
		_hdr("REPLACEMENT PILOTS" + ("" if s.hire else " — only at havens"))
		for e in dead:
			rows.append({"label": "Hire pilot for %s (new random weapons)" % e.def[0], "right": "200 cr", "enabled": s.hire and camp().credits >= 200,
				"why": "Only havens have pilots to spare." if not s.hire else "Not enough credits.", "col": e.def[3], "act": func():
					camp().credits -= 200
					camp().hire(e)
					flash("%s joins as %s." % [e.pilot, e.def[0]])})


func _rows_depart() -> void:
	_hdr("ROUTES OUT OF %s" % here().name.to_upper())
	for r in camp().routes_from(G.atlas, camp().node_idx):
		var n: Dictionary = G.atlas.nodes[r.to]
		var e: Dictionary = r.edge
		var pay: int = 50 + int(e.threat) * 35
		var tag := " (visited)" if camp().visited.has(r.to) else ""
		rows.append({"label": "→ %s%s" % [n.name, tag], "right": "%s · threat %d/5 · ~%d cr" % [e.zone, e.threat, pay],
			"col": Hud.KIND_COL[n.kind], "route": r, "act": func(): _push({"id": "confirm", "to": r.to})})


func _rows_confirm(to: int) -> void:
	var n: Dictionary = G.atlas.nodes[to]
	_hdr("Leave for %s? The gates close behind you." % n.name)
	rows.append({"label": "Move out", "right": "", "act": func(): _depart(to), "col": C_SEL})
	rows.append({"label": "Not yet", "right": "", "act": func(): _back()})


func _depart(to: int) -> void:
	camp().materials = G.materials.duplicate()
	camp().depart(G.atlas, to)
	open = false
	visible = false
	if G.bot_mode:
		print("[bot] DEPART leg %d -> %s [%s] (threat %d) credits=%d" % [camp().legs + 1, G.atlas.nodes[to].name, G.atlas.nodes[to].kind, camp().threat(G.atlas), camp().credits])
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- bot (automated tests)

func _bot(delta: float) -> void:
	bot_t += delta
	if bot_t < 0.4:
		return
	bot_t = 0.0
	match bot_step:
		0:  # sell a lot of scrap if we have it, then buy the cheapest affordable part
			_set_tab(1)
			for r in rows:
				if r.get("label", "") == "Sell 5 scrap" and r.get("enabled", false):
					r.act.call()
					break
			_build_rows()
			for r in rows:
				if r.has("part") and str(r.label).find("Sell") == -1 and r.get("enabled", false):
					r.act.call()
					break
			print("[bot] market: credits=%d inventory=%s" % [camp().credits, str(camp().inventory)])
			_shot("07_market")
		1:  # fit the first spare that fits ROOK (or VANGUARD)
			for i in camp().squad.size():
				var e: Dictionary = camp().squad[i]
				if not e.alive:
					continue
				for key in e.loadout.slot_keys():
					var weapon_slot: bool = key in ["primary", "secondary"]
					for id in camp().inventory:
						if PartsDB.WEAPONS.has(id) == weapon_slot and (e.loadout.get_slot(key) == "" or weapon_slot == false):
							stack = [{"id": "hangar"}, {"id": "mech", "i": i}, {"id": "slot", "i": i, "key": key}]
							_swap(i, key, id)
							print("[bot] hangar: %s %s <- %s" % [e.def[0], key, id])
							bot_step += 1
							return
		2:
			_set_tab(2)
			_build_rows()
			if rows.size() > 1 and rows[1].get("enabled", false):
				rows[1].act.call()
			print("[bot] repairs: credits=%d" % camp().credits)
		3:
			if bot_t == 0.0 and not has_meta("depart_shot"):
				set_meta("depart_shot", true)
				_set_tab(3)
				_build_rows()
				_skip_headers(1)
				_shot("08_depart")
				return
			_set_tab(3)
			_build_rows()
			var pick = null
			for r in rows:
				if r.has("route") and (pick == null or (camp().visited.has(pick.to) and not camp().visited.has(r.route.to))):
					pick = r.route
			if pick != null:
				_depart(pick.to)
				return
	bot_step += 1


func _shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			queue_redraw()
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [a.substr(8), name])
			print("[bot] screenshot %s" % name)


# ---------------------------------------------------------------- drawing

func _txt(p: Vector2, s: String, sz: int = 13, col: Color = C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, sz, col)


func _para(p: Vector2, s: String, sz: int, col: Color, w: float) -> float:
	## Wrapped text; returns the height used.
	draw_multiline_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, -1, col)
	var lines := font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, w, sz).y
	return lines + 4.0


func _draw() -> void:
	if not open:
		return
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.035, 0.03, 1.0))
	var n := here()
	var kc: Color = Hud.KIND_COL[n.kind]
	var x0 := 60.0
	# header
	_txt(Vector2(x0, 58), n.name.to_upper(), 30, kc)
	var sub := "%s · %s" % [n.kind.to_upper(), n.note]
	if n.pop > 0:
		sub = "%s · pop. %d · %s" % [n.kind.to_upper(), n.pop, n.note]
	_txt(Vector2(x0, 80), sub, 12, C_DIM)
	if not summary.is_empty():
		var lost: Array = camp().squad.filter(func(x): return not x.alive).map(func(x): return x.def[0])
		var line := "Leg %d complete · threat %d/5 · delivery +%d cr · machine bounties +%d cr" % [camp().legs, summary.threat, summary.delivery, summary.bounty]
		if not lost.is_empty():
			line += " · lost: " + ", ".join(lost)
		_txt(Vector2(x0, 100), line, 12, C_SEL)
	# wallet
	var wx := vs.x - 540
	_txt(Vector2(wx, 58), "%d CREDITS" % camp().credits, 22, C_CREDIT)
	var mx := wx
	for k in ["scrap", "circuits", "cells"]:
		_txt(Vector2(mx, 82), "%s %d" % [G.MATERIAL_NAMES[k], G.materials.get(k, 0)], 13, G.MATERIAL_COLORS[k])
		mx += 130
	# tabs
	tab_rects.clear()
	var tx := x0
	for i in TABS.size():
		var r := Rect2(tx, 120, 170, 32)
		tab_rects.append(r)
		var on := i == tab
		draw_rect(r, Color(1, 0.8, 0.4, 0.14) if on else Color(0, 0, 0, 0.35))
		draw_rect(r, C_SEL if on else C_LINE, false, 1.0)
		_txt(r.position + Vector2(0, 21), TABS[i], 14, C_SEL if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		tx += 178
	_txt(Vector2(tx + 10, 141), "A/D or ←/→ switch tabs · W/S select · E/Space/click confirm · Backspace/right-click back", 11, C_DIM)
	# list
	var list := Rect2(x0, 170, vs.x * 0.5 - x0, vs.y - 240)
	draw_rect(list, Color(0, 0, 0, 0.25))
	row_rects.clear()
	var y := list.position.y + 26
	for i in rows.size():
		var r: Dictionary = rows[i]
		var rr := Rect2(list.position.x + 6, y - 17, list.size.x - 12, 24)
		row_rects.append(rr)
		if r.get("header", false):
			_txt(Vector2(rr.position.x + 6, y), r.label, 11, C_DIM)
			y += 26
			continue
		var on := i == sel
		var en: bool = r.get("enabled", true)
		if on:
			draw_rect(rr, Color(1, 0.8, 0.4, 0.13))
			draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), C_SEL)
		var col: Color = r.get("col", C_TEXT)
		if not en:
			col = C_DIM.darkened(0.2)
		elif on:
			col = col.lerp(C_SEL, 0.4)
		_txt(Vector2(rr.position.x + 12, y), str(r.label), 14, col)
		_txt(Vector2(rr.position.x, y), str(r.get("right", "")), 12, col if en else C_DIM.darkened(0.2), HORIZONTAL_ALIGNMENT_RIGHT, rr.size.x - 10)
		y += 26
	# detail panel
	var det := Rect2(vs.x * 0.5 + 20, 170, vs.x * 0.5 - 80, vs.y - 240)
	draw_rect(det, Color(0, 0, 0, 0.25))
	draw_rect(det, C_LINE, false, 1.0)
	_draw_detail(det)
	if flash_t > 0.0:
		_txt(Vector2(x0, vs.y - 44), flash_msg, 15, C_SEL)
	# cursor
	if G.using_mouse:
		var mp := get_local_mouse_position()
		var pts := PackedVector2Array([mp, mp + Vector2(0, 16), mp + Vector2(4, 12), mp + Vector2(11, 12)])
		draw_colored_polygon(pts, C_SEL)


func _draw_detail(r: Rect2) -> void:
	var page: Dictionary = stack.back()
	var row: Dictionary = rows[sel] if sel < rows.size() else {}
	var x := r.position.x + 16
	var y := r.position.y + 26
	if page.id == "depart" or page.id == "confirm":
		_draw_route_map(r, row)
		return
	if row.has("mech"):
		var e: Dictionary = camp().squad[row.mech]
		var lo: Loadout = e.loadout
		var preview := lo.copy()
		if row.has("preview"):
			preview.set_slot(row.preview[0], row.preview[1])
		_draw_stats(Rect2(x, y - 10, r.size.x - 32, 360), e, lo, preview)
		y += 360
	if row.has("part") and row.part != "":
		var pd := PartsDB.part(row.part)
		_txt(Vector2(x, y), pd.name, 16, C_SEL)
		y += 20
		y += _para(Vector2(x, y), pd.desc, 12, C_TEXT, r.size.x - 32)
		var bits := "weight %d · power %d" % [pd.weight, pd.power]
		if PartsDB.WEAPONS.has(row.part):
			bits += " · dmg %.0f×%d · %.1f/s · range %.0f" % [pd.dmg, pd.pellets, pd.rof, pd.range]
		_txt(Vector2(x, y), bits, 11, C_DIM)
		y += 18
		_txt(Vector2(x, y), "market value %d cr · field fabrication: %s" % [Campaign.part_price(row.part), G.cost_string(pd.get("cost", {}))], 11, C_DIM)
	elif not row.has("mech"):
		var tips := {
			"hangar": "Swap gear on any squad mech using spare parts. Swaps here are instant and free; anything you remove goes to spares. Buy new parts in MARKET.",
			"market": "Prices differ between stations. Sell scrap where it's dear, buy cells where they're cheap. Materials also fuel field refits out in the zones.",
			"repairs": "Hull damage carries over between legs. Havens repair cheaper than outposts, and only havens have pilots to replace the fallen.",
		}
		_para(Vector2(x, y), tips.get(page.id, ""), 13, C_TEXT, r.size.x - 32)


func _draw_stats(r: Rect2, e: Dictionary, cur: Loadout, preview: Loadout) -> void:
	var a := cur.compute()
	var b := preview.compute()
	var x := r.position.x
	var y := r.position.y + 14
	_txt(Vector2(x, y), "%s · %s FRAME · hull %d%%" % [e.def[0], PartsDB.CHASSIS[cur.chassis_id]["name"].to_upper(), int(e.hp_ratio * 100)], 14, e.def[3])
	y += 24
	for rr in [["Weight", "weight", "/ %d" % a.max_weight, false], ["Power draw", "power_draw", "/ %d out" % b.power_out, false],
			["Cooling /s", "cooling", "", true], ["Hull", "hp", "", true], ["Shield", "shield", "", true], ["Walk speed", "speed", "", true]]:
		var va: float = a[rr[1]]
		var vb: float = b[rr[1]]
		var col := C_TEXT
		var s := "%.0f" % vb
		if not is_equal_approx(va, vb):
			col = C_GOOD if ((vb > va) == rr[3]) else C_BAD
			s = "%.0f → %.0f" % [va, vb]
		_txt(Vector2(x, y), rr[0], 12, C_DIM)
		_txt(Vector2(x + 110, y), s + " " + rr[2], 12, col)
		y += 19
	if b.overweight > 0:
		_txt(Vector2(x, y), "OVERWEIGHT +%d — slower, runs hot" % b.overweight, 11, C_BAD)
		y += 16
	if b.power_draw > b.power_out:
		_txt(Vector2(x, y), "POWER DEFICIT — weapons cycle at %d%%" % int(b.power_ratio * 100), 11, C_BAD)
		y += 16
	y += 8
	for key in ["primary", "secondary"]:
		var id := preview.get_slot(key)
		if id == "":
			_txt(Vector2(x, y), "%s  —" % ("W1" if key == "primary" else "W2"), 12, C_DIM)
			y += 34
			continue
		var w := preview.weapon_stats(id, b)
		_txt(Vector2(x, y), "%s  %s" % ["W1" if key == "primary" else "W2", w.name], 12, C_TEXT)
		y += 16
		var ammo := "∞" if int(w.mag) == 0 else str(w.mag)
		_txt(Vector2(x + 18, y), "DPS %.0f · range %.0f · heat %.1f/shot · mag %s" % [w.dmg * w.pellets * w.rof, w.range, w.heat, ammo], 10, C_DIM)
		y += 18
	var mods: Array = preview.modules.filter(func(m): return m != "").map(func(m): return PartsDB.MODULES[m]["short"])
	_txt(Vector2(x, y + 4), "MODULES  " + (", ".join(mods) if not mods.is_empty() else "none"), 11, C_DIM)


func _draw_route_map(r: Rect2, row: Dictionary) -> void:
	var at := G.atlas
	var inner := r.grow(-24)
	inner.size.y -= 60
	var P := func(i: int) -> Vector2: return inner.position + at.nodes[i].pos * inner.size
	var hl := -1
	if row.has("route"):
		hl = row.route.to
	elif stack.back().id == "confirm":
		hl = stack.back().to
	for e in at.edges:
		var a: Vector2 = P.call(e.a)
		var b: Vector2 = P.call(e.b)
		var touches_here: bool = e.a == camp().node_idx or e.b == camp().node_idx
		var is_hl: bool = touches_here and (e.a == hl or e.b == hl)
		if is_hl:
			draw_line(a, b, C_SEL, 3.0)
		elif e.known:
			draw_line(a, b, Color(0.55, 0.65, 0.55, 0.5), 1.2)
		else:
			draw_dashed_line(a, b, Color(0.5, 0.55, 0.5, 0.25), 1.0, 6.0)
	for i in at.nodes.size():
		var nd: Dictionary = at.nodes[i]
		var p: Vector2 = P.call(i)
		var c: Color = Hud.KIND_COL[nd.kind]
		var rad := 6.0 if nd.kind == "haven" else 4.5
		draw_circle(p, rad, c.darkened(0.5))
		draw_arc(p, rad, 0, TAU, 16, c, 1.5)
		if camp().visited.has(i):
			draw_circle(p, 2.0, c)
		if i == camp().node_idx:
			draw_arc(p, 12.0, 0, TAU, 24, Color(0.45, 0.85, 1.0), 2.0)
		_txt(p + Vector2(9, 4), nd.name, 11 if i != hl else 13, c if i != hl else C_SEL)
	if row.has("route"):
		var e2: Dictionary = row.route.edge
		var nd2: Dictionary = at.nodes[row.route.to]
		var y := r.end.y - 44
		_txt(Vector2(r.position.x + 16, y), "%s → %s via %s" % [here().name, nd2.name, e2.zone], 14, C_SEL)
		_txt(Vector2(r.position.x + 16, y + 20), "%s · threat %d/5 · %s · %s" % [e2.terrain, e2.threat, nd2.kind, nd2.note], 12, C_TEXT)
