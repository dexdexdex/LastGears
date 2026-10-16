class_name EnemyManager
extends Node2D
## The machine swarm. Hundreds of tiny dots simulated and drawn in one node.

const TYPES := {
	# The bulk of the swarm. Slow, fragile, endless.
	"crawler": {
		"name": "Crawler", "hp": 12.0, "speed": 36.0, "r": 3.0, "armor": 0.0,
		"color": Color(0.78, 0.3, 0.24), "melee": 6.0, "melee_cd": 0.9, "drop": 0.015,
	},
	# Medium-pace biters.
	"skitter": {
		"name": "Skitter", "hp": 16.0, "speed": 88.0, "r": 3.0, "armor": 0.0,
		"color": Color(0.95, 0.28, 0.22), "melee": 7.0, "melee_cd": 0.6, "drop": 0.04,
	},
	# Ranged. Keeps its distance and lobs slow bolts.
	"spitter": {
		"name": "Spitter", "hp": 34.0, "speed": 52.0, "r": 4.0, "armor": 0.0,
		"color": Color(1.0, 0.62, 0.15), "ranged": true, "shot_dmg": 9.0, "shot_cd": 1.9,
		"keep": 250.0, "shot_speed": 270.0, "drop": 0.06,
	},
	# Suicide runner. Explodes on contact or death (and chains).
	"tick": {
		"name": "Tick", "hp": 16.0, "speed": 168.0, "r": 3.5, "armor": 0.0,
		"color": Color(1.0, 0.95, 0.35), "bomb": true, "bomb_dmg": 42.0, "bomb_r": 70.0, "drop": 0.04,
	},
	# Armoured brute. Shrugs off small rounds; slams.
	"warden": {
		"name": "Warden", "hp": 380.0, "speed": 44.0, "r": 8.0, "armor": 5.0,
		"color": Color(0.85, 0.35, 0.98), "melee": 34.0, "melee_cd": 1.4, "drop": 1.0,
	},
}

class Enemy:
	var type := ""
	var d := {}
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var r := 3.0
	var cd := 0.0
	var los_t := 0.0
	var los := false
	var target: Mech
	var alive := true
	var flash := 0.0
	var t := 0.0
	var jitter := 1.0
	var strafe := 1.0
	var awake := true          # dormant swarm fields idle until something comes close
	var wander := Vector2.ZERO
	var want := Vector2.ZERO   # desired velocity, set by the (time-sliced) think step
	var mdt := 0.0             # off-screen: movement time banked for the next step
	var next_think := 0.0      # game time of the next decision (sooner the closer it is)
	var last_think := 0.0
	var seen := false          # inside some squad mech's vision cone right now
	var seen_t := -99.0
	var bi := -1               # bucket this machine is filed in (-1 = none)
	var pack = null            # Pack it moves with (null = thinks for itself)

# Packs: crawlers and skitters away from the squad are run as groups. Every
# machine in the same grid cell shares one decision (target, line of sight,
# think timing); cells are bigger the further out they are, so the far swarm
# is a few big blobs and the near swarm many small ones. Close to the squad
# machines break off and think for themselves.
class Pack:
	var key := Vector3i.ZERO
	var members: Array = []
	var center := Vector2.ZERO
	var radius := 0.0
	var target: Mech
	var los := false
	var los_t := 0.0
	var dist := 0.0
	var next_think := 0.0
	var last_think := 0.0
	var dir := Vector2.ZERO    # shared heading for big (far) packs

const PACKABLE := {"crawler": true, "skitter": true}
const PACK_SOLO := 300.0   # closer than this to the squad: individual
var packs := {}            # Vector3i(cell x, cell y, size) -> Pack
var pack_list: Array = []
var pack_cursor := 0
var squad_c := Vector2.ZERO
var pack_thinks := 0       # stats: pack decisions last frame

const WAKE_R := 300.0
const SEP_OX := [0, -1, 1, 0, 0, -1, 1, -1, 1]   # own bucket first
const SEP_OY := [0, 0, 0, -1, 1, -1, -1, 1, 1]

