class_name Director
extends Node
## Left 4 Dead–style pacing. Tracks how hard the squad is being pushed
## (intensity) and cycles between three phases:
##   RELAX  – nothing spawns. Breathe, scavenge, refit.
##   BUILD  – small packs trickle in from out of sight.
##   PEAK   – a horde. Ends once the area is clear, then back to RELAX.

enum Phase { RELAX, BUILD, PEAK }
const PHASE_NAMES := ["RELAX", "BUILD-UP", "PEAK"]

var phase: int = Phase.RELAX
var t := 0.0
var intensity := 0.0            # 0..100, the squad's "stress"
var relax_len := 14.0           # first lull is short
var build_len := 40.0
var trickle_t := 4.0
var horde_budget := 0
var horde_spawned := 0
var horde_tick := 0.0
var horde_dirs: Array = []
var hordes := 0
var max_enemies := 1000
var rng := RandomNumberGenerator.new()
var log_lines: Array = []       # debug history


func _ready() -> void:
	rng.randomize()


func populate_zone() -> void:
	## Dormant crawler fields scattered across the zone at the start of a leg.
	var r := RandomNumberGenerator.new()
	r.seed = G.world.rng.seed + 5
	G.enemies.seed_dormant(int(G.world.W * G.world.H / 160.0) + G.threat * 40, G.world.start_c, r)


func report_damage(amount: float, _m: Mech) -> void:
	intensity = minf(100.0, intensity + amount * 0.35)


func report_kill() -> void:
	intensity = minf(100.0, intensity + 0.5)


func near_count() -> int:
	return G.enemies.count_near(G.squad_centroid(), 520.0)


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_body(delta)
	G.pe("director", _t0)


func _process_body(delta: float) -> void:
	if G.game_state != "play" or G.alive_squad().is_empty():
		return
	t += delta
	var near := near_count()
	# Intensity decays fast when nothing's around, slowly in a fight.
	intensity -= (9.0 if near < 3 else 1.5) * delta
	intensity += minf(near, 40) * 0.06 * delta
	intensity = clampf(intensity, 0.0, 100.0)
	var prog := G.world.progress_of(G.squad_centroid())

	match phase:
		Phase.RELAX:
			if t > relax_len and near < 3:
				_enter(Phase.BUILD)
		Phase.BUILD:
			trickle_t -= delta
			if trickle_t <= 0.0:
				trickle_t = rng.randf_range(3.5, 6.5) / (1.0 + prog)
				_spawn_pack(int((rng.randi_range(10, 18) + prog * 14.0) * (0.7 + 0.15 * G.threat)), prog, false)
			if t > build_len or intensity > 70.0:
				_enter(Phase.PEAK)
		Phase.PEAK:
			if horde_spawned < horde_budget:
				horde_tick -= delta
				if horde_tick <= 0.0:
					horde_tick = 0.5
					var n := mini(22, horde_budget - horde_spawned)
					_spawn_pack(n, prog, true)
					horde_spawned += n
			elif t > 12.0 and G.enemies.count_near(G.squad_centroid(), 1100.0) < 4:
				_enter(Phase.RELAX)


func _enter(p: int) -> void:
	phase = p
	t = 0.0
	match p:
		Phase.RELAX:
			relax_len = rng.randf_range(18.0, 28.0)
			G.announce("AREA CLEAR", Color(0.6, 1.0, 0.7))
			_squad_bark("clear")
		Phase.BUILD:
			build_len = rng.randf_range(30.0, 45.0)
			trickle_t = 2.0
			_squad_bark("build")
		Phase.PEAK:
			hordes += 1
			var prog := G.world.progress_of(G.squad_centroid())
			horde_budget = int((140 + hordes * 40 + prog * 120) * (0.6 + 0.2 * G.threat))
			horde_spawned = 0
			horde_tick = 2.5     # a beat of warning before they arrive
			var base := rng.randf() * TAU
			horde_dirs = [base]
			if hordes >= 2:
				horde_dirs.append(base + rng.randf_range(1.6, 3.0))
			G.announce("SEISMIC CONTACT — HORDE INBOUND", Color(1, 0.4, 0.3))
			G.enemies.wake_around(G.squad_centroid(), 900.0)
			_squad_bark("horde")
	log_lines.append("%5.0fs %s" % [G.game_time, PHASE_NAMES[p]])
	if G.bot_mode:
		print("[director] %6.1fs -> %s  (intensity %.0f, enemies %d)" % [G.game_time, PHASE_NAMES[p], intensity, G.enemies.alive_count()])


func _spawn_pack(n: int, prog: float, horde: bool) -> void:
	if G.enemies.alive_count() >= max_enemies:
		return
	var center := G.squad_centroid()
	var angle: float = horde_dirs[rng.randi() % horde_dirs.size()] if horde else rng.randf() * TAU
	# Lean packs toward the direction of travel so they meet you, not chase you.
	if not horde and rng.randf() < 0.5:
		angle = G.world.dir.angle() + rng.randf_range(-1.0, 1.0)
	var origin := _find_spawn(center, angle)
	if origin == Vector2.INF:
		return
	for i in n:
		var type := _roll_type(prog, horde)
		var p := G.world.nearest_free(origin + Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50)))
		G.enemies.spawn(type, p)
	if horde and horde_spawned == 0:
		var wardens := 1 + hordes / 2 + (1 if G.threat >= 4 else 0)
		for i in wardens:
			G.enemies.spawn("warden", G.world.nearest_free(origin + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))))


func _roll_type(prog: float, horde: bool) -> String:
	## Mostly slow crawlers; some medium skitters; a few fast ticks.
	var r := rng.randf()
	var tick_p := 0.03 + prog * 0.03 + (0.02 if horde else 0.0)
	var spit_p := 0.07 + prog * 0.05
	var skit_p := 0.18 + prog * 0.08
	if r < tick_p:
		return "tick"
	if r < tick_p + spit_p:
		return "spitter"
	if r < tick_p + spit_p + skit_p:
		return "skitter"
	if not horde and r > 0.995 - prog * 0.01:
		return "warden"
	return "crawler"


func _find_spawn(center: Vector2, angle: float) -> Vector2:
	## A free spot 650–950px out, ideally out of the player's sight and off camera.
	var view := G.camera.view_rect() if G.camera else Rect2(center - Vector2(800, 450), Vector2(1600, 900))
	var fallback := Vector2.INF
	for i in 24:
		var a := angle + rng.randf_range(-0.6, 0.6)
		var p := center + Vector2.from_angle(a) * rng.randf_range(650.0, 950.0)
		var sz := G.world.size_px()
		if p.x < 40 or p.y < 40 or p.x > sz.x - 40 or p.y > sz.y - 40:
			continue
		if G.world.is_solid_at(p) or G.world.start_zone.grow(150).has_point(p) or G.world.goal_zone.grow(100).has_point(p):
			continue
		if view.grow(40).has_point(p):
			continue
		if fallback == Vector2.INF:
			fallback = p
		if G.player and not G.world.has_los(G.player.position, p):
			return p
	return fallback


func _squad_bark(event: String) -> void:
	var talkers := G.alive_squad().filter(func(m): return m.brain != null and not m.is_player)
	if talkers.is_empty():
		return
	var m: Mech = talkers[rng.randi() % talkers.size()]
	m.brain.bark(event, true)
