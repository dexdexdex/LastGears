class_name Atlas
extends RefCounted
## The regional network: human havens, outposts, machine hives and ruins,
## linked by zones (the ground you trudge across between them). Generated
## once from a fixed seed so the region is the same every run.
## Positions are normalised 0..1 and laid out by the HUD.

const SEED := 20761

const HAVENS := ["Haven-7", "Bastion Kell", "Lantern", "Sanctum Ory", "Deepwell", "Hearthome"]
const OUTPOSTS := ["Outpost Gravel", "Tamsin Post", "Relay Nine"]
const HIVES := ["Hive Theta", "Node Black", "The Choir", "Foundry Prime"]
const RUINS := ["Old Meridian", "Sky Harbor", "Cradle Dam"]
const ZONE_A := ["Ash", "Glass", "Rust", "Kiln", "Salt", "Pylon", "Copper", "Silent", "Bone", "Static", "Cinder", "Hollow", "Grey", "Ember", "Iron"]
const ZONE_B := ["Flats", "Sprawl", "Expressway", "Orchard", "Marsh", "Arcology", "Interchange", "Wastes", "Yards", "Causeway", "Terraces", "Gulch", "Fields", "Canals", "Barrens"]
const TERRAIN := ["dead city", "open flats", "collapsed overpasses", "flooded blocks", "scrap fields", "industrial yards"]

var nodes: Array = []    # {name, kind, pos, pop, note}
var edges: Array = []    # {a, b, zone, threat, terrain, known}
var start_idx := 0
var goal_idx := 0
var current_edge := 0
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = SEED
	_place_nodes()
	_link()
	_label_edges()


func _place_nodes() -> void:
	var kinds: Array = []
	for n in HAVENS: kinds.append(["haven", n])
	for n in OUTPOSTS: kinds.append(["outpost", n])
	for n in HIVES: kinds.append(["hive", n])
	for n in RUINS: kinds.append(["ruin", n])
	var pts: Array = []
	var tries := 0
	while pts.size() < kinds.size() and tries < 5000:
		tries += 1
		var p := Vector2(rng.randf_range(0.05, 0.95), rng.randf_range(0.08, 0.92))
		var ok := true
		for q in pts:
			if q.distance_to(p) < 0.17:
				ok = false
				break
		if ok:
			pts.append(p)
	# Gravel sits west-of-centre; Haven-7 is its nearest neighbour to the east.
	var gi := 0
	var bd := INF
	for i in pts.size():
		var d: float = pts[i].distance_to(Vector2(0.3, 0.55))
		if d < bd:
			bd = d
			gi = i
	var hi := -1
	bd = INF
	for i in pts.size():
		if i != gi and pts[i].x > pts[gi].x + 0.06:
			var d: float = pts[i].distance_to(pts[gi])
			if d < bd:
				bd = d
				hi = i
	# Assign kinds: Gravel and Haven-7 to those spots, shuffle the rest.
	var rest: Array = []
	for k in kinds:
		if k[1] != "Outpost Gravel" and k[1] != "Haven-7":
			rest.append(k)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = rest[i]
		rest[i] = rest[j]
		rest[j] = t
	for i in pts.size():
		var k: Array
		if i == gi:
			k = ["outpost", "Outpost Gravel"]
		elif i == hi:
			k = ["haven", "Haven-7"]
		else:
			k = rest.pop_back()
		nodes.append({"name": k[1], "kind": k[0], "pos": pts[i], "pop": 0, "note": ""})
	start_idx = gi
	goal_idx = hi
	for n in nodes:
		match n.kind:
			"haven":
				n.pop = rng.randi_range(4, 30) * 50
				n.note = ["Walls holding.", "Trading water for cells.", "Short on circuits.", "Field hospital.", "Quiet. Too quiet.", "Fortified grain silo."][rng.randi() % 6]
			"outpost":
				n.pop = rng.randi_range(1, 6) * 20
				n.note = ["Waystation.", "Signal relay, barely staffed.", "Last stop before the flats."][rng.randi() % 3]
			"hive":
				n.note = ["Machine fabricator. Swarms originate here.", "Signal mast. Don't linger.", "Seismic source. Hordes inbound from here."][rng.randi() % 3]
			"ruin":
				n.note = ["Pre-war landmark. Salvage rich.", "Collapsed. Machines nest here.", "Dead zone. Scanners scramble."][rng.randi() % 3]
	nodes[start_idx].note = "Departed. The convoy's last stop."
	nodes[goal_idx].note = "Destination. Gates open for mechs."