var list: Array = []       # awake machines: simulated every frame
var sleepers: Array = []   # dormant field machines: never move, cost nothing until woken
var sgrid := {}            # Vector2i bucket -> Array of sleepers (built once, sparse)
var sleepers_dirty := false
var bucket_t := 0.0
var on_list: Array = []    # awake machines on screen this frame (filled by the move pass)
var _seen_sl: Array = []
var wake_t := 0.0
const BUCKET := 48.0
const THINK_HZ := 10.0     # slice rate (off-screen movement steps + think checks)
# Think interval grows with distance to the nearest mech: 0.1 s up close,
# 1 s at 1100 px and beyond. Far machines just trudge toward the squad on
# their last decision and get sharper as they close in.
const THINK_MIN := 0.1
const THINK_MAX := 1.0
const THINK_FAR := 1100.0
var thinks_frame := 0      # stats: decisions made last frame
var budget_hits := 0       # stats: frames where the budget ran out
var budget_used_ms := 0.0
var bw := 0
var bh := 0
var grid: Array = []       # flat bucket grid of Arrays
var think_slice := 0
var deaths := 0
var flow_timer := 0.0
var vis_t := 0.0


func spawn(type: String, pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.type = type
	e.d = TYPES[type]
	e.pos = pos
	var legs: int = G.campaign.legs if G.campaign else 0
	e.hp = e.d.hp * (1.0 + G.world.progress_of(pos) * 0.4) * (1.0 + legs * 0.08)
	e.max_hp = e.hp
	e.r = e.d.r
	e.jitter = randf_range(0.85, 1.15)
	e.strafe = 1.0 if randf() < 0.5 else -1.0
	e.t = randf() * 10.0
	e.los_t = randf() * 0.4
	e.last_think = G.game_time
	list.append(e)
	return e


func _process(delta: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_process_body(delta)
	G.pe("enemies sim", _t0)


func _process_body(delta: float) -> void:
	if G.game_state != "play":
		return
	delta = minf(delta, 0.05)
	flow_timer -= delta
	var tf := Time.get_ticks_usec()
	if flow_timer <= 0.0 and not G.world.flow_building:
		flow_timer = 0.4
		var srcs: Array = []
		for m in G.squad:
			if m.alive:
				srcs.append(m.position)
		G.world.start_flow(srcs)
	G.world.step_flow(2500)
	G.pe(" · flow field", tf)
	var tb := Time.get_ticks_usec()
	bucket_t -= delta
	if bucket_t <= 0.0 or bw == 0:
		bucket_t = 1.0 / 30.0
		_rebuild_buckets()       # machines move < 6 px per 1/30 s; 48 px buckets stay valid
	G.pe(" · buckets", tb)
	var alive_mechs := G.alive_squad()
	if alive_mechs.is_empty():
		return
	wake_t -= delta
	if wake_t <= 0.0 and not sleepers.is_empty():
		wake_t = 0.2
		for m in alive_mechs:
			for o in query_sleepers(m.position, WAKE_R):
				if not o.awake:
					wake_around(o.pos, 140.0)
	if sleepers_dirty:
		sleepers_dirty = false
		sleepers = sleepers.filter(func(x): return x.alive and not x.awake)
	vis_t -= delta
	if vis_t <= 0.0:
		vis_t = 0.12
		_update_visibility(alive_mechs)
	# Time-sliced thinking: each frame only 1/k of the swarm re-decides.
	var k := maxi(1, int(round(1.0 / maxf(delta, 0.001) / THINK_HZ)))
	think_slice = (think_slice + 1) % k
	var think_dt := delta * k
	var n := list.size()
	var tt := Time.get_ticks_usec()
	var onscreen := G.camera.view_rect().grow(120.0) if G.camera else Rect2(-1e9, -1e9, 2e9, 2e9)
	# Thinking runs on a hard per-frame time budget (G.think_budget_ms).
	# Nearest first: machines on screen (around the squad) that are due get
	# their turn before anyone else; then the slice. Whoever misses out keeps
	# walking on its last decision and is simply a little slower to react.
	var now := G.game_time
	var t_end := tt + int(G.think_budget_ms * 1000.0)
	var over := false
	var cnt := 0
	squad_c = Vector2.ZERO
	for m in alive_mechs:
		squad_c += m.position
	squad_c /= alive_mechs.size()
	for e in on_list:
		if e.alive and e.pack == null and now >= e.next_think:
			_think_now(e, now, alive_mechs)
			cnt += 1
			if (cnt & 7) == 0 and Time.get_ticks_usec() > t_end:
				over = true
				break
	# The slice: 1/k of the swarm is visited each frame. Due machines think
	# (budget permitting); off-screen ones take their k-frame movement step.
	for i in range(think_slice, n, k):
		var e: Enemy = list[i]
		if not e.alive:
			continue
		if PACKABLE.has(e.type):
			_assign_pack(e)
			if e.pack != null:
				_pack_want(e, e.pack)
		if e.pack == null and not over and now >= e.next_think:
			_think_now(e, now, alive_mechs)
			cnt += 1
			if (cnt & 7) == 0 and Time.get_ticks_usec() > t_end:
				over = true
			if not e.alive:
				continue
		if not onscreen.has_point(e.pos):
			_move(e, think_dt)
	# Packs: one decision steers every member. Shares the same budget.
	var pc := 0
	var np := pack_list.size()
	var visited := 0
	while visited < np and not over:
		pack_cursor = (pack_cursor + 1) % pack_list.size()
		var pk: Pack = pack_list[pack_cursor]
		visited += 1
		if pk.members.is_empty():
			_drop_pack(pk)
			np -= 1
			if pack_list.is_empty():
				break
			continue
		if now < pk.next_think:
			continue
		_think_pack(pk, now, alive_mechs, onscreen)
		pc += 1
		cnt += 1
		if Time.get_ticks_usec() > t_end:
			over = true
	pack_thinks = pc
	thinks_frame = cnt
	if over:
		budget_hits += 1
	G.pe(" · pass1", tt)
	var t2 := Time.get_ticks_usec()
	# Pass 2: what's on screen moves every frame (found through the buckets).
	# Above ~90 fps each visible machine steps every other frame with 2x dt:
	# sub-pixel per step at these speeds, half the work at 120 Hz.
	var halve := delta < 1.0 / 90.0
	var par := Engine.get_process_frames() & 1
	var sdt := delta * 2.0 if halve else delta
	var lerp_k := clampf(5.0 * sdt, 0.0, 1.0)
	var world: World = G.world
	var near: PackedByteArray = world.near
	var ww: int = world.W
	var hh: int = world.H
	var inv_cell := 1.0 / World.CELL
	on_list.clear()
	if bw > 0:
		var x0 := maxi(0, int(onscreen.position.x / BUCKET))
		var x1 := mini(bw - 1, int(onscreen.end.x / BUCKET))
		var y0 := maxi(0, int(onscreen.position.y / BUCKET))
		var y1 := mini(bh - 1, int(onscreen.end.y / BUCKET))
		for y in range(y0, y1 + 1):
			var row := y * bw
			for x in range(x0, x1 + 1):
				for e in grid[row + x]:
					if not e.alive or not onscreen.has_point(e.pos):
						continue
					on_list.append(e)
					if halve and ((e.bi & 1) ^ par) == 1:
						continue
					# inlined _move (this runs for every visible machine every frame)
					if e.flash > 0.0:
						e.flash = maxf(0.0, e.flash - sdt * 6.0)
					var v: Vector2 = e.vel.lerp(e.want, lerp_k)
					e.vel = v
					var step: Vector2 = v * sdt
					if step.length_squared() < 0.0004:
						if e.want == Vector2.ZERO:
							e.vel = Vector2.ZERO
						continue
					var cx := int(e.pos.x * inv_cell)
					var cy := int(e.pos.y * inv_cell)
					if cx < 1 or cy < 1 or cx >= ww - 1 or cy >= hh - 1 or near[cy * ww + cx] == 1:
						e.pos = world.move_small(e.pos, step, e.r)
					else:
						e.pos += step
	G.pe(" · pass2", t2)
	G.pe(" · think+move", tt)
	# compact the dead out now and then (every loop skips them meanwhile)
	if deaths > 0 and (deaths > 60 or Engine.get_process_frames() % 30 == 0):
		deaths = 0
		list = list.filter(func(x): return x.alive)
	queue_redraw()


func _assign_pack(e: Enemy) -> void:
	## Called from the slice pass: file the machine in the pack for its cell,
	## or let it go solo when it is close to the squad.
	var dc := e.pos.distance_to(squad_c)
	if dc < PACK_SOLO:
		if e.pack != null:
			_leave_pack(e)
			e.next_think = 0.0
		return
	var size := 64 if dc < 600.0 else (128 if dc < 1100.0 else 256)
	var key := Vector3i(int(e.pos.x / size), int(e.pos.y / size), size)
	if e.pack != null and e.pack.key == key:
		return
	if e.pack != null:
		_leave_pack(e)
	var pk: Pack = packs.get(key)
	if pk == null:
		pk = Pack.new()
		pk.key = key
		pk.center = e.pos
		pk.last_think = G.game_time
		packs[key] = pk
		pack_list.append(pk)
	pk.members.append(e)
	e.pack = pk


func _leave_pack(e: Enemy) -> void:
	var pk: Pack = e.pack
	e.pack = null
	if pk != null:
		pk.members.erase(e)


func _drop_pack(pk: Pack) -> void:
	packs.erase(pk.key)
	pack_list.erase(pk)


func _think_pack(pk: Pack, now: float, mechs: Array, _onscreen: Rect2) -> void:
	## One decision for the whole pack, constant cost however big it is:
	## target, line of sight and heading are taken from the cell centre.
	pk.last_think = now
	var c := Vector2((pk.key.x + 0.5) * pk.key.z, (pk.key.y + 0.5) * pk.key.z)
	pk.center = c
	pk.radius = pk.key.z * 0.6
	var best: Mech = null
	var bd := INF
	for m in mechs:
		var dd: float = c.distance_squared_to(m.position)
		if dd < bd:
			bd = dd
			best = m
	pk.target = best
	pk.dist = sqrt(bd)
	if now >= pk.los_t:
		pk.los_t = now + 0.35
		pk.los = pk.dist < 420.0 and G.world.has_los(c, best.position)
	var d := (best.position - c).normalized() if pk.los else G.world.flow_dir(c)
	pk.dir = d if d != Vector2.ZERO else (best.position - c).normalized()
	pk.next_think = now + clampf(pk.dist / THINK_FAR, THINK_MIN, THINK_MAX) * randf_range(0.9, 1.1)


func _pack_want(e: Enemy, pk: Pack) -> void:
	## A member applies its pack's decision (cheap; done on its slice visit).
	e.target = pk.target
	e.los = pk.los
	var desired: Vector2 = pk.dir
	if pk.key.z == 64 and pk.target != null:
		# small packs near the fight still steer around corners individually
		desired = (pk.target.position - e.pos).normalized() if pk.los else G.world.flow_dir(e.pos)
		if desired == Vector2.ZERO:
			desired = pk.dir
	e.want = desired * (e.d.speed * e.jitter)


func _separation(e: Enemy) -> Vector2:
	var sep := Vector2.ZERO
	var checked := 0
	var bx := int(e.pos.x / BUCKET)
	var by := int(e.pos.y / BUCKET)
	for q in 9:
		var gx: int = bx + SEP_OX[q]
		var gy: int = by + SEP_OY[q]
		if gx < 0 or gy < 0 or gx >= bw or gy >= bh:
			continue
		for o in grid[gy * bw + gx]:
			if o == e:
				continue
			var dv: Vector2 = e.pos - o.pos
			var md: float = e.r + o.r + 3.0
			var l2 := dv.length_squared()
			if l2 < md * md and l2 > 0.0001:
				var l := sqrt(l2)
				sep += dv / l * (md - l) / md
			checked += 1
			if checked > 8:
				return sep
	return sep


func _move(e: Enemy, delta: float) -> void:
	e.flash = maxf(0.0, e.flash - delta * 6.0)
	e.vel = e.vel.lerp(e.want, clampf(5.0 * delta, 0, 1))
	var step := e.vel * delta
	if step.length_squared() < 0.0004:
		if e.want == Vector2.ZERO:
			e.vel = Vector2.ZERO
		return
	if G.world.near_solid_at(e.pos):
		e.pos = G.world.move_small(e.pos, step, e.r)
	else:
		e.pos += step


func _think_now(e: Enemy, now: float, mechs: Array) -> void:
	var dt := clampf(now - e.last_think, 0.0, 1.5)
	e.last_think = now
	e.next_think = now + THINK_MAX     # _think shortens this by distance
	_think(e, dt, mechs)


func _think(e: Enemy, delta: float, mechs: Array) -> void:
	e.t += delta
	e.cd -= delta
	if not e.awake:
		e.los_t -= delta
		if e.los_t <= 0.0:
			e.los_t = 0.5
			for m in mechs:
				if e.pos.distance_squared_to(m.position) < WAKE_R * WAKE_R:
					wake_around(e.pos, 140.0)
					break
			# mostly still; the odd shuffle
			e.wander = Vector2.from_angle(randf() * TAU) * 6.0 if randf() < 0.08 else Vector2.ZERO
		e.want = e.wander
		if e.want == Vector2.ZERO and e.vel.length_squared() < 0.5:
			e.vel = Vector2.ZERO
		return
	# nearest mech
	var best: Mech = null
	var bd := INF
	for m in mechs:
		var dd: float = e.pos.distance_squared_to(m.position)
		if dd < bd:
			bd = dd
			best = m
	e.target = best
	var to_t := best.position - e.pos
	var dist := sqrt(bd)
	# Distance LOD: only machines about to touch a mech need quick reflexes.
	e.next_think = e.last_think + clampf(dist / THINK_FAR, THINK_MIN, THINK_MAX) * randf_range(0.9, 1.1)
	e.los_t -= delta
	if e.los_t <= 0.0:
		e.los_t = 0.35
		e.los = dist < 420.0 and G.world.has_los(e.pos, best.position)

	var desired := Vector2.ZERO
	var spd: float = e.d.speed * e.jitter
	if e.los:
		desired = to_t / maxf(dist, 0.01)
	else:
		desired = G.world.flow_dir(e.pos)
		if desired == Vector2.ZERO:
			desired = to_t / maxf(dist, 0.01)

	if e.d.get("ranged", false) and e.los:
		var keep: float = e.d.keep
		if dist < keep - 40.0:
			desired = -to_t.normalized()
		elif dist < keep + 60.0:
			desired = to_t.normalized().orthogonal() * e.strafe * 0.6
			if randf() < 0.005:
				e.strafe *= -1.0
		if dist < keep + 140.0 and e.cd <= 0.0:
			e.cd = e.d.shot_cd * randf_range(0.8, 1.2)
			var lead: Vector2 = best.position + best.vel * (dist / e.d.shot_speed) * 0.6
			G.projectiles.spawn_enemy_bolt(e.pos, (lead - e.pos).normalized(), e.d.shot_dmg, e.d.shot_speed)
	elif e.d.get("bomb", false):
		spd *= 1.0 + 0.4 * clampf(1.0 - dist / 200.0, 0, 1)
		if dist < best.radius + 14.0:
			kill(e, null)
			return
	elif e.d.has("melee") and dist < best.radius + e.r + 4.0:
		desired = Vector2.ZERO
		if e.cd <= 0.0:
			e.cd = e.d.melee_cd
			best.take_damage(e.d.melee, e.pos)
			e.vel = to_t.normalized() * 60.0

	var sep := _separation(e)
	if e.d.has("melee") and desired == Vector2.ZERO:
		e.want = sep * 90.0
	else:
		e.want = (desired * spd) + sep * 90.0


func _rebuild_buckets() -> void:
	## Incremental: only machines that crossed a bucket edge get re-filed.
	if bw == 0:
		bw = int(G.world.W * World.CELL / BUCKET) + 1
		bh = int(G.world.H * World.CELL / BUCKET) + 1
		grid.resize(bw * bh)
		for i in grid.size():
			grid[i] = []
	var inv := 1.0 / BUCKET
	for e in list:
		if not e.alive:
			continue
		var gx := clampi(int(e.pos.x * inv), 0, bw - 1)
		var gy := clampi(int(e.pos.y * inv), 0, bh - 1)
		var idx := gy * bw + gx
		if idx == e.bi:
			continue
		if e.bi >= 0:
			grid[e.bi].erase(e)
		grid[idx].append(e)
		e.bi = idx


func _unfile(e: Enemy) -> void:
	if e.bi >= 0:
		grid[e.bi].erase(e)
		e.bi = -1


func query_radius(p: Vector2, r: float) -> Array:
	var out: Array = []
	if bw == 0:
		return out
	var x0 := maxi(0, int((p.x - r) / BUCKET))
	var x1 := mini(bw - 1, int((p.x + r) / BUCKET))
	var y0 := maxi(0, int((p.y - r) / BUCKET))
	var y1 := mini(bh - 1, int((p.y + r) / BUCKET))
	for y in range(y0, y1 + 1):
		var row := y * bw
		for x in range(x0, x1 + 1):
			for e in grid[row + x]:
				var rr: float = r + e.r
				if e.alive and e.pos.distance_squared_to(p) <= rr * rr:
					out.append(e)
	if not sgrid.is_empty():
		out.append_array(query_sleepers(p, r))
	return out


func query_segment(a: Vector2, b: Vector2, pad: float) -> Array:
	var mid := (a + b) * 0.5
	var near := query_radius(mid, a.distance_to(b) * 0.5 + 12.0)
	var out: Array = []
	for e in near:
		if Geometry2D.get_closest_point_to_segment(e.pos, a, b).distance_to(e.pos) <= e.r + pad:
			out.append(e)
	out.sort_custom(func(x, y): return x.pos.distance_squared_to(a) < y.pos.distance_squared_to(a))
	return out


func count_near(p: Vector2, r: float) -> int:
	## Awake hostiles only: dormant fields don't count as pressure.
	var n := 0
	var r2 := r * r
	if bw == 0:
		return 0
	for y in range(maxi(0, int((p.y - r) / BUCKET)), mini(bh - 1, int((p.y + r) / BUCKET)) + 1):
		var row := y * bw
		for x in range(maxi(0, int((p.x - r) / BUCKET)), mini(bw - 1, int((p.x + r) / BUCKET)) + 1):
			for e in grid[row + x]:
				if e.alive and e.pos.distance_squared_to(p) < r2:
					n += 1
	return n


func _update_visibility(mechs: Array) -> void:
	var _t0 := Time.get_ticks_usec()
	_update_visibility_body(mechs)
	G.pe("enemies vis", _t0)


func _update_visibility_body(mechs: Array) -> void:
	## An enemy is "seen" if it's inside any squad mech's light cone with a
	## clear line of sight (or inside a hull halo). Shared across the squad.
	for e in _seen_sl:
		e.seen = false
	_seen_sl.clear()
	for m in mechs:
		for e in query_radius(m.position, Lighting.VIS_RANGE):
			if e.seen:
				continue
			if Lighting.in_cone(m, e.pos) and (e.pos.distance_squared_to(m.position) < Lighting.HALO * Lighting.HALO or G.world.has_los(m.position, e.pos)):
				e.seen = true
				e.seen_t = G.game_time
				_seen_sl.append(e)


func wake_around(p: Vector2, r: float) -> void:
	for o in query_sleepers(p, r):
		_wake(o)


func _skey(p: Vector2) -> Vector2i:
	return Vector2i(int(p.x / BUCKET), int(p.y / BUCKET))


func _sleep(e: Enemy) -> void:
	e.awake = false
	sleepers.append(e)
	var k := _skey(e.pos)
	if not sgrid.has(k):
		sgrid[k] = []
	sgrid[k].append(e)


func _wake(e: Enemy) -> void:
	if e.awake:
		return
	e.awake = true
	var k := _skey(e.pos)
	if sgrid.has(k):
		sgrid[k].erase(e)
		if sgrid[k].is_empty():
			sgrid.erase(k)
	sleepers_dirty = true
	if e.alive:
		list.append(e)


func query_sleepers(p: Vector2, r: float) -> Array:
	var out: Array = []
	if sgrid.is_empty():
		return out
	var x0 := int((p.x - r) / BUCKET)
	var x1 := int((p.x + r) / BUCKET)
	var y0 := int((p.y - r) / BUCKET)
	var y1 := int((p.y + r) / BUCKET)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell = sgrid.get(Vector2i(x, y))
			if cell == null:
				continue
			for e in cell:
				var rr: float = r + e.r
				if e.alive and e.pos.distance_squared_to(p) <= rr * rr:
					out.append(e)
	return out


func all_count() -> int:
	return list.size() + sleepers.size()


func seed_dormant(count: int, avoid: Vector2, rng: RandomNumberGenerator) -> void:
	## Scatter idle clusters of slow crawlers (with a few skitters) across the zone.
	var placed := 0
	var tries := 0
	while placed < count and tries < 3000:
		tries += 1
		var c := Vector2(rng.randf() * G.world.W, rng.randf() * G.world.H) * World.CELL
		if G.world.is_solid_at(c) or c.distance_to(avoid) < 900.0:
			continue
		var n := rng.randi_range(8, 22)
		for i in n:
			var p := G.world.nearest_free(c + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60)))
			var en := spawn("crawler" if rng.randf() < 0.85 else "skitter", p)
			list.pop_back()
			_sleep(en)
			placed += 1


