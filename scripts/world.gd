class_name World
extends Node2D
## Tile grid of the ruined zone between two human settlements.
## Handles generation, drawing, collision, line of sight and pathing
## (A* for the squad, a BFS flow field for the swarm).

const CELL := 24
var W := 230
var H := 100
var dir := Vector2.RIGHT              # travel direction (matches the region map)
var start_c := Vector2.ZERO           # px, centre of departure compound
var goal_c := Vector2.ZERO            # px, centre of destination compound

var blocked := PackedByteArray()      # 1 = solid (building / wall / border)
var nmask := PackedByteArray()        # per cell: which of the 8 neighbours are solid (bits, see NMASK_OFS)
const NMASK_OFS := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
var near := PackedByteArray()         # 1 = solid or touching solid (needs real collision)
var buildings: Array = []             # Array[Rect2i] in cells
var walls: Array = []                 # Array[Rect2i] settlement walls
var plazas: Array = []               # [center px, radius px] open ground, no buildings
var bkind: Array = []                 # parallel to buildings: draw style per rect
var rounds: Array = []                # [center px, radius px, kind] round solids (tanks, trees)
var water := PackedByteArray()        # 1 = shallow water (slows mechs)
var biome := "dead city"
var lamps: Array = []                 # [pos px, radius px, color, flicker 0..1] ambient light sources
var pal := {}

const BIOMES := {
	"dead city": {"ambient": Color(0.045, 0.05, 0.055), "lamp": Color(0.75, 0.82, 0.95), "lamps": 2600, "ground": Color(0.15, 0.16, 0.13), "bldg": Color(0.085, 0.09, 0.085), "roof": Color(0.12, 0.125, 0.115), "edge": Color(0.30, 0.31, 0.27), "specks": 0.3, "craters": 1.0},
	"industrial yards": {"ambient": Color(0.045, 0.042, 0.035), "lamp": Color(1.0, 0.62, 0.25), "lamps": 1500, "ground": Color(0.165, 0.165, 0.155), "bldg": Color(0.09, 0.095, 0.105), "roof": Color(0.15, 0.155, 0.165), "edge": Color(0.40, 0.38, 0.30), "accent": Color(0.62, 0.5, 0.14), "specks": 0.2, "craters": 0.6},
	"flooded district": {"ambient": Color(0.05, 0.075, 0.1), "ground": Color(0.12, 0.145, 0.135), "bldg": Color(0.075, 0.085, 0.085), "roof": Color(0.11, 0.13, 0.13), "edge": Color(0.27, 0.33, 0.32), "water": Color(0.045, 0.09, 0.11), "specks": 0.25, "craters": 0.4},
	"scrap fields": {"ambient": Color(0.05, 0.04, 0.03), "lamp": Color(1.0, 0.45, 0.15), "ground": Color(0.19, 0.16, 0.12), "bldg": Color(0.12, 0.10, 0.08), "roof": Color(0.18, 0.15, 0.11), "edge": Color(0.40, 0.31, 0.22), "accent": Color(0.55, 0.32, 0.16), "specks": 0.4, "craters": 3.0},
	"dead forest": {"ambient": Color(0.025, 0.035, 0.03), "ground": Color(0.105, 0.125, 0.095), "bldg": Color(0.13, 0.11, 0.08), "roof": Color(0.26, 0.23, 0.17), "edge": Color(0.36, 0.38, 0.27), "specks": 0.45, "craters": 0.5},
}
var specks: Array = []                # ground texture [pos, size, shade]
var craters: Array = []               # [pos, r]
var start_zone := Rect2()             # px, settlement A interior
var goal_zone := Rect2()              # px, settlement B interior
var start_pos := Vector2.ZERO
var cache_spots: Array = []           # px positions for supply caches
var rng := RandomNumberGenerator.new()

var astar := AStarGrid2D.new()

# flow field toward the nearest squad mech
var flow := PackedInt32Array()
var flow_cache := PackedByteArray()   # per cell: 0 unknown, 1-8 best neighbour, 9 none
const FLOW_N := [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]
var flow_timer := 0.0
const FLOW_MAX := 80
const FLOW_INF := 1 << 28

var map_texture: ImageTexture


var from_name := "Outpost Gravel"
var to_name := "Haven-7"


