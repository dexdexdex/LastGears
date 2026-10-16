class_name SquadBrain
extends RefCounted
## Utility AI for squadmates. Every ~0.25s each brain scores its options
## (follow / engage / cover / retreat / scavenge / repair) through its
## pilot's personality, picks one, then steers, aims and fires.

const PERSONALITIES := {
	"rook": {
		"tag": "Brawler", "aggression": 0.9, "caution": 0.15, "loyalty": 0.45, "greed": 0.2,
		"discipline": 0.2, "range": 150.0, "medic": false, "slot": Vector2(40, -70), "watch": 0.95,
		"barks": {
			"engage": ["Contact. Let 'em come.", "Fresh meat.", "Moving up!", "Mine."],
			"cover": ["On you, %s!", "Get behind me, %s.", "I've got %s's back."],
			"cover_refit": ["Do your wrenching, boss. Nothing gets past me.", "Refit away, I'll hold the line."],
			"retreat": ["Hull's cracking — pulling back. Temporarily.", "Fine. FINE. Falling back."],
			"scavenge": ["Grabbing scrap."],
			"scav_done": ["Picked up %s. Don't say I never share."],
			"kill_warden": ["Big one's scrap!", "Who's the warden now?"],
			"horde": ["Finally.", "Here they come. Good."],
			"clear": ["That's it? Hm.", "Clear. Barely warmed up."],
			"build": ["Something's stirring out there."],
			"ally_down": ["%s! ...They'll pay for that."],
			"low_hp": ["Took a beating. Still walking."],
			"overheat": ["Running hot!"],
			"form_0": ["On you, boss."], "form_1": ["Tightening up. Fine."], "form_2": ["Spreading out. More for me."], "form_3": ["Holding. Bring 'em here."],
		},
	},
	"wren": {
		"tag": "Marksman", "aggression": 0.4, "caution": 0.75, "loyalty": 0.35, "greed": 0.75,
		"discipline": 0.85, "range": 380.0, "medic": false, "slot": Vector2(-60, 70), "watch": -0.95,
		"barks": {
			"engage": ["Eyes on. Engaging at range.", "Got a line on them.", "Target marked."],
			"cover": ["Covering %s.", "Watching %s's flank."],
			"cover_refit": ["Overwatch up. Make it quick.", "I've got eyes on your perimeter."],
			"retreat": ["Too close. Repositioning.", "Need distance — falling back."],
			"scavenge": ["Cache on my scope. Grabbing it.", "Salvage nearby, going for it."],
			"scav_done": ["Got %s.", "Secured %s. We'll need it."],
			"kill_warden": ["Warden down.", "Heavy neutralized."],
			"horde": ["Seismic readings off the chart. Brace.", "Multiple signatures. A lot of them."],
			"clear": ["Sector quiet. For now. Check the caches.", "Clear. Use the time."],
			"build": ["Movement on the edge of scan.", "Readings picking up."],
			"ally_down": ["Lost %s's signal..."],
			"low_hp": ["I'm hurt. Staying back."],
			"overheat": ["Overheating, holding fire."],
			"form_0": ["Following."], "form_1": ["Closing in."], "form_2": ["Fanning out. Watching the flank."], "form_3": ["Holding position. Overwatch."],
		},
	},
	"mags": {
		"tag": "Medic", "aggression": 0.5, "caution": 0.5, "loyalty": 0.95, "greed": 0.3,
		"discipline": 0.6, "range": 260.0, "medic": true, "slot": Vector2(-70, -20), "watch": PI,
		"barks": {
			"engage": ["Engaging!", "They're on us!", "Contact, contact!"],
			"cover": ["Hang on %s, I'm coming!", "Covering %s!"],
			"cover_refit": ["Go on, fix her up. I'm right here.", "I've got you while you work."],
			"retreat": ["Can't patch anyone if I'm dead — backing off!"],
			"scavenge": ["Spare parts! One sec."],
			"scav_done": ["Found %s."],
			"repair": ["Hold still, %s, patching you.", "Sealing your breaches, %s."],
			"kill_warden": ["Got the big one!"],
			"horde": ["Oh no. Oh no no no. Stay together!", "Everyone close up!"],
			"clear": ["Okay. Okay. Everyone breathing?", "Clear. Let me look at those dents."],
			"build": ["Do you hear that?"],
			"ally_down": ["No — %s! I'm sorry..."],
			"low_hp": ["Hull integrity low!"],
			"overheat": ["Too hot, cooling off!"],
			"form_0": ["Right behind you!"], "form_1": ["Grouping up, stay close!"], "form_2": ["Spreading out — shout if you need me!"], "form_3": ["Holding here!"],
		},
	},
	# Used for --bot playtests: drives the player toward Haven.
	"lead": {
		"tag": "Lead", "aggression": 0.55, "caution": 0.5, "loyalty": 0.0, "greed": 0.35,
		"discipline": 0.6, "range": 300.0, "medic": false, "slot": Vector2.ZERO, "watch": 0.0, "barks": {},
	},
}

