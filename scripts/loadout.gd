class_name Loadout
extends RefCounted
## A mech's parts, and the derived stats they produce.

const DMG_MULT := 2.2

var chassis_id: String = "vanguard"
var primary: String = ""
var secondary: String = ""
var modules: Array = []


func _init(c: String = "vanguard", p: String = "", s: String = "", mods: Array = []) -> void:
	chassis_id = c
	primary = p
	secondary = s
	var n: int = PartsDB.CHASSIS[c]["module_slots"]
	modules = []
	for i in n:
		modules.append(mods[i] if i < mods.size() else "")


func copy() -> Loadout:
	return Loadout.new(chassis_id, primary, secondary, modules.duplicate())


func get_slot(key: String) -> String:
	if key == "primary":
		return primary
	if key == "secondary":
		return secondary
	return modules[int(key.substr(1))]


func set_slot(key: String, id: String) -> void:
	if key == "primary":
		primary = id
	elif key == "secondary":
		secondary = id
	else:
		modules[int(key.substr(1))] = id


func slot_keys() -> Array:
	var keys: Array = ["primary", "secondary"]
	for i in modules.size():
		keys.append("m%d" % i)
	return keys


func compute() -> Dictionary:
	var c: Dictionary = PartsDB.CHASSIS[chassis_id]
	var s := {
		"weight": float(c["frame_weight"]),
		"max_weight": float(c["max_weight"]),
		"power_draw": 0.0,
		"power_out": float(c["power"]),
		"cooling": float(c["cooling"]),
		"hp": float(c["hp"]),
		"shield": 0.0, "regen": 0.0, "heat_passive": 0.0,
		"speed_mult": 1.0, "spread_mult": 1.0, "range_mult": 1.0,
		"mag_mult": 1.0, "reload_mult": 1.0, "rof_mult": 1.0,
	}
	for w in [primary, secondary]:
		if w != "":
			var wd: Dictionary = PartsDB.WEAPONS[w]
			s.weight += wd["weight"]
			s.power_draw += wd["power"]
	for m in modules:
		if m == "":
			continue
		var md: Dictionary = PartsDB.MODULES[m]
		s.weight += md["weight"]
		s.power_draw += md["power"]
		s.power_out += md.get("power_out", 0)
		s.cooling += md.get("cooling", 0.0)
		s.hp += md.get("hp", 0)
		s.shield += md.get("shield", 0)
		s.regen += md.get("regen", 0.0)
		s.heat_passive += md.get("heat_passive", 0.0)
		s.speed_mult *= md.get("speed_mult", 1.0)
		s.spread_mult *= md.get("spread_mult", 1.0)
		s.range_mult *= md.get("range_mult", 1.0)
		s.mag_mult *= md.get("mag_mult", 1.0)
		s.reload_mult *= md.get("reload_mult", 1.0)
		s.rof_mult *= md.get("rof_mult", 1.0)

	var over: float = maxf(0.0, s.weight - s.max_weight)
	var under: float = maxf(0.0, s.max_weight - s.weight)
	s["overweight"] = over
	# Over budget: steep penalty. Under budget: a little spring in the step.
	var wf := clampf(1.0 - over * 0.07, 0.35, 1.0) + minf(under / s.max_weight, 0.3) * 0.25
	s["speed"] = float(c["speed"]) * s.speed_mult * wf
	s.heat_passive += over * 0.6
	s["power_ratio"] = clampf(s.power_out / maxf(s.power_draw, 0.001), 0.35, 1.0)
	return s


func weapon_stats(id: String, s: Dictionary) -> Dictionary:
	## Weapon data with the loadout's modifiers applied.
	if id == "":
		return {}
	var w: Dictionary = PartsDB.WEAPONS[id].duplicate()
	w["id"] = id
	# Swarm-clearing tuning: everything hits much harder, carries more, runs cooler.
	w.dmg *= DMG_MULT
	w.splash *= 1.25
	w.heat *= 0.8
	if w.mag > 0:
		w.mag = int(round(w.mag * 1.6))
	w.spread *= s.spread_mult
	w.range *= s.range_mult
	w.rof *= s.rof_mult * s.power_ratio
	if w.mag > 0:
		w.mag = int(round(w.mag * s.mag_mult))
		w.reload *= s.reload_mult
	return w