func generate(seed_value: int, p_from: String = "Outpost Gravel", p_to: String = "Haven-7", p_dir: Vector2 = Vector2.RIGHT, p_biome: String = "dead city") -> void:
	biome = p_biome if BIOMES.has(p_biome) else "dead city"
	pal = BIOMES[biome]
	from_name = p_from
	to_name = p_to
	rng.seed = seed_value
	dir = p_dir.normalized() if p_dir.length() > 0.01 else Vector2.RIGHT
	# A corridor ~230 cells long, ~100 wide, rotated to the travel direction;
	# the map is its bounding box (diagonal legs get a squarer, bigger city).
	var L := 230.0
	var Wd := 100.0
	var c := absf(dir.x)
	var sn := absf(dir.y)
	W = maxi(110, int(L * c + Wd * sn))
	H = maxi(110, int(L * sn + Wd * c))
	blocked.resize(W * H)
	blocked.fill(0)
	buildings.clear()
	bkind.clear()
	rounds.clear()
	walls.clear()
	for x in W:
		_set_solid(x, 0)
		_set_solid(x, H - 1)
	for y in H:
		_set_solid(0, y)
		_set_solid(W - 1, y)

	# Settlements: walled compounds, gates facing each other.
	var mid := Vector2(W, H) * 0.5
	var half := Vector2(maxf(W * 0.5 - 12.0, 10.0), maxf(H * 0.5 - 12.0, 10.0))
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, half.y / absf(dir.y))
	var a_cell := mid - dir * t
	var b_cell := mid + dir * t
	var gate_a := _side_of(dir)
	var gate_b := _side_of(-dir)
	var sa := _compound_rect(a_cell, gate_a)
	var sb := _compound_rect(b_cell, gate_b)
	_compound(sa, gate_a)
	_compound(sb, gate_b)
	start_zone = Rect2(Vector2(sa.position + Vector2i(1, 1)) * CELL, Vector2(sa.size - Vector2i(2, 2)) * CELL)
	goal_zone = Rect2(Vector2(sb.position + Vector2i(1, 1)) * CELL, Vector2(sb.size - Vector2i(2, 2)) * CELL)
	start_c = start_zone.get_center()
	goal_c = goal_zone.get_center()
	start_pos = start_c + Vector2(gate_a) * CELL * 2.0
	var area := W * H

	water.resize(W * H)
	water.fill(0)
	_gen_biome(sa, sb, area)
	_gen_lamps(area)

	# Ground dressing.
	specks.clear()
	for i in int(area * float(pal.specks)):
		specks.append([Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL),
			rng.randf_range(1.0, 3.5), rng.randf_range(-0.05, 0.06)])
	craters.clear()
	for i in int(area / 150 * float(pal.craters)):
		var p := Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL)
		if not is_solid_at(p):
			craters.append([p, rng.randf_range(10, 40)])

	# Cache spots: free cells away from the start, biased toward building edges.
	cache_spots.clear()
	var tries := 0
	while cache_spots.size() < area / 450 and tries < 12000:
		tries += 1
		var cx := rng.randi_range(4, W - 5)
		var cy := rng.randi_range(4, H - 5)
		if is_solid(cx, cy) or cell_center(Vector2i(cx, cy)).distance_to(start_c) < 18 * CELL:
			continue
		var adj := is_solid(cx + 1, cy) or is_solid(cx - 1, cy) or is_solid(cx, cy + 1) or is_solid(cx, cy - 1)
		if not adj and rng.randf() < 0.75:
			continue
		var p := cell_center(Vector2i(cx, cy))
		var ok := true
		for q in cache_spots:
			if q.distance_to(p) < 220:
				ok = false
				break
		if ok:
			cache_spots.append(p)

	_build_astar()
	_build_map_texture()
	_build_chunks()


# ---------------------------------------------------------------- biomes

func _gen_biome(sa: Rect2i, sb: Rect2i, area: int) -> void:
	plazas.clear()
	match biome:
		"dead city":
			_plazas(area / 2000)
			_rects(area / 85, Vector2i(2, 7), Vector2i(2, 6), "bldg", sa, sb)
		"industrial yards":
			_plazas(area / 3500)
			_rects(area / 260, Vector2i(6, 14), Vector2i(4, 8), "warehouse", sa, sb)
			for i in area / 1100:   # pipe runs
				if rng.randf() < 0.5:
					_rects(1, Vector2i(9, 20), Vector2i(1, 1), "pipe", sa, sb)
				else:
					_rects(1, Vector2i(1, 1), Vector2i(9, 20), "pipe", sa, sb)
			_rounds(area / 650, 1.4, 3.0, "tank", sa, sb)
			_rects(area / 300, Vector2i(2, 3), Vector2i(1, 2), "crate", sa, sb)
		"flooded district":
			for i in area / 900:
				var c := Vector2(rng.randf_range(6, W - 6), rng.randf_range(6, H - 6))
				var rr := rng.randf_range(4.0, 11.0)
				for x in range(int(c.x - rr), int(c.x + rr) + 1):
					for y in range(int(c.y - rr), int(c.y + rr) + 1):
						if x > 0 and y > 0 and x < W - 1 and y < H - 1 and Vector2(x, y).distance_to(c) < rr * rng.randf_range(0.85, 1.0):
							if not sa.grow(2).has_point(Vector2i(x, y)) and not sb.grow(2).has_point(Vector2i(x, y)):
								water[y * W + x] = 1
			_plazas(area / 3000)
			_rects(area / 150, Vector2i(2, 6), Vector2i(2, 5), "bldg", sa, sb)
		"scrap fields":
			_plazas(area / 1600)
			for i in area / 220:   # piles: a hulk with debris around it
				var c := Vector2i(rng.randi_range(4, W - 8), rng.randi_range(4, H - 8))
				if _try_rect(Rect2i(c, Vector2i(rng.randi_range(3, 4), rng.randi_range(2, 3))), "hulk", sa, sb):
					for k in 3:
						var o := c + Vector2i(rng.randi_range(-7, 7), rng.randi_range(-6, 6))
						_try_rect(Rect2i(o, Vector2i(rng.randi_range(1, 2), rng.randi_range(1, 2))), "scrap", sa, sb)
		"dead forest":
			_plazas(area / 1400)
			_rounds(area / 26, 0.55, 1.35, "tree", sa, sb)
			_rects(area / 900, Vector2i(2, 4), Vector2i(2, 3), "bldg", sa, sb)