func damage(e: Enemy, amount: float, by: Mech) -> void:
	if not e.alive:
		return
	var armor: float = e.d.armor
	var dealt := maxf(amount - armor, amount * 0.2)
	if not e.awake:
		wake_around(e.pos, 200.0)
	e.hp -= dealt
	e.flash = 1.0
	if e.hp <= 0.0:
		kill(e, by)


func damage_radius(p: Vector2, r: float, dmg: float) -> void:
	for e in query_radius(p, r):
		var d: float = e.pos.distance_to(p)
		damage(e, dmg * (1.0 - 0.5 * d / r), null)


func kill(e: Enemy, by: Mech) -> void:
	if not e.alive:
		return
	if not e.awake:
		_wake(e)
	e.alive = false
	_unfile(e)
	if e.pack != null:
		_leave_pack(e)
	deaths += 1
	G.kills += 1
	G.leg_kills[e.type] = int(G.leg_kills.get(e.type, 0)) + 1
	if by:
		by.kills += 1
		if by.brain:
			by.brain.on_kill(e)
	if G.director:
		G.director.report_kill()
	G.projectiles.add_fx("puff", e.pos, e.r * 2.5, e.d.color, 0.3)
	G.projectiles.add_fx("shards", e.pos, e.r * 5.0, e.d.color.lightened(0.2), 0.35)
	if e.d.get("bomb", false):
		G.projectiles.explode(e.pos, e.d.bomb_r, e.d.bomb_dmg, 1, true)
	if randf() < e.d.drop:
		var loot := {"scrap": randi_range(1, 3)}
		if e.type == "warden":
			loot = {"scrap": randi_range(4, 7), "circuits": randi_range(1, 3)}
			if randf() < 0.5:
				loot["cells"] = 1
		G.pickups.add_salvage(e.pos, loot)


