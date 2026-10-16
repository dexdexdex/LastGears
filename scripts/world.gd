class_name World
extends Node2D
## Tile grid of the ruined zone between two human settlements.
## Handles generation, drawing, collision, line of sight and pathing
## (A* for the squad, a BFS flow field for the swarm).

const CELL := 24
const W := 300
const H := 96

var blocked := PackedByteArray()      # 1 = solid (building / wall / border)
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


func generate(seed_value: int) -> void:
	rng.seed = seed_value
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

	# Settlements: walled compounds with gates.
	var sa := Rect2i(3, 39, 13, 18)
	var sb := Rect2i(W - 16, 39, 13, 18)
	_compound(sa, true)
	_compound(sb, false)
	start_zone = Rect2(Vector2(sa.position + Vector2i(1, 1)) * CELL, Vector2(sa.size - Vector2i(2, 2)) * CELL)
	goal_zone = Rect2(Vector2(sb.position + Vector2i(1, 1)) * CELL, Vector2(sb.size - Vector2i(2, 2)) * CELL)
	start_pos = start_zone.get_center() + Vector2(CELL * 2, 0)

	# Plazas: open squares/rubble fields so the city isn't wall-to-wall blocks.
	plazas.clear()
	for i in 14:
		var c := Vector2(rng.randf_range(22, W - 22), rng.randf_range(10, H - 10)) * CELL
		plazas.append([c, rng.randf_range(4.0, 8.5) * CELL])

	# Buildings: random rects with a 2-cell gutter so heavy mechs fit between.
	var tries := 0
	while tries < 3200 and buildings.size() < 330:
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
	for i in 9000:
		specks.append([Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL),
			rng.randf_range(1.0, 3.5), rng.randf_range(-0.05, 0.06)])
	craters.clear()
	for i in 190:
		var p := Vector2(rng.randf() * W * CELL, rng.randf() * H * CELL)
		if not is_solid_at(p):
			craters.append([p, rng.randf_range(10, 40)])

	# Cache spots: free cells away from the start, biased toward building edges.
	cache_spots.clear()
	tries = 0
	while cache_spots.size() < 60 and tries < 9000:
		tries += 1
		var cx := rng.randi_range(18, W - 18)
		var cy := rng.randi_range(4, H - 5)
		if is_solid(cx, cy):
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
	queue_redraw()


func _compound(r: Rect2i, gate_east: bool) -> void:
	var cy := r.get_center().y
	for x in range(r.position.x, r.end.x):
		for yy in [r.position.y, r.end.y - 1]:
			_set_solid(x, yy)
	for yy in range(r.position.y, r.end.y):
		for x in [r.position.x, r.end.x - 1]:
			var is_gate: bool = absi(yy - cy) <= 1 and ((x == r.end.x - 1) == gate_east)
			if not is_gate:
				_set_solid(x, yy)
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
	return clampf((p.x - start_zone.end.x) / (goal_zone.position.x - start_zone.end.x), 0.0, 1.0)


# ---------------------------------------------------------------- A* (squad)