func _gen_lamps(area: int) -> void:
	lamps.clear()
	if not pal.has("lamp"):
		return
	if biome == "scrap fields":
		# burning wrecks: fires at some of the hulks
		for i in buildings.size():
			if bkind[i] == "hulk" and rng.randf() < 0.45:
				var c := (Vector2(buildings[i].position) + Vector2(buildings[i].size) * 0.5) * CELL
				lamps.append([c, rng.randf_range(150.0, 230.0), pal.lamp, 0.8])
		return
	var n: int = area / int(pal.lamps)
	var tries := 0
	while lamps.size() < n and tries < n * 20:
		tries += 1
		var c2 := cell_center(Vector2i(rng.randi_range(3, W - 4), rng.randi_range(3, H - 4)))
		if is_solid_at(c2) or not near_solid_at_gen(c2):
			continue
		var broken := rng.randf() < 0.35
		lamps.append([c2, rng.randf_range(170.0, 260.0), pal.lamp, 0.9 if broken else 0.08])


func near_solid_at_gen(p: Vector2) -> bool:
	var c := to_cell(p)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if is_solid(c.x + dx, c.y + dy):
				return true
	return false


func _plazas(n: int) -> void:
	for i in n:
		var pc := Vector2(rng.randf_range(12, W - 12), rng.randf_range(12, H - 12)) * CELL
		plazas.append([pc, rng.randf_range(4.0, 8.5) * CELL])


func _rects(n: int, wr: Vector2i, hr: Vector2i, kind: String, sa: Rect2i, sb: Rect2i) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 9 + 20:
		tries += 1
		var bw := rng.randi_range(wr.x, wr.y)
		var bh := rng.randi_range(hr.x, hr.y)
		var r := Rect2i(rng.randi_range(2, W - bw - 3), rng.randi_range(2, H - bh - 3), bw, bh)
		if _try_rect(r, kind, sa, sb):
			placed += 1


func _try_rect(r: Rect2i, kind: String, sa: Rect2i, sb: Rect2i) -> bool:
	if r.position.x < 2 or r.position.y < 2 or r.end.x > W - 2 or r.end.y > H - 2:
		return false
	if not _rect_ok(r, sa, sb):
		return false
	buildings.append(r)
	bkind.append(kind)
	for cx in range(r.position.x, r.end.x):
		for cy in range(r.position.y, r.end.y):
			_set_solid(cx, cy)
			water[cy * W + cx] = 0
	return true


func _rounds(n: int, rmin: float, rmax: float, kind: String, sa: Rect2i, sb: Rect2i) -> void:
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 6 + 20:
		tries += 1
		var rc := rng.randf_range(rmin, rmax)
		var c := Vector2(rng.randf_range(3 + rc, W - 3 - rc), rng.randf_range(3 + rc, H - 3 - rc))
		var bb := Rect2i(int(c.x - rc), int(c.y - rc), int(ceil(rc * 2.0)) + 1, int(ceil(rc * 2.0)) + 1)
		if not _rect_ok(bb, sa, sb):
			continue
		var any := false
		for x in range(bb.position.x, bb.end.x):
			for y in range(bb.position.y, bb.end.y):
				if Vector2(x + 0.5, y + 0.5).distance_to(c) <= rc + 0.25:
					_set_solid(x, y)
					water[y * W + x] = 0
					any = true
		if any:
			buildings.append(bb)       # keeps the 2-cell gutter rule for later props
			bkind.append("_round")
			rounds.append([c * CELL, rc * CELL, kind])
			placed += 1


func in_water(p: Vector2) -> bool:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	if cx < 0 or cy < 0 or cx >= W or cy >= H:
		return false
	return water[cy * W + cx] == 1


