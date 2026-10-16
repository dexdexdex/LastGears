class_name FieldMenu
extends Control
## Real-time field refit (START). The world keeps running: your mech stands
## still and can't fire while you work, and your squad moves to cover you.
## Parts are fabricated from salvaged materials and take time to install.

const C_TEXT := Color(0.82, 0.9, 0.8)
const C_DIM := Color(0.5, 0.58, 0.5)
const C_SEL := Color(1, 0.82, 0.4)
const C_GOOD := Color(0.55, 1, 0.6)
const C_BAD := Color(1, 0.45, 0.3)

var open := false
var level := 0               # 0 = slot list, 1 = part list
var slot_idx := 0
var part_idx := 0
var rows: Array = []         # level 0: [{key,label}], level 1: [part ids]
var font: Font
var flash_msg := ""
var flash_t := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle() -> void:
	if G.player == null or not G.player.alive:
		return
	open = not open
	G.player.busy_menu = open
	if not open:
		G.menu_closed_t = G.game_time
	level = 0
	if open:
		_build_slot_rows()


func _build_slot_rows() -> void:
	rows = []
	var lo := G.player.loadout
	rows.append({"key": "primary", "label": "R1 HARDPOINT"})
	rows.append({"key": "secondary", "label": "L1 HARDPOINT"})
	for i in lo.modules.size():
		rows.append({"key": "m%d" % i, "label": "MODULE BAY %d" % (i + 1)})
	rows.append({"key": "repair", "label": "FIELD REPAIR"})
	rows.append({"key": "reload", "label": "RELOAD ALL"})
	rows.append({"key": "close", "label": "CLOSE"})
	slot_idx = clampi(slot_idx, 0, rows.size() - 1)


func _build_part_rows(key: String) -> void:
	rows = [""]
	var src: Dictionary = PartsDB.WEAPONS if key in ["primary", "secondary"] else PartsDB.MODULES
	for id in src:
		rows.append(id)
	part_idx = maxi(0, rows.find(G.player.loadout.get_slot(key)))


func _process(delta: float) -> void:
	flash_t = maxf(0.0, flash_t - delta)
	if open and (G.player == null or not G.player.alive or G.game_state != "play"):
		open = false
	visible = open
	if open:
		queue_redraw()


func handle_input() -> void:
	if not open:
		return
	if Input.is_action_just_pressed("menu_up"):
		_move(-1)
	if Input.is_action_just_pressed("menu_down"):
		_move(1)
	if Input.is_action_just_pressed("menu_accept"):
		_accept()
	if Input.is_action_just_pressed("menu_back"):
		if level == 1:
			level = 0
			_build_slot_rows()
		else:
			toggle()


func _move(d: int) -> void:
	if level == 0:
		slot_idx = wrapi(slot_idx + d, 0, rows.size())
	else:
		part_idx = wrapi(part_idx + d, 0, rows.size())


func _flash(s: String) -> void:
	flash_msg = s
	flash_t = 2.5


func _accept() -> void:
	var m := G.player
	if level == 0:
		var key: String = rows[slot_idx].key
		match key:
			"close":
				toggle()
			"reload":
				m.manual_reload()
				_flash("Reloading.")
			"repair":
				if m.repairing > 0.0:
					_flash("Already repairing.")
				elif m.hp >= m.max_hp:
					_flash("Hull is intact.")
				elif G.spend(PartsDB.REPAIR_COST):
					m.begin_repair()
					_flash("Patching hull… stay put.")
				else:
					_flash("Need %s." % G.cost_string(PartsDB.REPAIR_COST))
			_:
				if m.installing.has(key):
					_flash("Bay busy — installing.")
					return
				level = 1
				_build_part_rows(key)
				set_meta("slot_key", key)
		return
	# level 1 — pick a part
	var slot_key: String = get_meta("slot_key")
	var id: String = rows[part_idx]
	var current := m.loadout.get_slot(slot_key)
	if id == current:
		_flash("Already fitted.")
		return
	var cost: Dictionary = PartsDB.part(id).get("cost", {}) if id != "" else {}
	if not G.spend(cost):
		_flash("Not enough materials: need %s." % G.cost_string(cost))
		return
	# Stripping the old part salvages half its scrap.
	if current != "":
		var old_cost: Dictionary = PartsDB.part(current).get("cost", {})
		var back := int(old_cost.get("scrap", 0) / 2)
		if back > 0:
			G.add_materials({"scrap": back})
	m.begin_install(slot_key, id)
	_flash("Installing %s (%.1fs)" % [PartsDB.part(id).get("name", "nothing"), PartsDB.install_time(id)])
	level = 0
	_build_slot_rows()


func _txt(p: Vector2, s: String, sz: int = 13, col: Color = C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, sz, col)


