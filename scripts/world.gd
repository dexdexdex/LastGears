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
var near := PackedByteArray()         # 1 = solid or touching solid (needs real collision)
var buildings: Array = []             # Array[Rect2i] in cells
var walls: Array = []                 # Array[Rect2i] settlement walls
var plazas: Array = []               # [center px, radius px] open ground, no buildings
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
var flow_timer := 0.0
const FLOW_MAX := 80
const FLOW_INF := 1 << 28

var map_texture: ImageTexture


var from_name := "Outpost Gravel"
var to_name := "Haven-7"


func generate(seed_value: int, p_from: String = "Outpost Gravel", p_to: String = "Haven-7", p_dir: Vector2 = Vector2.RIGHT) -> void:
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

	# Plazas: open squares/rubble fields so the city isn't wall-to-wall blocks.
	plazas.clear()
	for i in area / 2000:
		var pc := Vector2(rng.randf_range(12, W - 12), rng.randf_range(12, H - 12)) * CELL
		plazas.append([pc, rng.randf_range(4.0, 8.5) * CELL])

	# Buildings: random rects with a 2-cell gutter so heavy mechs fit between.
	var tries := 0
	while tries < area / 7 and buildings.size() < area / 85:
		tries += 1
		var bw := rng.randi_range(2, 7)
		var bh := rng.randi_range(2, 6)
		var bx := rng.randi_range(2, W - bw - 3)
		var by := rng.randi_range(2, H - bh - 3)
		var r := Rect2i(bx, by, bw, bh)
		if _rect_ok(r, sa, sb):
			buildings.append(r)
			for cx in range(r.position.x, r.end.x):
				for cy in range(r.position.y, r.end.y):
					_set_solid(cx, cy)

	# Ground dressing.
	specks.clear()
	for i in int(area * 0.3):
		specks.append([Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL),
			rng.randf_range(1.0, 3.5), rng.randf_range(-0.05, 0.06)])
	craters.clear()
	for i in area / 150:
		var p := Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL)
		if not is_solid_at(p):
			craters.append([p, rng.randf_range(10, 40)])

	# Cache spots: free cells away from the start, biased toward building edges.
	cache_spots.clear()
	tries = 0
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
	for x in W:
		for y in H:
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
		flow_build = tmp
		flow_building = false


func update_flow(sources: Array) -> void:
	## Synchronous rebuild (used only where a full field is needed at once).
	start_flow(sources)
	step_flow(1 << 30)


func flow_dir(p: Vector2) -> Vector2:
	var c := to_cell(p)
	if c.x <= 0 or c.y <= 0 or c.x >= W - 1 or c.y >= H - 1 or flow.size() != W * H:
		return Vector2.ZERO
	var i := c.y * W + c.x
	var best := flow[i]
	var dir := Vector2.ZERO
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var nx: int = c.x + dx
			var ny: int = c.y + dy
			if dx != 0 and dy != 0 and (is_solid(c.x + dx, c.y) or is_solid(c.x, c.y + dy)):
				continue
			var v := flow[ny * W + nx]
			if v < best:
				best = v
				dir = (cell_center(Vector2i(nx, ny)) - p)
	return dir.normalized()


# ---------------------------------------------------------------- drawing

const COL_GROUND := Color(0.15, 0.16, 0.13)
const COL_BLDG := Color(0.085, 0.09, 0.085)
const COL_ROOF := Color(0.12, 0.125, 0.115)
const COL_EDGE := Color(0.30, 0.31, 0.27)
const COL_WALL := Color(0.42, 0.28, 0.18)


# The city is drawn in chunks so the renderer culls everything off screen.
const CHUNK := 600.0


class Chunk extends Node2D:
	var world: World
	var rect: Rect2

	func _draw() -> void:
		world.draw_chunk(self, rect)


func _build_chunks() -> void:
	for c in get_children():
		if c is Chunk:
			c.queue_free()
	var sz := size_px()
	var nx := int(ceil(sz.x / CHUNK))
	var ny := int(ceil(sz.y / CHUNK))
	for cy in ny:
		for cx in nx:
			var ch := Chunk.new()
			ch.world = self
			ch.rect = Rect2(Vector2(cx, cy) * CHUNK, Vector2(CHUNK, CHUNK)).intersection(Rect2(Vector2.ZERO, sz))
			add_child(ch)


func draw_chunk(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, COL_GROUND)
	for sp in specks:
		if rect.has_point(sp[0]):
			var c := COL_GROUND.lightened(sp[2]) if sp[2] > 0 else COL_GROUND.darkened(-sp[2])
			ci.draw_rect(Rect2(sp[0], Vector2(sp[1], sp[1])), c)
	for cr in craters:
		if rect.has_point(cr[0]):
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
		if not rect.has_point(pl[0]):
			continue
		ci.draw_circle(pl[0], pl[1] * 0.85, Color(0.17, 0.17, 0.14, 0.5))
		var pr := RandomNumberGenerator.new()
		pr.seed = int(pl[0].x * 31 + pl[0].y)
		for k in 10:
			var rp: Vector2 = pl[0] + Vector2.from_angle(pr.randf() * TAU) * pr.randf() * pl[1] * 0.8
			ci.draw_rect(Rect2(rp, Vector2(pr.randf_range(3, 9), pr.randf_range(3, 7))), COL_EDGE.darkened(0.45))
	# buildings (owned by the chunk containing their top-left corner)
	for r in buildings:
		var rp := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		if not rect.has_point(rp.position):
			continue
		ci.draw_rect(rp.grow(3), Color(0, 0, 0, 0.35))
		ci.draw_rect(rp, COL_BLDG)
		ci.draw_rect(rp.grow(-5), COL_ROOF)
		ci.draw_rect(rp, COL_EDGE, false, 1.5)
		var hv := int(r.position.x * 7 + r.position.y * 13)
		if hv % 3 == 0:
			ci.draw_rect(Rect2(rp.position + Vector2(8, 8), Vector2(10, 6)), COL_EDGE.darkened(0.3))
		if hv % 4 == 1:
			ci.draw_line(rp.position + Vector2(6, rp.size.y - 6), rp.position + Vector2(rp.size.x - 6, 6), COL_BLDG, 3.0)
	# settlement walls and lights
	for wr in walls:
		for x in range(wr.position.x, wr.end.x):
			for y in range(wr.position.y, wr.end.y):
				var cp := Vector2(x, y) * CELL
				if is_solid(x, y) and rect.has_point(cp):
					ci.draw_rect(Rect2(cp, Vector2(CELL, CELL)), COL_WALL.darkened(0.35))
					ci.draw_rect(Rect2(cp, Vector2(CELL, CELL)).grow(-4), COL_WALL)
	var font := ThemeDB.fallback_font
	if rect.has_point(start_zone.position):
		_draw_settlement(ci, start_zone, "%s — DEPARTED" % from_name.to_upper(), Color(0.7, 0.8, 0.6), font)
	if rect.has_point(goal_zone.position):
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
	map_texture = ImageTexture.create_from_image(img)