func _side_of(d: Vector2) -> Vector2i:
	if absf(d.x) >= absf(d.y):
		return Vector2i(1 if d.x > 0 else -1, 0)
	return Vector2i(0, 1 if d.y > 0 else -1)


func _compound_rect(center: Vector2, gate: Vector2i) -> Rect2i:
	var sz := Vector2i(13, 18) if gate.x != 0 else Vector2i(18, 13)
	var p := Vector2i(int(center.x) - sz.x / 2, int(center.y) - sz.y / 2)
	p.x = clampi(p.x, 2, W - sz.x - 2)
	p.y = clampi(p.y, 2, H - sz.y - 2)
	return Rect2i(p, sz)


func _compound(r: Rect2i, gate: Vector2i) -> void:
	var cc := r.get_center()
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if not edge:
				continue
			var is_gate := false
			if gate.x != 0:
				is_gate = absi(y - cc.y) <= 1 and x == (r.end.x - 1 if gate.x > 0 else r.position.x)
			else:
				is_gate = absi(x - cc.x) <= 1 and y == (r.end.y - 1 if gate.y > 0 else r.position.y)
			if not is_gate:
				_set_solid(x, y)
	walls.append(r)


func _rect_ok(r: Rect2i, sa: Rect2i, sb: Rect2i) -> bool:
	var grown := r.grow(2)
	if grown.intersects(sa.grow(4)) or grown.intersects(sb.grow(4)):
		return false
	for b in buildings:
		if grown.intersects(b):
			return false
	var px := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
	for pl in plazas:
		var nearest := Vector2(clampf(pl[0].x, px.position.x, px.end.x), clampf(pl[0].y, px.position.y, px.end.y))
		if nearest.distance_to(pl[0]) < pl[1]:
			return false
	return true


func _set_solid(x: int, y: int) -> void:
	blocked[y * W + x] = 1


# ---------------------------------------------------------------- queries

func is_solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= W or cy >= H:
		return true
	return blocked[cy * W + cx] == 1


func near_solid_at(p: Vector2) -> bool:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	if cx < 1 or cy < 1 or cx >= W - 1 or cy >= H - 1:
		return true
	return near[cy * W + cx] == 1


