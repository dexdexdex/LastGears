class_name PartsDB
extends RefCounted
## All tunable mech data lives here. Mech Engineer–style trade-offs:
## every part has weight (vs. frame max), power draw (vs. reactor output)
## and heat (vs. cooling). Going over budget is allowed but punished.

const CHASSIS := {
	"vanguard": {
		"name": "Vanguard", "role": "Line frame",
		"hp": 240, "frame_weight": 10, "max_weight": 32, "power": 12, "cooling": 16,
		"speed": 100.0, "radius": 11.0, "module_slots": 4,
	},
	"bulwark": {
		"name": "Bulwark", "role": "Heavy frame",
		"hp": 340, "frame_weight": 14, "max_weight": 42, "power": 11, "cooling": 14,
		"speed": 84.0, "radius": 13.0, "module_slots": 4,
	},
	"kestrel": {
		"name": "Kestrel", "role": "Light frame",
		"hp": 170, "frame_weight": 7, "max_weight": 24, "power": 13, "cooling": 18,
		"speed": 116.0, "radius": 9.0, "module_slots": 3,
	},
	"sparrow": {
		"name": "Sparrow", "role": "Support frame",
		"hp": 210, "frame_weight": 9, "max_weight": 28, "power": 15, "cooling": 16,
		"speed": 104.0, "radius": 10.0, "module_slots": 4,
	},
}

# dmg per projectile, rof shots/s, spread degrees (full cone), speed px/s,
# range px, heat per shot, power draw, weight, mag (0 = energy weapon, no ammo)
const WEAPONS := {
	"autocannon": {
		"name": "AC-20 Autocannon", "short": "AUTOCANNON",
		"dmg": 15.0, "rof": 4.5, "spread": 4.0, "speed": 900.0, "range": 520.0, "pellets": 1,
		"splash": 0.0, "pierce": false, "lob": false,
		"heat": 3.2, "power": 2, "weight": 6, "mag": 40, "reload": 2.2,
		"color": Color(1.0, 0.9, 0.55), "width": 2.0,
		"cost": {"scrap": 6, "circuits": 1},
		"desc": "Reliable mid-range cannon. Punches through armour well.",
	},
	"gatling": {
		"name": "Rotary Gatling", "short": "GATLING",
		"dmg": 6.0, "rof": 15.0, "spread": 10.0, "speed": 1000.0, "range": 420.0, "pellets": 1,
		"splash": 0.0, "pierce": false, "lob": false,
		"heat": 1.3, "power": 3, "weight": 7, "mag": 160, "reload": 3.5,
		"color": Color(1.0, 0.8, 0.4), "width": 1.5,
		"cost": {"scrap": 8, "circuits": 1},
		"desc": "Hose for swarms. Small rounds bounce off armoured targets.",
	},
	"flak": {
		"name": "Flak Scattergun", "short": "FLAK",
		"dmg": 8.0, "rof": 1.5, "spread": 26.0, "speed": 780.0, "range": 250.0, "pellets": 9,
		"splash": 0.0, "pierce": false, "lob": false,
		"heat": 6.5, "power": 1, "weight": 5, "mag": 8, "reload": 2.0,
		"color": Color(1.0, 0.75, 0.5), "width": 1.5,
		"cost": {"scrap": 5},
		"desc": "Close-range wall of shrapnel.",
	},
	"rockets": {
		"name": "Rocket Pod", "short": "ROCKETS",
		"dmg": 34.0, "rof": 2.5, "spread": 6.0, "speed": 460.0, "range": 600.0, "pellets": 1,
		"splash": 62.0, "pierce": false, "lob": false,
		"heat": 5.0, "power": 1, "weight": 8, "mag": 12, "reload": 4.0,
		"color": Color(1.0, 0.55, 0.3), "width": 3.0,
		"cost": {"scrap": 8, "circuits": 2},
		"desc": "Explosive rockets. Burst a crowd, crack a Warden.",
	},
	"laser": {
		"name": "Pulse Laser", "short": "LASER",
		"dmg": 9.0, "rof": 12.0, "spread": 1.5, "speed": 2400.0, "range": 480.0, "pellets": 1,
		"splash": 0.0, "pierce": true, "lob": false,
		"heat": 2.6, "power": 6, "weight": 4, "mag": 0, "reload": 0.0,
		"color": Color(0.5, 1.0, 0.95), "width": 2.0,
		"cost": {"scrap": 4, "circuits": 3, "cells": 2},
		"desc": "No ammo, pierces lines of enemies. Power hungry and runs hot.",
	},
	"mortar": {
		"name": "Field Mortar", "short": "MORTAR",
		"dmg": 46.0, "rof": 0.8, "spread": 3.0, "speed": 380.0, "range": 640.0, "pellets": 1,
		"splash": 92.0, "pierce": false, "lob": true, "min_range": 120.0,
		"heat": 7.0, "power": 1, "weight": 10, "mag": 6, "reload": 5.0,
		"color": Color(1.0, 0.65, 0.35), "width": 3.0,
		"cost": {"scrap": 10, "circuits": 2},
		"desc": "Lobbed shells over cover. Lands at your aim point.",
	},
	"flamer": {
		"name": "Incinerator", "short": "FLAMER",
		"dmg": 4.0, "rof": 22.0, "spread": 20.0, "speed": 420.0, "range": 170.0, "pellets": 1,
		"splash": 0.0, "pierce": true, "lob": false,
		"heat": 1.1, "power": 1, "weight": 5, "mag": 200, "reload": 4.0,
		"color": Color(1.0, 0.5, 0.15), "width": 4.0,
		"cost": {"scrap": 5, "cells": 1},
		"desc": "Short-range stream that burns through packed swarms.",
	},
	"railgun": {
		"name": "Rail Driver", "short": "RAILGUN", "mode": "beam",
		"dmg": 70.0, "rof": 0.75, "spread": 0.5, "speed": 0.0, "range": 780.0, "pellets": 1,
		"splash": 0.0, "pierce": true, "lob": false,
		"heat": 14.0, "power": 5, "weight": 9, "mag": 6, "reload": 3.0,
		"color": Color(0.55, 0.85, 1.0), "width": 4.0,
		"cost": {"scrap": 8, "circuits": 4, "cells": 2},
		"desc": "Hypervelocity slug. Punches through every machine in a line, all the way to the wall.",
	},
	"arc": {
		"name": "Arc Caster", "short": "ARC", "mode": "chain", "chains": 6, "chain_r": 125.0,
		"dmg": 14.0, "rof": 3.2, "spread": 0.0, "speed": 0.0, "range": 320.0, "pellets": 1,
		"splash": 0.0, "pierce": false, "lob": false,
		"heat": 4.0, "power": 5, "weight": 5, "mag": 0, "reload": 0.0,
		"color": Color(0.6, 0.72, 1.0), "width": 2.0,
		"cost": {"circuits": 4, "cells": 2},
		"desc": "Lightning that leaps between up to six machines. No ammo; power hungry.",
	},
	"cluster": {
		"name": "Cluster Mortar", "short": "CLUSTER", "mode": "cluster", "bomblets": 7,
		"dmg": 12.0, "rof": 0.7, "spread": 4.0, "speed": 360.0, "range": 620.0, "pellets": 1,
		"splash": 46.0, "pierce": false, "lob": true, "min_range": 140.0,
		"heat": 7.0, "power": 1, "weight": 9, "mag": 5, "reload": 5.0,
		"color": Color(1.0, 0.62, 0.3), "width": 3.0,
		"cost": {"scrap": 10, "circuits": 3},
		"desc": "Lobbed shell that bursts into a carpet of bomblets. Swarm eraser.",
	},
	"swarm": {
		"name": "Swarm Pod", "short": "SWARM", "mode": "homing", "turn": 5.5,
		"dmg": 14.0, "rof": 6.0, "spread": 34.0, "speed": 330.0, "range": 640.0, "pellets": 1,
		"splash": 30.0, "pierce": false, "lob": false,
		"heat": 2.5, "power": 2, "weight": 7, "mag": 24, "reload": 4.0,
		"color": Color(1.0, 0.82, 0.45), "width": 2.0,
		"cost": {"scrap": 6, "circuits": 4, "cells": 1},
		"desc": "Micro-missiles that hunt the nearest machine.",
	},
}