var mech: Mech
var key := ""
var p: Dictionary
var state := "follow"
var state_time := 0.0
var think_t := 0.0
var target = null                # EnemyManager.Enemy
var cover_ally: Mech
var cache = null
var heal_ally: Mech
var threat_center := Vector2.ZERO
var threats: Array = []
var path := PackedVector2Array()
var path_goal := Vector2.INF
var path_idx := 0
var path_t := 0.0
var stuck_t := 0.0
var last_pos := Vector2.ZERO
var bark_cd := 0.0
var bark_last := {}
var strafe := 1.0
var rng := RandomNumberGenerator.new()


func _init(m: Mech, personality: String) -> void:
	mech = m
	key = personality
	p = PERSONALITIES[personality]
	rng.randomize()
	strafe = 1.0 if rng.randf() < 0.5 else -1.0
	mech.role_tag = p.tag


func think(delta: float) -> void:
	state_time += delta
	think_t -= delta
	bark_cd -= delta
	path_t -= delta
	if think_t <= 0.0:
		think_t = 0.22 + rng.randf() * 0.1
		_decide()
	_act(delta)


# ---------------------------------------------------------------- deciding

func _decide() -> void:
	var player := G.player
	var pos := mech.position
	threats = G.enemies.query_radius(pos, 500.0).filter(
		func(e): return e.seen or e.pos.distance_squared_to(pos) < PROX * PROX)
	threats.sort_custom(func(a, b): return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
	if threats.size() > 30:
		threats.resize(30)
	threat_center = Vector2.ZERO
	for e in threats:
		threat_center += e.pos
	if not threats.is_empty():
		threat_center /= threats.size()
	target = _pick_target()
	_maybe_dodge()

	var self_pressure := 0
	for e in threats:
		if e.pos.distance_to(pos) < 150.0:
			self_pressure += 1
	var hp := mech.hp_ratio()
	var scores := {}
	var dp := pos.distance_to(_formation_goal()) if player and player != mech else 0.0

	if key != "lead":
		scores["follow"] = 0.25 + p.loyalty * 0.3 + clampf((dp - 40.0) / 220.0, 0.0, 1.0) * 0.9
		if G.formation == 1 or G.formation == 3:
			scores["follow"] += 0.15     # disciplined formations: stick to your spot
	else:
		scores["follow"] = 0.45      # lead heads east to the haven

	if target != null:
		scores["engage"] = 0.55 + p.aggression * 0.35 + minf(threats.size(), 10) * 0.02

	# Cover the squadmate who's under the most pressure.
	cover_ally = null
	var best_pressure := 0.0
	for m in G.squad:
		if m == mech or not m.alive:
			continue
		var pr := float(G.enemies.query_radius(m.position, 160.0).size())
		pr += (1.0 - m.hp_ratio()) * 4.0
		if m.is_player and m.busy_menu:
			pr += 4.0
		if m.is_player and m.repairing > 0.0:
			pr += 3.0
		if pr > best_pressure:
			best_pressure = pr
			cover_ally = m
	if cover_ally and best_pressure >= 3.0:
		scores["cover"] = 0.35 + p.loyalty * 0.45 + minf(best_pressure, 12.0) * 0.04

	if hp < 0.35:
		scores["retreat"] = 0.5 + p.caution * 0.6 - p.aggression * 0.3 + self_pressure * 0.03

	var calm := threats.filter(func(e): return e.pos.distance_to(pos) < 380.0).is_empty()
	if calm:
		cache = G.pickups.nearest(pos, 260.0 + p.greed * 220.0)
		if cache != null and ((key == "lead" and G.world.progress_of(mech.position) < 0.9) or (key != "lead" and cache.pos.distance_to(player.position) < 520.0)):
			scores["scavenge"] = 0.3 + p.greed * 0.55 if G.formation in [0, 2] else 0.0

	if p.medic:
		heal_ally = null
		var worst := 0.78
		for m in G.squad:
			if m != mech and m.alive and m.hp_ratio() < worst and m.repairing <= 0.0:
				worst = m.hp_ratio()
				heal_ally = m
		if heal_ally and self_pressure < 3:
			scores["repair"] = 0.6 + (1.0 - worst) * 0.7

	if scores.has(state):
		scores[state] += 0.12      # hysteresis: don't flip-flop
	var best := "follow"
	var bs := -1.0
	for k in scores:
		if scores[k] > bs:
			bs = scores[k]
			best = k
	if best != state:
		_on_state_change(state, best)
		state = best
		state_time = 0.0
		path_goal = Vector2.INF


func _maybe_dodge() -> void:
	## Roll away from a Tick about to pop, a Warden about to slam, or a
	## swarm closing in. Cautious pilots react more reliably.
	if not mech.can_dodge():
		return
	var pos := mech.position
	var danger := Vector2.ZERO
	var close := 0
	for e in threats:
		var d: float = e.pos.distance_to(pos)
		if e.type == "tick" and d < 85.0:
			danger += (pos - e.pos).normalized() * 3.0
		elif e.type == "warden" and d < mech.radius + 30.0:
			danger += (pos - e.pos).normalized() * 2.0
		elif d < 45.0:
			close += 1
			danger += (pos - e.pos).normalized() * 0.3
	if danger == Vector2.ZERO or (danger.length() < 2.0 and close < 6):
		return
	if rng.randf() > 0.45 + p.caution * 0.5:
		return
	var dir := danger.normalized().rotated(rng.randf_range(-0.5, 0.5))
	for t in 4:
		if not G.world.circle_hits(pos + dir * 70.0, mech.radius):
			break
		dir = dir.rotated(PI / 3.0 * (1 if t % 2 == 0 else -1) * (t + 1))
	if mech.try_dodge(dir):
		dodges += 1


var dodges := 0
const PROX := 110.0     # hull proximity sensor: always aware this close


func _pick_target():
	var pos := mech.position
	var best = null
	var bs := -INF
	var checked := 0
	for e in threats:
		checked += 1
		if checked > 14:
			break
		var d: float = e.pos.distance_to(pos)
		if d > 520.0 or not G.world.has_los(pos, e.pos):
			continue
		var s := 400.0 / maxf(d, 30.0)
		if e.type == "tick" and d < 240.0:
			s *= 2.5 + p.caution * 2.0
		if e.type == "warden":
			s *= 1.0 + p.aggression * 1.5
		if e.type == "spitter":
			s *= 1.0 + p.caution * 0.8
		if G.player and G.player != mech and e.pos.distance_to(G.player.position) < 140.0:
			s *= 1.0 + p.loyalty
		if e == target:
			s *= 1.3                  # stick with a target
		if s > bs:
			bs = s
			best = e
	return best


func _on_state_change(old: String, new: String) -> void:
	match new:
		"engage":
			if old != "cover":
				bark("engage")
		"cover":
			if cover_ally and cover_ally.is_player and cover_ally.busy_menu:
				bark("cover_refit")
			elif cover_ally:
				bark("cover", false, cover_ally.callsign)
		"retreat":
			bark("retreat", true)
		"scavenge":
			bark("scavenge")
		"repair":
			if heal_ally:
				bark("repair", false, heal_ally.callsign)
	mech.state_label = _label_for(new)


func _label_for(s: String) -> String:
	match s:
		"follow": return "FOLLOWING"
		"engage": return "ENGAGING"
		"cover": return "COVERING %s" % (cover_ally.callsign if cover_ally else "")
		"retreat": return "FALLING BACK"
		"scavenge": return "SCAVENGING"
		"repair": return "REPAIRING %s" % (heal_ally.callsign if heal_ally else "")
	return s.to_upper()


# ---------------------------------------------------------------- acting

func _act(delta: float) -> void:
	var pos := mech.position
	var player := G.player
	var desired := Vector2.ZERO
	mech.repair_beam_target = null
	if target != null and not target.alive:
		target = null

	match state:
		"follow":
			if key == "lead":
				desired = _navigate(_road_goal(), delta)
			else:
				var goal: Vector2 = _formation_goal()
				if pos.distance_to(goal) > 28.0:
					desired = _navigate(goal, delta)
		"engage":
			if target != null:
				var d: float = target.pos.distance_to(pos)
				var to_t: Vector2 = (target.pos - pos).normalized()
				# preferred range, but never outside what the primary can reach
				var ws_r: Mech.WeaponState = mech.weapons["primary"]
				var want: float = p.range
				if ws_r:
					want = clampf(float(ws_r.data.range) * 0.8, 90.0, p.range)
				if d > want + 50.0:
					desired = _navigate(target.pos, delta)
				elif d < want - 70.0:
					desired = (-to_t + to_t.orthogonal() * strafe * 0.4).normalized()
				else:
					desired = to_t.orthogonal() * strafe * 0.45
					if rng.randf() < 0.01:
						strafe *= -1.0
				# leash: don't wander off from the lead
				if key != "lead":
					var leash: float = (260.0 + (1.0 - p.loyalty) * 240.0) * [1.0, 0.6, 1.5, 0.8][G.formation]
					var anchor: Vector2 = G.hold_pos if G.formation == 3 else player.position
					if pos.distance_to(anchor) > leash:
						desired = (desired * 0.3 + _navigate(anchor, delta)).normalized()
		"cover":
			if cover_ally and cover_ally.alive:
				var away: Vector2 = threat_center - cover_ally.position if threat_center != Vector2.ZERO else cover_ally.facing
				var goal: Vector2 = cover_ally.position + away.normalized() * 60.0
				if pos.distance_to(goal) > 20.0:
					desired = _navigate(goal, delta)
		"retreat":
			var anchor := player.position if player != mech else G.world.goal_zone.get_center()
			var flee := (anchor - threat_center).normalized() if threat_center != Vector2.ZERO else Vector2.ZERO
			desired = _navigate(anchor + flee * 70.0, delta)
		"scavenge":
			if cache != null and not cache.taken:
				desired = _navigate(cache.pos, delta)
			else:
				state_time = 99.0
				think_t = 0.0
		"repair":
			if heal_ally and heal_ally.alive:
				var d2 := pos.distance_to(heal_ally.position)
				if d2 > 55.0:
					desired = _navigate(heal_ally.position, delta)
				if d2 < 90.0 and G.world.has_los(pos, heal_ally.position):
					heal_ally.receive_repair(16.0 * delta)
					mech.repair_beam_target = heal_ally
			else:
				think_t = 0.0

	# Stuck? replan and sidestep.
	if desired.length() > 0.3:
		if pos.distance_to(last_pos) < 0.5 * mech.speed() * delta:
			stuck_t += delta
		else:
			stuck_t = maxf(0.0, stuck_t - delta)
		if stuck_t > 0.8:
			stuck_t = 0.0
			path_goal = Vector2.INF
			desired = desired.orthogonal() * strafe
	last_pos = pos
	mech.move_input = desired.limit_length(1.0)
	_aim_and_fire()


func _formation_goal() -> Vector2:
	var player := G.player
	var ang := player.facing.angle()
	match G.formation:
		1:  # group up: tight around the lead
			return player.position + (p.slot * 0.5).rotated(ang)
		2:  # spread out: wide arc, more ground covered
			return player.position + (p.slot.normalized() * 200.0).rotated(ang)
		3:  # hold: stay where the order was given
			return G.hold_pos + p.slot * 0.7
	return player.position + p.slot.rotated(ang)


func _road_goal() -> Vector2:
	return G.world.goal_zone.get_center()


func _navigate(goal: Vector2, _delta: float) -> Vector2:
	var pos := mech.position
	if not G.world.segment_blocked(pos, goal) and pos.distance_to(goal) < 700.0:
		var dv := goal - pos
		return dv.normalized() * clampf(dv.length() / 50.0, 0.0, 1.0)
	if path_goal == Vector2.INF or path_goal.distance_to(goal) > 60.0 or path_t <= 0.0:
		path = G.world.find_path(pos, goal)
		path_goal = goal
		path_idx = 0
		path_t = 0.8
	while path_idx < path.size() and path[path_idx].distance_to(pos) < 22.0:
		path_idx += 1
	# shortcut: skip ahead to the furthest visible waypoint (cheap check)
	if path_idx + 2 < path.size() and not G.world.segment_blocked(pos, path[path_idx + 2]):
		path_idx += 1
	if path_idx < path.size():
		return (path[path_idx] - pos).normalized()
	return (goal - pos).normalized()


func _aim_and_fire() -> void:
	mech.want_primary = false
	mech.want_secondary = false
	var pos := mech.position
	if target == null:
		var look: Vector2
		if threat_center != Vector2.ZERO:
			look = (threat_center - pos).normalized()
		elif mech == G.player:
			look = mech.vel.normalized() if mech.vel.length() > 10.0 else mech.aim_dir
		else:
			# cover the arc the lead isn't looking at, with a slow scan
			look = G.player.aim_dir.rotated(p.watch + sin(G.game_time * 0.6 + p.watch * 3.0) * 0.45)
		mech.aim_dir = mech.aim_dir.slerp(look, 0.08).normalized()
		return
	var d: float = target.pos.distance_to(pos)
	var ws_p: Mech.WeaponState = mech.weapons["primary"]
	var spd: float = ws_p.data.speed if ws_p else 800.0
	if spd <= 1.0:
		spd = 1e6       # beams / arcs are instant
	var lead: Vector2 = target.pos + target.vel * (d / spd)
	mech.aim_dir = (lead - pos).normalized()
	mech.aim_dist = d
	var heat_limit: float = 96.0 - p.discipline * 26.0
	if mech.heat > heat_limit:
		return
	if _friendly_in_line(lead):
		return
	if ws_p and d <= float(ws_p.data.range) * 1.02:
		mech.want_primary = true
	var ws_s: Mech.WeaponState = mech.weapons["secondary"]
	if ws_s:
		var sd: Dictionary = ws_s.data
		var in_range: bool = d <= float(sd.range) and d >= float(sd.get("min_range", 0.0))
		if in_range:
			if float(sd.get("splash", 0.0)) > 0.0:
				var cluster := G.enemies.query_radius(target.pos, 70.0).size()
				# never splash near a squadmate
				var safe := true
				for m in G.squad:
					if m.alive and m.position.distance_to(target.pos) < float(sd.splash) + 20.0:
						safe = false
				if safe and (cluster >= 4 or target.type == "warden"):
					mech.want_secondary = true
			else:
				mech.want_secondary = true


func _friendly_in_line(at: Vector2) -> bool:
	var pos := mech.position
	for m in G.squad:
		if m == mech or not m.alive:
			continue
		if m.position.distance_to(pos) > pos.distance_to(at):
			continue
		var cp := Geometry2D.get_closest_point_to_segment(m.position, pos, at)
		if cp.distance_to(m.position) < m.radius + 6.0:
			return true
	return false


# ---------------------------------------------------------------- events / barks

func on_kill(e) -> void:
	if e.type == "warden":
		bark("kill_warden", true)


func on_ally_down(m: Mech) -> void:
	bark("ally_down", true, m.callsign)


func on_scavenged(txt: String, _was_cache: bool) -> void:
	bark("scav_done", true, txt)
	state_time = 99.0
	think_t = 0.0


func bark(event: String, force: bool = false, arg: String = "") -> void:
	var lines: Array = p.barks.get(event, [])
	if lines.is_empty():
		return
	if not force and (bark_cd > 0.0 or G.game_time - bark_last.get(event, -99.0) < 12.0):
		return
	bark_cd = 4.0
	bark_last[event] = G.game_time
	var line: String = lines[rng.randi() % lines.size()]
	if "%s" in line:
		line = line % arg
	G.say(mech.callsign, line, mech.color.lightened(0.3))