func is_solid_at(p: Vector2) -> bool:
	return is_solid(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func circle_hits(p: Vector2, r: float) -> bool:
	var x0 := int(floor((p.x - r) / CELL))
	var x1 := int(floor((p.x + r) / CELL))
	var y0 := int(floor((p.y - r) / CELL))
	var y1 := int(floor((p.y + r) / CELL))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			if is_solid(cx, cy):
				var nx := clampf(p.x, cx * CELL, (cx + 1) * CELL)
				var ny := clampf(p.y, cy * CELL, (cy + 1) * CELL)
				if (Vector2(nx, ny) - p).length_squared() < r * r:
					return true
	return false


func move_small(p: Vector2, motion: Vector2, r: float) -> Vector2:
	## move_circle for the swarm (r < CELL / 2). Most machines brushing a wall
	## aren't walking into it, so try the whole move first (one test); only a
	## blocked move falls back to the axis-separated slide.
	var q := p + motion
	if small_free(q, r):
		return q
	var out := p
	q = Vector2(p.x + motion.x, p.y)
	if small_free(q, r):
		out = q
	q = Vector2(out.x, out.y + motion.y)
	if small_free(q, r):
		out = q
	return out


func small_free(q: Vector2, r: float) -> bool:
	## Is a circle of radius r (< CELL / 2) at q clear of solid cells?
	## One neighbour-mask lookup plus a few compares.
	if q.x < 0.0 or q.y < 0.0:
		return false
	var cx := int(q.x / CELL)
	var cy := int(q.y / CELL)
	if cx >= W or cy >= H:
		return false
	var i := cy * W + cx
	if blocked[i] == 1:
		return false
	var m := nmask[i]
	if m == 0:
		return true
	var fx := q.x - cx * CELL
	var fy := q.y - cy * CELL
	var gx := CELL - fx
	var gy := CELL - fy
	if (m & 1 and fx < r) or (m & 2 and gx < r) or (m & 4 and fy < r) or (m & 8 and gy < r):
		return false
	var r2 := r * r
	return not ((m & 16 and fx * fx + fy * fy < r2) or (m & 32 and gx * gx + fy * fy < r2) \
			or (m & 64 and fx * fx + gy * gy < r2) or (m & 128 and gx * gx + gy * gy < r2))


func move_circle(p: Vector2, motion: Vector2, r: float) -> Vector2:
	## Axis-separated slide against walls.
	var out := p
	var nx := out + Vector2(motion.x, 0)
	if not circle_hits(nx, r):
		out = nx
	var ny := out + Vector2(0, motion.y)
	if not circle_hits(ny, r):
		out = ny
	return out


func ray_dist(o: Vector2, d: Vector2, maxd: float) -> float:
	## Distance from o along unit d to the first solid cell (or maxd).
	var cx := int(floor(o.x / CELL))
	var cy := int(floor(o.y / CELL))
	var sx := 1 if d.x > 0.0 else -1
	var sy := 1 if d.y > 0.0 else -1
	var tdx := absf(CELL / d.x) if absf(d.x) > 1e-6 else INF
	var tdy := absf(CELL / d.y) if absf(d.y) > 1e-6 else INF
	var nx := (cx + (1 if sx > 0 else 0)) * CELL
	var ny := (cy + (1 if sy > 0 else 0)) * CELL
	var tmx := (nx - o.x) / d.x if absf(d.x) > 1e-6 else INF
	var tmy := (ny - o.y) / d.y if absf(d.y) > 1e-6 else INF
	var t := 0.0
	while t < maxd:
		if tmx < tmy:
			t = tmx
			tmx += tdx
			cx += sx
		else:
			t = tmy
			tmy += tdy
			cy += sy
		if cx < 0 or cy < 0 or cx >= W or cy >= H or blocked[cy * W + cx] == 1:
			return minf(t, maxd)
	return maxd


func segment_blocked(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / (CELL * 0.4)) + 1
	for i in range(1, steps + 1):
		if is_solid_at(a.lerp(b, float(i) / steps)):
			return true
	return false


func segment_hit_point(a: Vector2, b: Vector2) -> Vector2:
	var d := a.distance_to(b)
	var steps := int(d / (CELL * 0.25)) + 1
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		if is_solid_at(p):
			return p
	return b


func has_los(a: Vector2, b: Vector2) -> bool:
	return not segment_blocked(a, b)


func nearest_free(p: Vector2) -> Vector2:
	var c := to_cell(p)
	if not is_solid(c.x, c.y):
		return p
	for rad in range(1, 6):
		for dx in range(-rad, rad + 1):
			for dy in range(-rad, rad + 1):
				if not is_solid(c.x + dx, c.y + dy):
					return cell_center(c + Vector2i(dx, dy))
	return p


func size_px() -> Vector2:
	return Vector2(W, H) * CELL


func progress_of(p: Vector2) -> float:
	var v := goal_c - start_c
	return clampf((p - start_c).dot(v) / v.length_squared(), 0.0, 1.0)


func compass(v: Vector2) -> String:
	## Screen/map up is north.
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[int(round(fposmod(v.angle(), TAU) / (TAU / 8.0))) % 8]


# ---------------------------------------------------------------- A* (squad)

func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL * 0.5, CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	near.resize(W * H)
	near.fill(0)
	nmask.resize(W * H)
	nmask.fill(0)
	for x in W:
		for y in H:
			var m := 0
			for b in 8:
				var o: Vector2i = NMASK_OFS[b]
				if is_solid(x + o.x, y + o.y):
					m |= 1 << b
			nmask[y * W + x] = m
			if is_solid(x, y):
				astar.set_point_solid(Vector2i(x, y), true)
				near[y * W + x] = 1
			elif _touches_solid(x, y):
				astar.set_point_weight_scale(Vector2i(x, y), 4.0)
				near[y * W + x] = 1


func _touches_solid(x: int, y: int) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if is_solid(x + dx, y + dy):
				return true
	return false


func find_path(a: Vector2, b: Vector2) -> PackedVector2Array:
	var ca := to_cell(nearest_free(a))
	var cb := to_cell(nearest_free(b))
	if is_solid(ca.x, ca.y) or is_solid(cb.x, cb.y):
		return PackedVector2Array()
	return astar.get_point_path(ca, cb)


# ---------------------------------------------------------------- flow field (swarm)

# The flow field is rebuilt incrementally over several frames (a BFS spread
# across frames) so recomputing it never causes a hitch.
var flow_build := PackedInt32Array()
var fqueue := PackedInt32Array()
var fhead := 0
var ftail := 0
var flow_building := false


func start_flow(sources: Array) -> void:
	if flow_build.size() != W * H:
		flow_build.resize(W * H)
		fqueue.resize(W * H)
	flow_build.fill(FLOW_INF)
	fhead = 0
	ftail = 0
	for s in sources:
		var c := to_cell(s)
		if is_solid(c.x, c.y):
			continue
		var i := c.y * W + c.x
		flow_build[i] = 0
		fqueue[ftail] = i
		ftail += 1
	flow_building = true


func step_flow(budget: int) -> void:
	if not flow_building:
		return
	var done := 0
	while fhead < ftail and done < budget:
		var i := fqueue[fhead]
		fhead += 1
		done += 1
		var d := flow_build[i] + 1
		if d > FLOW_MAX:
			continue
		var n := i - 1
		if blocked[n] == 0 and flow_build[n] > d:
			flow_build[n] = d
			fqueue[ftail] = n
			ftail += 1
		n = i + 1
		if blocked[n] == 0 and flow_build[n] > d:
			flow_build[n] = d
			fqueue[ftail] = n
			ftail += 1
		n = i - W
		if blocked[n] == 0 and flow_build[n] > d:
			flow_build[n] = d
			fqueue[ftail] = n
			ftail += 1
		n = i + W
		if blocked[n] == 0 and flow_build[n] > d:
			flow_build[n] = d
			fqueue[ftail] = n
			ftail += 1
	if fhead >= ftail:
		var tmp := flow
		flow = flow_build
		flow_cache.resize(W * H)
		flow_cache.fill(0)
		flow_build = tmp
		flow_building = false


func update_flow(sources: Array) -> void:
	## Synchronous rebuild (used only where a full field is needed at once).
	start_flow(sources)
	step_flow(1 << 30)


func flow_dir(p: Vector2) -> Vector2:
	## Downhill step on the flow field. The best neighbour of each cell is
	## worked out once per field and cached (thousands of machines ask).
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	if cx <= 0 or cy <= 0 or cx >= W - 1 or cy >= H - 1 or flow.size() != W * H:
		return Vector2.ZERO
	var i := cy * W + cx
	var k := flow_cache[i]
	if k == 0:
		k = 9
		var best := flow[i]
		for j in 8:
			var o: Vector2i = FLOW_N[j]
			if o.x != 0 and o.y != 0 and (blocked[cy * W + cx + o.x] == 1 or blocked[(cy + o.y) * W + cx] == 1):
				continue
			var v := flow[(cy + o.y) * W + cx + o.x]
			if v < best:
				best = v
				k = j + 1
		flow_cache[i] = k
	if k == 9:
		return Vector2.ZERO
	var n: Vector2i = FLOW_N[k - 1]
	return (Vector2((cx + n.x + 0.5) * CELL, (cy + n.y + 0.5) * CELL) - p).normalized()


# ---------------------------------------------------------------- drawing

const COL_WALL := Color(0.42, 0.28, 0.18)


# The zone is drawn in 600 px chunks. Each chunk near the camera is baked
# once into its own texture (rendered by a one-shot SubViewport), so the whole
# visible city costs a handful of draw calls instead of hundreds. Chunks far
# from the camera are released again.
const CHUNK := 600.0
const BAKES_PER_FRAME := 2
var chunks: Array = []


class Chunk extends Node2D:
	var world: World
	var rect: Rect2
	var vp: SubViewport
	var ready_frame := -1

	func _draw() -> void:
		if vp and Engine.get_process_frames() >= ready_frame:
			draw_texture(vp.get_texture(), rect.position)


class Baker extends Node2D:
	var world: World
	var rect: Rect2

	func _draw() -> void:
		world.draw_chunk(self, rect)


func _build_chunks() -> void:
	for c in chunks:
		c.queue_free()
	chunks.clear()
	var sz := size_px()
	var nx := int(ceil(sz.x / CHUNK))
	var ny := int(ceil(sz.y / CHUNK))
	for cy in ny:
		for cx in nx:
			var ch := Chunk.new()
			ch.world = self
			ch.rect = Rect2(Vector2(cx, cy) * CHUNK, Vector2(CHUNK, CHUNK)).intersection(Rect2(Vector2.ZERO, sz))
			add_child(ch)
			chunks.append(ch)


func _bake(ch: Chunk) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(ch.rect.size.x), int(ch.rect.size.y))
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bk := Baker.new()
	bk.world = self
	bk.rect = ch.rect
	bk.position = -ch.rect.position
	vp.add_child(bk)
	ch.add_child(vp)
	ch.vp = vp
	ch.ready_frame = Engine.get_process_frames() + 2