func _link() -> void:
	# Spanning tree (Prim) for connectivity, then extra short non-crossing links.
	_add_edge(start_idx, goal_idx)
	var in_tree := {start_idx: true, goal_idx: true}
	while in_tree.size() < nodes.size():
		var best := [-1, -1]
		var bd := INF
		for i in in_tree:
			for j in nodes.size():
				if in_tree.has(j):
					continue
				var d: float = nodes[i].pos.distance_to(nodes[j].pos)
				if d < bd and not _crosses(i, j):
					bd = d
					best = [i, j]
		if best[0] == -1:
			# fall back: allow a crossing rather than leave a node orphaned
			for i in in_tree:
				for j in nodes.size():
					if not in_tree.has(j):
						var d2: float = nodes[i].pos.distance_to(nodes[j].pos)
						if d2 < bd:
							bd = d2
							best = [i, j]
		_add_edge(best[0], best[1])
		in_tree[best[1]] = true
	var pairs: Array = []
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			pairs.append([nodes[i].pos.distance_to(nodes[j].pos), i, j])
	pairs.sort_custom(func(a, b): return a[0] < b[0])
	var extra := 0
	for pr in pairs:
		if extra >= 7 or pr[0] > 0.36:
			break
		if not _has_edge(pr[1], pr[2]) and not _crosses(pr[1], pr[2]):
			_add_edge(pr[1], pr[2])
			extra += 1
	for i in edges.size():
		var e: Dictionary = edges[i]
		if (e.a == start_idx and e.b == goal_idx) or (e.b == start_idx and e.a == goal_idx):
			current_edge = i


func _add_edge(a: int, b: int) -> void:
	edges.append({"a": a, "b": b, "zone": "", "threat": 1, "terrain": "", "known": false})


func _has_edge(a: int, b: int) -> bool:
	for e in edges:
		if (e.a == a and e.b == b) or (e.a == b and e.b == a):
			return true
	return false


func _crosses(a: int, b: int) -> bool:
	var p1: Vector2 = nodes[a].pos
	var p2: Vector2 = nodes[b].pos
	for e in edges:
		if e.a == a or e.b == a or e.a == b or e.b == b:
			continue
		if Geometry2D.segment_intersects_segment(p1, p2, nodes[e.a].pos, nodes[e.b].pos) != null:
			return true
	return false


func _label_edges() -> void:
	var used := {}
	for i in edges.size():
		var e: Dictionary = edges[i]
		var nm := ""
		for t in 40:
			nm = "%s %s" % [ZONE_A[rng.randi() % ZONE_A.size()], ZONE_B[rng.randi() % ZONE_B.size()]]
			if not used.has(nm):
				break
		used[nm] = true
		e.zone = nm
		e.terrain = TERRAIN[rng.randi() % TERRAIN.size()]
		# threat from proximity to the nearest hive
		var mid: Vector2 = (nodes[e.a].pos + nodes[e.b].pos) * 0.5
		var hd := INF
		for n in nodes:
			if n.kind == "hive":
				hd = minf(hd, n.pos.distance_to(mid))
		e.threat = clampi(5 - int(hd / 0.12), 1, 5)
		if nodes[e.a].kind == "hive" or nodes[e.b].kind == "hive":
			e.threat = 5
		e.known = e.a == start_idx or e.b == start_idx or e.a == goal_idx or e.b == goal_idx
	var cur: Dictionary = edges[current_edge]
	cur.zone = "Ash Sprawl"
	cur.terrain = "dead city"
	cur.threat = 2          # the opening leg is a gentle one


func current() -> Dictionary:
	return edges[current_edge]


func edge_progress_dir(e: Dictionary) -> bool:
	## true when the edge runs start -> goal (a is Gravel)
	return e.a == start_idx