func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(CELL, CELL)
	astar.offset = Vector2(CELL * 0.5, CELL * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for x in W:
		for y in H:
			if is_solid(x, y):
				astar.set_point_solid(Vector2i(x, y), true)
			elif _touches_solid(x, y):
				astar.set_point_weight_scale(Vector2i(x, y), 4.0)


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

func update_flow(sources: Array) -> void:
	if flow.size() != W * H:
		flow.resize(W * H)
	flow.fill(FLOW_INF)
	var queue := PackedInt32Array()
	queue.resize(W * H)
	var head := 0
	var tail := 0
	for s in sources:
		var c := to_cell(s)
		if is_solid(c.x, c.y):
			continue
		var i := c.y * W + c.x
		flow[i] = 0
		queue[tail] = i
		tail += 1
	while head < tail:
		var i := queue[head]
		head += 1
		var d := flow[i]
		if d >= FLOW_MAX:
			continue
		for n in [i - 1, i + 1, i - W, i + W]:
			if blocked[n] == 0 and flow[n] > d + 1:
				flow[n] = d + 1
				queue[tail] = n
				tail += 1


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


func _draw() -> void:
	var sz := size_px()
	draw_rect(Rect2(Vector2.ZERO, sz), COL_GROUND)
	for s in specks:
		var c := COL_GROUND.lightened(s[2]) if s[2] > 0 else COL_GROUND.darkened(-s[2])
		draw_rect(Rect2(s[0], Vector2(s[1], s[1])), c)
	for cr in craters:
		draw_circle(cr[0], cr[1], Color(0.11, 0.115, 0.1, 0.8))
		draw_arc(cr[0], cr[1], 0, TAU, 24, Color(0.22, 0.22, 0.18, 0.5), 2.0)
	# faint survey grid
	var gc := Color(0.4, 0.5, 0.35, 0.05)
	for x in range(0, W + 1, 5):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, sz.y), gc, 1.0)
	for y in range(0, H + 1, 5):
		draw_line(Vector2(0, y * CELL), Vector2(sz.x, y * CELL), gc, 1.0)
	# plazas: rubble-strewn open ground
	for pl in plazas:
		draw_circle(pl[0], pl[1] * 0.85, Color(0.17, 0.17, 0.14, 0.5))
		var pr := RandomNumberGenerator.new()
		pr.seed = int(pl[0].x * 31 + pl[0].y)
		for k in 10:
			var rp: Vector2 = pl[0] + Vector2.from_angle(pr.randf() * TAU) * pr.randf() * pl[1] * 0.8
			draw_rect(Rect2(rp, Vector2(pr.randf_range(3, 9), pr.randf_range(3, 7))), COL_EDGE.darkened(0.45))
	# buildings
	for r in buildings:
		var rp := Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)
		draw_rect(rp.grow(3), Color(0, 0, 0, 0.35))
		draw_rect(rp, COL_BLDG)
		draw_rect(rp.grow(-5), COL_ROOF)
		draw_rect(rp, COL_EDGE, false, 1.5)
		var hv := int(r.position.x * 7 + r.position.y * 13)
		if hv % 3 == 0:
			draw_rect(Rect2(rp.position + Vector2(8, 8), Vector2(10, 6)), COL_EDGE.darkened(0.3))
		if hv % 4 == 1:
			draw_line(rp.position + Vector2(6, rp.size.y - 6), rp.position + Vector2(rp.size.x - 6, 6), COL_BLDG, 3.0)
	# settlement walls and lights
	for wr in walls:
		for x in range(wr.position.x, wr.end.x):
			for y in range(wr.position.y, wr.end.y):
				if is_solid(x, y):
					draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), COL_WALL.darkened(0.35))
					draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)).grow(-4), COL_WALL)
	var font := ThemeDB.fallback_font
	_draw_settlement(start_zone, "OUTPOST GRAVEL — DEPARTED", Color(0.7, 0.8, 0.6), font)
	_draw_settlement(goal_zone, "HAVEN-7 — DESTINATION", Color(1.0, 0.82, 0.45), font)


func _draw_settlement(z: Rect2, label: String, col: Color, font: Font) -> void:
	draw_rect(z, Color(col, 0.06))
	var r := RandomNumberGenerator.new()
	r.seed = int(z.position.x)
	for i in 14:
		var p := z.position + Vector2(r.randf() * z.size.x, r.randf() * z.size.y)
		draw_rect(Rect2(p, Vector2(r.randf_range(14, 40), r.randf_range(10, 30))), Color(0.18, 0.17, 0.14))
		draw_circle(p + Vector2(4, 4), 2.5, Color(1.0, 0.75, 0.35, 0.9))
	draw_string(font, z.position + Vector2(4, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _build_map_texture() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.14, 0.11, 0.92))
	for x in W:
		for y in H:
			if is_solid(x, y):
				img.set_pixel(x, y, Color(0.4, 0.45, 0.36))
	map_texture = ImageTexture.create_from_image(img)