func _process(_delta: float) -> void:
	if G.camera == null or chunks.is_empty():
		return
	var view := G.camera.view_rect()
	var near := view.grow(CHUNK * 0.75)
	var far := view.grow(CHUNK * 2.5)
	var budget := BAKES_PER_FRAME
	var frame := Engine.get_process_frames()
	for ch in chunks:
		if ch.vp == null:
			if budget > 0 and near.intersects(ch.rect):
				_bake(ch)
				budget -= 1
		else:
			if frame == ch.ready_frame:
				ch.queue_redraw()
			elif not far.intersects(ch.rect):
				ch.vp.queue_free()
				ch.vp = null
				ch.queue_redraw()


func draw_chunk(ci: CanvasItem, rect: Rect2) -> void:
	var ground: Color = pal.ground
	ci.draw_rect(rect, ground)
	for sp in specks:
		if rect.has_point(sp[0]):
			var c := ground.lightened(sp[2]) if sp[2] > 0 else ground.darkened(-sp[2])
			ci.draw_rect(Rect2(sp[0], Vector2(sp[1], sp[1])), c)
	for cr in craters:
		if rect.grow(42.0).has_point(cr[0]):
			ci.draw_circle(cr[0], cr[1], Color(0.11, 0.115, 0.1, 0.8))
			ci.draw_arc(cr[0], cr[1], 0, TAU, 24, Color(0.22, 0.22, 0.18, 0.5), 2.0)
	# faint survey grid
	var gc := Color(0.4, 0.5, 0.35, 0.05)
	var step := CELL * 5.0
	var gx := ceilf(rect.position.x / step) * step
	while gx <= rect.end.x:
		ci.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), gc, 1.0)
		gx += step
	var gy := ceilf(rect.position.y / step) * step
	while gy <= rect.end.y:
		ci.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), gc, 1.0)
		gy += step
	# plazas: rubble-strewn open ground
	for pl in plazas:
		if not rect.grow(pl[1]).has_point(pl[0]):
			continue
		ci.draw_circle(pl[0], pl[1] * 0.85, Color(0.17, 0.17, 0.14, 0.5))
		var pr := RandomNumberGenerator.new()
		pr.seed = int(pl[0].x * 31 + pl[0].y)
		for k in 10:
			var rp: Vector2 = pl[0] + Vector2.from_angle(pr.randf() * TAU) * pr.randf() * pl[1] * 0.8
			ci.draw_rect(Rect2(rp, Vector2(pr.randf_range(3, 9), pr.randf_range(3, 7))), Color(pal.edge).darkened(0.45))
	# shallow water
	if pal.has("water"):
		var wc: Color = pal.water
		var c0 := Vector2i(int(rect.position.x / CELL), int(rect.position.y / CELL))
		var c1 := Vector2i(int(ceil(rect.end.x / CELL)), int(ceil(rect.end.y / CELL)))
		for cy in range(maxi(c0.y, 0), mini(c1.y, H)):
			for cx in range(maxi(c0.x, 0), mini(c1.x, W)):
				if water[cy * W + cx] == 1:
					var wp := Vector2(cx, cy) * CELL
					ci.draw_rect(Rect2(wp, Vector2(CELL, CELL)), wc)
					if (cx * 7 + cy * 13) % 5 == 0:
						ci.draw_arc(wp + Vector2(12, 12), 7.0, 0.3, 2.6, 6, Color(0.3, 0.45, 0.5, 0.25), 1.0)
	# rect props (owned by the chunk containing their top-left corner)
	var bl: Color = pal.bldg
	var rf: Color = pal.roof
	var ed: Color = pal.edge
	for i in buildings.size():
		var r: Rect2i = buildings[i]
		var kind: String = bkind[i]
		if kind == "_round":
			continue
		var rp := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		if not rect.intersects(rp.grow(4.0)):
			continue
		var hv := int(r.position.x * 7 + r.position.y * 13)
		match kind:
			"warehouse":
				ci.draw_rect(rp.grow(3), Color(0, 0, 0, 0.35))
				ci.draw_rect(rp, bl)
				ci.draw_rect(rp.grow(-4), rf)
				var ribs := int(rp.size.x / 18.0)
				for k in range(1, ribs):
					ci.draw_line(rp.position + Vector2(k * 18.0, 4), rp.position + Vector2(k * 18.0, rp.size.y - 4), bl.lightened(0.05), 1.0)
				ci.draw_rect(rp, ed, false, 1.5)
				ci.draw_rect(Rect2(rp.position + Vector2(0, rp.size.y - 5), Vector2(rp.size.x, 5)), Color(pal.accent, 0.5))
			"pipe":
				ci.draw_rect(rp.grow(2), Color(0, 0, 0, 0.3))
				ci.draw_rect(rp.grow(-3), ed.darkened(0.2))
				var horiz := rp.size.x > rp.size.y
				var n := int((rp.size.x if horiz else rp.size.y) / 48.0)
				for k in range(1, n + 1):
					var off := k * 48.0
					if horiz:
						ci.draw_rect(Rect2(rp.position + Vector2(off - 3, 1), Vector2(6, rp.size.y - 2)), ed)
					else:
						ci.draw_rect(Rect2(rp.position + Vector2(1, off - 3), Vector2(rp.size.x - 2, 6)), ed)
			"crate":
				ci.draw_rect(rp.grow(-2), Color(pal.accent).darkened(0.45))
				ci.draw_rect(rp.grow(-2), Color(pal.accent).darkened(0.1), false, 1.0)
			"hulk":
				var c := rp.get_center()
				var pts := PackedVector2Array()
				var hr := RandomNumberGenerator.new()
				hr.seed = hv
				for k in 7:
					var a := TAU * k / 7.0
					pts.append(c + Vector2(cos(a) * rp.size.x * 0.5, sin(a) * rp.size.y * 0.5) * hr.randf_range(0.75, 1.0))
				ci.draw_colored_polygon(pts, bl)
				pts.append(pts[0])
				ci.draw_polyline(pts, ed, 1.5)
				ci.draw_line(c - Vector2(rp.size.x * 0.3, 0), c + Vector2(rp.size.x * 0.45, -rp.size.y * 0.2), Color(pal.accent, 0.6), 3.0)
			"scrap":
				ci.draw_rect(rp.grow(-3), bl.lightened(0.05))
				ci.draw_line(rp.position + Vector2(3, 3), rp.end - Vector2(3, 3), Color(pal.accent, 0.5), 2.0)
			_:
				ci.draw_rect(rp.grow(3), Color(0, 0, 0, 0.35))
				ci.draw_rect(rp, bl)
				ci.draw_rect(rp.grow(-5), rf)
				ci.draw_rect(rp, ed, false, 1.5)
				if hv % 3 == 0:
					ci.draw_rect(Rect2(rp.position + Vector2(8, 8), Vector2(10, 6)), ed.darkened(0.3))
				if hv % 4 == 1:
					ci.draw_line(rp.position + Vector2(6, rp.size.y - 6), rp.position + Vector2(rp.size.x - 6, 6), bl, 3.0)
	# round props
	for rd in rounds:
		var c2: Vector2 = rd[0]
		var rr: float = rd[1]
		if not rect.grow(rr * 1.7).has_point(c2):
			continue
		match rd[2]:
			"tank":
				ci.draw_circle(c2 + Vector2(3, 4), rr + 2, Color(0, 0, 0, 0.35))
				ci.draw_circle(c2, rr, bl)
				ci.draw_arc(c2, rr, 0, TAU, 32, ed, 1.5)
				ci.draw_arc(c2, rr * 0.62, 0, TAU, 28, rf, 2.0)
				ci.draw_circle(c2, 3.0, Color(pal.accent, 0.7))
			"tree":
				var tr := RandomNumberGenerator.new()
				tr.seed = int(c2.x * 13 + c2.y)
				ci.draw_circle(c2 + Vector2(2, 3), rr * 0.8, Color(0, 0, 0, 0.3))
				for k in 7:
					var a2 := tr.randf() * TAU
					var len := rr * tr.randf_range(0.9, 1.6)
					var mid := c2 + Vector2.from_angle(a2) * len * 0.55
					var tip := mid + Vector2.from_angle(a2 + tr.randf_range(-0.5, 0.5)) * len * 0.5
					ci.draw_polyline(PackedVector2Array([c2, mid, tip]), Color(pal.roof).lightened(0.05), 1.5, true)
				ci.draw_circle(c2, rr * 0.42, pal.bldg)
				ci.draw_arc(c2, rr * 0.42, 0, TAU, 14, ed, 1.0, true)
	# settlement walls and lights
	for wr in walls:
		for x in range(wr.position.x, wr.end.x):
			for y in range(wr.position.y, wr.end.y):
				var cp := Vector2(x, y) * CELL
				if is_solid(x, y) and rect.intersects(Rect2(cp, Vector2(CELL, CELL))):
					ci.draw_rect(Rect2(cp, Vector2(CELL, CELL)), COL_WALL.darkened(0.35))
					ci.draw_rect(Rect2(cp, Vector2(CELL, CELL)).grow(-4), COL_WALL)
	var font := ThemeDB.fallback_font
	if rect.intersects(start_zone.grow(30.0)):
		_draw_settlement(ci, start_zone, "%s — DEPARTED" % from_name.to_upper(), Color(0.7, 0.8, 0.6), font)
	if rect.intersects(goal_zone.grow(30.0)):
		_draw_settlement(ci, goal_zone, "%s — DESTINATION" % to_name.to_upper(), Color(1.0, 0.82, 0.45), font)


func _draw_settlement(ci: CanvasItem, z: Rect2, label: String, col: Color, font: Font) -> void:
	ci.draw_rect(z, Color(col, 0.06))
	var r := RandomNumberGenerator.new()
	r.seed = int(z.position.x)
	for i in 14:
		var p := z.position + Vector2(r.randf() * z.size.x, r.randf() * z.size.y)
		ci.draw_rect(Rect2(p, Vector2(r.randf_range(14, 40), r.randf_range(10, 30))), Color(0.18, 0.17, 0.14))
		ci.draw_circle(p + Vector2(4, 4), 2.5, Color(1.0, 0.75, 0.35, 0.9))
	ci.draw_string(font, z.position + Vector2(4, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _build_map_texture() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.14, 0.11, 0.92))
	for x in W:
		for y in H:
			if is_solid(x, y):
				img.set_pixel(x, y, Color(0.4, 0.45, 0.36))
			elif water[y * W + x] == 1:
				img.set_pixel(x, y, Color(0.12, 0.22, 0.28))
	map_texture = ImageTexture.create_from_image(img)
