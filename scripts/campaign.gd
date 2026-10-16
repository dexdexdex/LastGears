class_name Campaign
extends RefCounted
## Everything that persists between legs: where the squad is, where it's
## going, credits, materials, spare parts, and each mech's loadout, hull
## and whether its pilot is still alive. Lives in G.campaign (autoload),
## so it survives the scene reload that builds each new leg.

const SQUAD_DEF := [
	# callsign, pilot, personality, color, chassis, primary, secondary, modules
	["VANGUARD", "You", "", Color(0.45, 0.85, 1.0), "vanguard", "autocannon", "rockets", ["heat_sink", "targeting"]],
	["ROOK", "Ilya Rooker", "rook", Color(1.0, 0.55, 0.35), "bulwark", "flak", "rockets", ["armor_plate", "heat_sink", "ammo_rack"]],
	["WREN", "Sade Okonkwo", "wren", Color(0.75, 0.95, 0.45), "kestrel", "laser", "mortar", ["targeting", "reactor"]],
	["MAGS", "Magda Vell", "mags", Color(0.9, 0.7, 1.0), "sparrow", "gatling", "", ["repair_drone", "shield", "heat_sink"]],
]
const RECRUITS := ["Teo Marsh", "Ana Petrak", "Joss Imani", "Kit Varga", "Rune Calder", "Oyelaran", "Nell Szabo", "Duc Pham"]

# kill bounties paid by havens on arrival
const BOUNTY := {"crawler": 0.2, "skitter": 0.5, "spitter": 1.5, "tick": 1.5, "warden": 12.0}

var node_idx := 0                 # where we are (or departed from)
var dest_idx := 0                 # where this leg goes
var credits := 150
var materials := {"scrap": 24, "circuits": 8, "cells": 5}
var inventory := {}               # part_id -> count (spare parts, not fitted)
var squad: Array = []             # [{def, loadout, hp_ratio, alive, pilot}]
var legs := 0                     # legs completed
var visited := {}
var stock := {}                   # node_idx -> {"parts": [ids], "prices": {...}}
var leg_seed := 0
var rng := RandomNumberGenerator.new()


func _init(atlas: Atlas, seed_value: int) -> void:
	rng.seed = seed_value
	node_idx = atlas.start_idx
	dest_idx = atlas.goal_idx
	visited[node_idx] = true
	leg_seed = seed_value
	for d in SQUAD_DEF:
		squad.append({"def": d, "pilot": d[1], "loadout": random_loadout(d), "hp_ratio": 1.0, "alive": true})
	inventory = {"heat_sink": 1, "armor_plate": 1}


func random_loadout(d: Array) -> Loadout:
	## Keep each frame's role modules, roll two different weapons that fit
	## within the frame's weight limit (+1 grace).
	var ids: Array = PartsDB.WEAPONS.keys()
	var best: Loadout = Loadout.new(d[4], d[5], d[6], d[7])
	for attempt in 60:
		var p: String = ids[rng.randi() % ids.size()]
		var s: String = ids[rng.randi() % ids.size()]
		if s == p:
			continue
		var lo := Loadout.new(d[4], p, s, d[7])
		var st := lo.compute()
		if st.weight <= st.max_weight + 1:
			return lo
		best = lo
	for i in range(best.modules.size() - 1, -1, -1):
		if best.compute().weight <= best.compute().max_weight + 1:
			break
		best.modules[i] = ""
	return best


# ---------------------------------------------------------------- legs

func current_edge(atlas: Atlas) -> Dictionary:
	for e in atlas.edges:
		if (e.a == node_idx and e.b == dest_idx) or (e.b == node_idx and e.a == dest_idx):
			return e
	return atlas.edges[0]


func threat(atlas: Atlas) -> int:
	return int(current_edge(atlas).threat)


func sync_atlas(atlas: Atlas) -> void:
	atlas.start_idx = node_idx
	atlas.goal_idx = dest_idx
	for i in atlas.edges.size():
		var e: Dictionary = atlas.edges[i]
		if (e.a == node_idx and e.b == dest_idx) or (e.b == node_idx and e.a == dest_idx):
			atlas.current_edge = i
	for e in atlas.edges:
		if visited.has(e.a) or visited.has(e.b):
			e.known = true