# Module effect keys:
#  hp, cooling, power_out, speed_mult, shield, spread_mult, range_mult,
#  mag_mult, reload_mult, regen, heat_passive, rof_mult
const MODULES := {
	"armor_plate": {
		"name": "Composite Plating", "short": "PLATING", "weight": 6, "power": 0,
		"hp": 70, "cost": {"scrap": 6},
		"desc": "+70 hull. Heavy.",
	},
	"heat_sink": {
		"name": "Heat Sink Array", "short": "HEATSINK", "weight": 3, "power": 1,
		"cooling": 9.0, "cost": {"scrap": 3, "circuits": 1},
		"desc": "+9 cooling/s. Fire longer before shutdown.",
	},
	"reactor": {
		"name": "Reactor Booster", "short": "REACTOR", "weight": 4, "power": 0,
		"power_out": 6, "heat_passive": 2.0, "cost": {"scrap": 4, "cells": 2},
		"desc": "+6 power output, but the core runs warmer.",
	},
	"servos": {
		"name": "Leg Servos", "short": "SERVOS", "weight": 2, "power": 2,
		"speed_mult": 1.18, "cost": {"scrap": 3, "circuits": 2},
		"desc": "+18% walk speed.",
	},
	"shield": {
		"name": "Barrier Projector", "short": "SHIELD", "weight": 3, "power": 5,
		"shield": 70, "cost": {"circuits": 3, "cells": 2},
		"desc": "70-point regenerating shield. Big power draw.",
	},
	"targeting": {
		"name": "Targeting Computer", "short": "TARGETING", "weight": 1, "power": 2,
		"spread_mult": 0.6, "range_mult": 1.15, "cost": {"circuits": 3},
		"desc": "-40% spread, +15% range.",
	},
	"ammo_rack": {
		"name": "Ammo Rack", "short": "AMMO RACK", "weight": 3, "power": 0,
		"mag_mult": 1.5, "reload_mult": 0.8, "cost": {"scrap": 4},
		"desc": "+50% magazine, faster reloads.",
	},
	"repair_drone": {
		"name": "Repair Drone", "short": "REPAIR", "weight": 2, "power": 3,
		"regen": 2.5, "cost": {"scrap": 3, "circuits": 2, "cells": 1},
		"desc": "Slowly patches hull (2.5/s).",
	},
	"cycler": {
		"name": "Fire Cycler", "short": "CYCLER", "weight": 2, "power": 3,
		"rof_mult": 1.25, "heat_passive": 1.0, "cost": {"circuits": 2, "cells": 1},
		"desc": "+25% fire rate on all weapons. More heat.",
	},
}

const REPAIR_COST := {"scrap": 5}
const REPAIR_AMOUNT := 80.0
const REPAIR_TIME := 4.0


static func part(id: String) -> Dictionary:
	if WEAPONS.has(id):
		return WEAPONS[id]
	if MODULES.has(id):
		return MODULES[id]
	return {}


static func install_time(id: String) -> float:
	if id == "":
		return 1.2
	var p := part(id)
	return 1.5 + float(p.get("weight", 2)) * 0.25