func _draw() -> void:
	if not open:
		return
	var m := G.player
	var vs := size
	var r := Rect2(vs.x - 760, 96, 740, 600)
	draw_rect(r, Color(0.02, 0.04, 0.03, 0.9))
	draw_rect(r, Color(0.45, 0.6, 0.45, 0.6), false, 1.0)
	_txt(r.position + Vector2(16, 24), "FIELD REFIT — %s" % m.callsign, 16, C_SEL)
	_txt(r.position + Vector2(0, 24), "LIVE — you can't move or fire", 11, C_BAD, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16)
	_txt(r.position + Vector2(16, 42), "W/S select · E/Space/LMB confirm · Backspace/RMB back · Esc close   (pad: D-pad · A · B)", 10, C_DIM)

	var lx := r.position.x + 16
	var y := r.position.y + 70
	var preview: Loadout = m.loadout.copy()
	var desc := ""
	if level == 0:
		for i in rows.size():
			var row: Dictionary = rows[i]
			var sel := i == slot_idx
			var col := C_SEL if sel else C_TEXT
			if sel:
				draw_rect(Rect2(lx - 6, y - 14, 360, 20), Color(1, 0.8, 0.4, 0.12))
			_txt(Vector2(lx, y), row.label, 11, C_DIM if not sel else col)
			var val := ""
			var key: String = row.key
			if key in ["primary", "secondary"] or key.begins_with("m"):
				if m.installing.has(key):
					val = "installing %s… %.1fs" % [PartsDB.part(m.installing[key].part).get("short", "—"), m.installing[key].t]
					col = C_SEL
				else:
					var id := m.loadout.get_slot(key)
					val = PartsDB.part(id).get("name", "— empty —") if id != "" else "— empty —"
			elif key == "repair":
				val = "+%d hull · %s · %.0fs" % [PartsDB.REPAIR_AMOUNT, G.cost_string(PartsDB.REPAIR_COST), PartsDB.REPAIR_TIME]
			_txt(Vector2(lx + 120, y), val, 13, col)
			y += 24
		var key0: String = rows[slot_idx].key
		if key0 in ["primary", "secondary"] or key0.begins_with("m"):
			var id0 := m.loadout.get_slot(key0)
			desc = PartsDB.part(id0).get("desc", "") if id0 != "" else ""
	else:
		var slot_key: String = get_meta("slot_key")
		_txt(Vector2(lx, y - 4), "Fit to %s:" % slot_key.to_upper().replace("M", "MODULE BAY "), 11, C_DIM)
		y += 18
		var current := m.loadout.get_slot(slot_key)
		for i in rows.size():
			var id: String = rows[i]
			var sel := i == part_idx
			var pd := PartsDB.part(id)
			var cost: Dictionary = pd.get("cost", {})
			var afford := G.can_afford(cost)
			var col := C_SEL if sel else (C_TEXT if afford else C_DIM)
			if sel:
				draw_rect(Rect2(lx - 6, y - 14, 360, 20), Color(1, 0.8, 0.4, 0.12))
			var nm: String = pd.get("name", "— strip slot —")
			if id == current:
				nm += "  [FITTED]"
			_txt(Vector2(lx, y), nm, 13, col)
			_txt(Vector2(lx + 220, y), G.cost_string(cost) if id != "" else "", 10, C_TEXT if afford else C_BAD)
			y += 21
		var sel_id: String = rows[part_idx]
		preview.set_slot(slot_key, sel_id)
		desc = PartsDB.part(sel_id).get("desc", "Remove the part. Salvages half its scrap.")

	_draw_stats(Rect2(r.position.x + 390, r.position.y + 60, 330, 480), m, preview)
	if desc != "":
		_txt(Vector2(lx, r.end.y - 40), desc, 12, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32)
	if flash_t > 0.0:
		_txt(Vector2(lx, r.end.y - 16), flash_msg, 13, C_SEL)


func _draw_stats(r: Rect2, m: Mech, preview: Loadout) -> void:
	var a := m.loadout.compute()
	var b := preview.compute()
	draw_rect(r, Color(0, 0, 0, 0.3))
	var x := r.position.x + 12
	var y := r.position.y + 20
	_txt(Vector2(x, y), "%s FRAME" % PartsDB.CHASSIS[m.loadout.chassis_id]["name"].to_upper(), 13, C_TEXT)
	y += 24
	var rows_s := [
		["Weight", "weight", "/ %d" % a.max_weight, false],
		["Power draw", "power_draw", "/ %d out" % b.power_out, false],
		["Power out", "power_out", "", true],
		["Cooling /s", "cooling", "", true],
		["Hull", "hp", "", true],
		["Shield", "shield", "", true],
		["Walk speed", "speed", "", true],
	]
	for rr in rows_s:
		var va: float = a[rr[1]]
		var vb: float = b[rr[1]]
		_txt(Vector2(x, y), rr[0], 12, C_DIM)
		var col := C_TEXT
		if not is_equal_approx(va, vb):
			col = C_GOOD if ((vb > va) == rr[3]) else C_BAD
		var s := "%.0f" % vb
		if not is_equal_approx(va, vb):
			s = "%.0f → %.0f" % [va, vb]
		_txt(Vector2(x + 110, y), s + " " + rr[2], 12, col)
		y += 19
	# budget warnings
	y += 6
	if b.overweight > 0:
		_txt(Vector2(x, y), "OVERWEIGHT +%d — slower, runs hot" % b.overweight, 11, C_BAD)
		y += 16
	if b.power_draw > b.power_out:
		_txt(Vector2(x, y), "POWER DEFICIT — weapons cycle at %d%%" % int(b.power_ratio * 100), 11, C_BAD)
		y += 16
	if b.heat_passive > 0:
		_txt(Vector2(x, y), "Passive heat +%.1f/s" % b.heat_passive, 11, C_SEL)
		y += 16
	# weapon readouts
	y += 10
	for key in ["primary", "secondary"]:
		var id := preview.get_slot(key)
		var lbl := "R1" if key == "primary" else "L1"
		if id == "":
			_txt(Vector2(x, y), "%s  —" % lbl, 12, C_DIM)
			y += 34
			continue
		var w := preview.weapon_stats(id, b)
		_txt(Vector2(x, y), "%s  %s" % [lbl, w.name], 12, C_TEXT)
		y += 16
		var dps: float = w.dmg * w.pellets * w.rof
		var ammo := "∞" if int(w.mag) == 0 else str(w.mag)
		_txt(Vector2(x + 18, y), "DPS %.0f · range %.0f · heat %.1f/shot · mag %s" % [dps, w.range, w.heat, ammo], 10, C_DIM)
		y += 18
