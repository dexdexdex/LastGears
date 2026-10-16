class_name Lighting
extends Node2D
## The zones are dark. Each mech projects a cone of light where it aims
## (blocked by buildings), plus a small halo around its hull. Explosions
## and muzzle flashes briefly light the area. Settlements burn beacons.
## Game logic uses the same cone (VIS_RANGE / VIS_HALF) to decide what the
## squad can actually see — see EnemyManager.update_visibility().

const VIS_RANGE := 520.0               # cone reach, px
const VIS_HALF := deg_to_rad(32.0)     # half-angle of the cone
const HALO := 95.0                     # always-lit radius around each hull
const AMBIENT := Color(0.035, 0.045, 0.045)

static var _cone_tex: ImageTexture
static var _radial_tex: ImageTexture

var cones := {}          # Mech -> PointLight2D
var flashes: Array = []  # pool of {light, t, dur, energy}


static func cone_texture() -> ImageTexture:
	if _cone_tex:
		return _cone_tex
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) * 0.5
	var halo_r := HALO / VIS_RANGE
	for y in n:
		for x in n:
			var v := (Vector2(x, y) - c) / (n * 0.5)
			var r := v.length()
			var a := 0.0
			if r < 1.0:
				var ang := absf(v.angle())
				var edge := clampf((VIS_HALF - ang) / deg_to_rad(6.0), 0.0, 1.0)
				a = pow(1.0 - r, 0.7) * edge
				var halo := clampf(1.0 - r / halo_r, 0.0, 1.0)
				a = maxf(a, halo * halo * 0.75)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_cone_tex = ImageTexture.create_from_image(img)
	return _cone_tex


static func radial_texture() -> ImageTexture:
	if _radial_tex:
		return _radial_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var img := gt.get_image()
	_radial_tex = ImageTexture.create_from_image(img)
	return _radial_tex


func setup(world: World, mechs: Array) -> void:
	var cm := CanvasModulate.new()
	cm.color = AMBIENT
	add_child(cm)
	_add_occluders(world)
	for m in mechs:
		var l := PointLight2D.new()
		l.texture = cone_texture()
		l.texture_scale = VIS_RANGE / 256.0
		l.energy = 1.25
		l.color = Color(1.0, 0.97, 0.88).lerp(m.color, 0.18)
		l.shadow_enabled = true
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_color = Color(0, 0, 0, 1)
		add_child(l)
		cones[m] = l
	# settlement beacons
	for z in [world.start_zone, world.goal_zone]:
		var b := PointLight2D.new()
		b.texture = radial_texture()
		b.texture_scale = 4.2
		b.energy = 1.1 if z == world.goal_zone else 0.7
		b.color = Color(1.0, 0.72, 0.38)
		b.position = z.get_center()
		add_child(b)
	for i in 10:
		var fl := PointLight2D.new()
		fl.texture = radial_texture()
		fl.enabled = false
		fl.color = Color(1.0, 0.68, 0.35)
		add_child(fl)
		flashes.append({"light": fl, "t": 0.0, "dur": 1.0, "energy": 0.0})


func _add_occluders(world: World) -> void:
	var rects: Array = world.buildings.duplicate()
	# compound walls: one occluder per solid wall cell run is overkill; use cells
	for wr in world.walls:
		for x in range(wr.position.x, wr.end.x):
			for y in range(wr.position.y, wr.end.y):
				if world.is_solid(x, y):
					rects.append(Rect2i(x, y, 1, 1))
	for r in rects:
		var o := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var p := Vector2(r.position) * World.CELL
		var s := Vector2(r.size) * World.CELL
		poly.polygon = PackedVector2Array([p, p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y)])
		poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
		o.occluder = poly
		add_child(o)


func flash(pos: Vector2, radius: float, strength: float = 1.0) -> void:
	var best = flashes[0]
	for f in flashes:
		if not f.light.enabled:
			best = f
			break
		if f.t / f.dur > best.t / best.dur:
			best = f
	best.light.enabled = true
	best.light.position = pos
	best.light.texture_scale = radius / 128.0
	best.t = 0.0
	best.dur = 0.35 + radius / 600.0
	best.energy = 1.4 * strength


func _process(delta: float) -> void:
	for m in cones:
		var l: PointLight2D = cones[m]
		l.visible = m.alive
		if m.alive:
			l.position = m.position
			l.rotation = m.aim_dir.angle()
			# overheated / shut-down mechs dim their lamps
			l.energy = 0.55 if m.overheated > 0.0 else 1.25
	for f in flashes:
		if not f.light.enabled:
			continue
		f.t += delta
		var k: float = f.t / f.dur
		if k >= 1.0:
			f.light.enabled = false
		else:
			f.light.energy = f.energy * (1.0 - k) * (1.0 - k)


static func in_cone(m: Mech, p: Vector2) -> bool:
	var v := p - m.position
	var d2 := v.length_squared()
	if d2 < HALO * HALO:
		return true
	if d2 > VIS_RANGE * VIS_RANGE:
		return false
	return absf(m.aim_dir.angle_to(v)) < VIS_HALF