func routes_from(atlas: Atlas, idx: int) -> Array:
	## Adjacent nodes the squad can travel to (not machine hives).
	var out: Array = []
	for e in atlas.edges:
		var other := -1
		if e.a == idx:
			other = e.b
		elif e.b == idx:
			other = e.a
		if other >= 0 and atlas.nodes[other].kind != "hive":
			out.append({"to": other, "edge": e})
	out.sort_custom(func(x, y): return x.edge.threat < y.edge.threat)
	return out


func store_squad(mechs: Array) -> void:
	## Copy live mech state back into the campaign at the end of a leg.
	for entry in squad:
		var found := false
		for m in mechs:
			if m.callsign == entry.def[0]:
				found = true
				entry.loadout = m.loadout.copy()
				# parts still mid-install count as fitted
				for k in m.installing:
					entry.loadout.set_slot(k, m.installing[k].part)
				entry.alive = m.alive
				entry.hp_ratio = m.hp_ratio() if m.alive else 0.0


func arrive(atlas: Atlas, mechs: Array, mats: Dictionary, leg_kills: Dictionary) -> Dictionary:
	## Returns a summary of the leg for the arrival screen.
	store_squad(mechs)
	materials = mats.duplicate()
	var t := threat(atlas)
	var bf := 0.0
	for k in leg_kills:
		bf += float(BOUNTY.get(k, 0.5)) * int(leg_kills[k])
	var bounty := int(bf)
	var delivery := 50 + t * 35
	credits += bounty + delivery
	node_idx = dest_idx
	visited[node_idx] = true
	legs += 1
	sync_atlas(atlas)
	return {"bounty": bounty, "delivery": delivery, "threat": t}


func depart(atlas: Atlas, to_idx: int) -> void:
	dest_idx = to_idx
	leg_seed = rng.randi()
	sync_atlas(atlas)


# ---------------------------------------------------------------- station economy

func station(atlas: Atlas, idx: int) -> Dictionary:
	## Stock and prices are rolled once per visit count, so they refresh
	## when you come back later.
	var key := "%d:%d" % [idx, legs]
	if stock.has(key):
		return stock[key]
	var r := RandomNumberGenerator.new()
	r.seed = idx * 7919 + legs * 104729 + 17
	var kind: String = atlas.nodes[idx].kind
	var base := {"scrap": 3, "circuits": 9, "cells": 14}
	var prices := {}
	for m in base:
		var sell := maxi(1, int(round(base[m] * r.randf_range(0.7, 1.3))))
		prices[m] = {"sell": sell, "buy": int(ceil(sell * 1.7))}
	var all: Array = PartsDB.WEAPONS.keys() + PartsDB.MODULES.keys()
	var parts: Array = []
	var n := 7 if kind == "haven" else (4 if kind == "outpost" else 0)
	for i in n:
		var id: String = all[r.randi() % all.size()]
		if not parts.has(id):
			parts.append(id)
	var st := {"parts": parts, "prices": prices, "kind": kind,
		"market": kind != "ruin", "hire": kind == "haven", "repair_rate": 0.6 if kind == "haven" else 0.9}
	stock[key] = st
	return st


static func part_price(id: String) -> int:
	var c: Dictionary = PartsDB.part(id).get("cost", {})
	return 25 + int(c.get("scrap", 0)) * 4 + int(c.get("circuits", 0)) * 11 + int(c.get("cells", 0)) * 16


static func part_sell_price(id: String) -> int:
	return int(part_price(id) * 0.45)


func repair_cost(entry: Dictionary, rate: float) -> int:
	if not entry.alive:
		return 0
	var max_hp: float = entry.loadout.compute().hp
	return int(ceil(max_hp * (1.0 - entry.hp_ratio) * rate))


func add_part(id: String, n: int = 1) -> void:
	if id == "":
		return
	inventory[id] = int(inventory.get(id, 0)) + n
	if inventory[id] <= 0:
		inventory.erase(id)


func hire(entry: Dictionary) -> void:
	entry.alive = true
	entry.hp_ratio = 1.0
	entry.pilot = RECRUITS[rng.randi() % RECRUITS.size()]
	entry.loadout = random_loadout(entry.def)