func count_awake() -> int:
	var n := 0
	for e in list:
		if e.alive and e.awake:
			n += 1
	return n


func alive_count() -> int:
	return list.size() + sleepers.size()


func _draw() -> void:
	var _t0 := Time.get_ticks_usec()
	_draw_body()
	G.pe("enemies draw", _t0)


static var _dot: ImageTexture


static func dot_texture() -> ImageTexture:
	## One shared soft-edged dot, so every machine batches into a single draw.
	if _dot:
		return _dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5 - Vector2(0.5, 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c) / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 6.0, 0.0, 1.0)))
	_dot = ImageTexture.create_from_image(img)
	return _dot


func _draw_body() -> void:
	var tsec := Time.get_ticks_msec() / 1000.0
	var view := G.camera.view_rect().grow(30.0) if G.camera else Rect2(-1e9, -1e9, 2e9, 2e9)
	var dot := dot_texture()
	var specials: Array = []
	# pass 1: every body as a textured dot (one batch)
	for e in on_list:
		if not e.alive or not view.has_point(e.pos):
			continue
		var c: Color = e.d.color
		if e.flash > 0.0:
			c = c.lerp(Color.WHITE, e.flash)
		var r: float = e.r
		match e.type:
			"crawler":
				if not e.awake:
					c = c.darkened(0.35)
			"tick":
				var blink := 0.5 + 0.5 * sin(e.t * (10.0 + 20.0 * float(e.los)))
				c = c.lerp(Color.WHITE, blink * 0.6)
				specials.append(e)
			"warden", "spitter":
				specials.append(e)
				if e.type == "warden":
					continue
		draw_texture_rect(dot, Rect2(e.pos - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
	# sleepers in view (dim, still)
	if not sgrid.is_empty():
		for y in range(int(view.position.y / BUCKET), int(view.end.y / BUCKET) + 1):
			for x in range(int(view.position.x / BUCKET), int(view.end.x / BUCKET) + 1):
				var cell = sgrid.get(Vector2i(x, y))
				if cell == null:
					continue
				for e in cell:
					var rs: float = e.r
					draw_texture_rect(dot, Rect2(e.pos - Vector2(rs, rs), Vector2(rs, rs) * 2.0), false, Color(e.d.color).darkened(0.35))
	# pass 2: the few machines with extra detail
	for e in specials:
		var c2: Color = e.d.color
		match e.type:
			"spitter":
				draw_texture_rect(dot, Rect2(e.pos - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), false, Color(0.15, 0.05, 0.0))
			"tick":
				var blink2 := 0.5 + 0.5 * sin(e.t * (10.0 + 20.0 * float(e.los)))
				draw_arc(e.pos, e.r + 2.0, 0, TAU, 10, Color(1, 0.9, 0.3, 0.4 * blink2), 1.0)
			"warden":
				if e.flash > 0.0:
					c2 = c2.lerp(Color.WHITE, e.flash)
				var a: float = e.vel.angle() if e.vel.length() > 1.0 else 0.0
				var pts := PackedVector2Array()
				for i in 4:
					pts.append(e.pos + Vector2.from_angle(a + TAU * i / 4.0) * e.r * (1.3 if i % 2 == 0 else 0.9))
				draw_colored_polygon(pts, c2.darkened(0.3))
				pts.append(pts[0])
				draw_polyline(pts, c2, 1.5)
				draw_arc(e.pos, e.r + 4.0, -PI / 2, -PI / 2 + TAU * e.hp / e.max_hp, 20, Color(c2, 0.6), 1.5)
				draw_circle(e.pos, 2.0, Color(1, 1, 1, 0.5 + 0.5 * sin(tsec * 6.0)))
	if G.show_packs:
		var font := ThemeDB.fallback_font
		for pk in pack_list:
			if pk.members.size() < 2 or not view.grow(pk.radius).has_point(pk.center):
				continue
			var pcol := Color(1.0, 0.75, 0.3, 0.5) if pk.key.z == 64 else (Color(1.0, 0.45, 0.3, 0.45) if pk.key.z == 128 else Color(0.9, 0.3, 0.6, 0.4))
			draw_arc(pk.center, pk.radius + 5.0, 0, TAU, 28, pcol, 1.0)
			draw_string(font, pk.center + Vector2(pk.radius + 6.0, -pk.radius), str(pk.members.size()), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, pcol)
