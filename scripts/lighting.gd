class_name Lighting
extends Node
## The zones are dark. Each mech projects a cone of light where it aims,
## shadowed by buildings (ray-cast against the city grid), plus a small hull
## halo. Explosions and muzzle flashes briefly light the area; settlements
## burn beacons.
##
## Cheap by design: all light shapes are painted once per frame, additively,
## into a half-resolution light map (a SubViewport), and the post filter
## multiplies the scene by it in its single full-screen pass. No Light2D.
## Game logic uses the same cone (VIS_RANGE / VIS_HALF) to decide what the
## squad can see — see EnemyManager._update_visibility().

const VIS_RANGE := 520.0               # cone reach, px
const VIS_HALF := deg_to_rad(32.0)     # half-angle of the cone
const HALO := 95.0                     # always-lit radius around each hull
const AMBIENT := Color(0.035, 0.045, 0.045)
const CONE_RAYS := 30
const HALO_RAYS := 20
const MAP_SCALE := 0.5                 # light map resolution vs. the screen

var world: World
var mechs: Array = []
var flashes: Array = []                # {pos, r, t, dur, e}
var beacons: Array = []                # [pos, radius, intensity]
var vp: SubViewport
var cam: Camera2D
var painter: Painter


class Painter extends Node2D:
	var lt: Lighting

	func _draw() -> void:
		lt.paint(self)


func setup(p_world: World, p_mechs: Array) -> void:
	world = p_world
	mechs = p_mechs
	beacons = [[world.goal_zone.get_center(), 520.0, 0.9], [world.start_zone.get_center(), 420.0, 0.55]]
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(vp)
	cam = Camera2D.new()
	vp.add_child(cam)
	cam.make_current()
	painter = Painter.new()
	painter.lt = self
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	painter.material = add
	vp.add_child(painter)
	_resize()


func light_texture() -> Texture2D:
	return vp.get_texture()


func _resize() -> void:
	var s := get_viewport().get_visible_rect().size * MAP_SCALE
	var si := Vector2i(maxi(16, int(s.x)), maxi(16, int(s.y)))
	if vp.size != si:
		vp.size = si


func flash(pos: Vector2, radius: float, strength: float = 1.0) -> void:
	if flashes.size() > 24:
		flashes.pop_front()
	flashes.append({"pos": pos, "r": radius, "t": 0.0, "dur": 0.3 + radius / 700.0, "e": 1.3 * strength})


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if vp == null or G.camera == null:
		return
	_resize()
	# mirror the main camera at half resolution
	cam.global_position = G.camera.get_screen_center_position()
	cam.zoom = G.camera.zoom * MAP_SCALE
	var keep: Array = []
	for f in flashes:
		f.t += delta
		if f.t < f.dur:
			keep.append(f)
	flashes = keep
	painter.queue_redraw()
	G.pe("lighting", t0)


func paint(ci: CanvasItem) -> void:
	var t0 := Time.get_ticks_usec()
	var view: Rect2 = G.camera.view_rect().grow(VIS_RANGE)
	for b in beacons:
		if view.has_point(b[0]):
			_radial(ci, b[0], b[1], Color(1.0, 0.72, 0.38) * b[2])
	var t := Time.get_ticks_msec() / 1000.0
	for lp in world.lamps:
		var lpos: Vector2 = lp[0]
		if not view.has_point(lpos):
			continue
		var fl: float = lp[3]
		var seed := lpos.x * 0.013 + lpos.y * 0.007
		var flick := 1.0 - fl * 0.5 * (0.5 + 0.5 * sin(t * 13.0 + seed * 9.0)) * (0.5 + 0.5 * sin(t * 3.7 + seed * 5.0))
		if fl > 0.5 and fmod(t + seed * 3.0, 4.0) < 0.12:
			flick *= 0.15                   # the odd brown-out on broken lamps
		_radial(ci, lpos, lp[1], Color(lp[2]) * 0.75 * flick)
	for m in mechs:
		if not m.alive or not view.has_point(m.position):
			continue
		var tint: Color = Color(1.0, 0.97, 0.88).lerp(m.color, 0.18)
		var e := 0.55 if m.overheated > 0.0 else 1.25
		_cone(ci, m.position, m.aim_dir.angle(), tint * e)
		_radial(ci, m.position, HALO, tint * 0.75)
	for f in flashes:
		var k: float = 1.0 - f.t / f.dur
		_radial(ci, f.pos, f.r, Color(1.0, 0.68, 0.35) * (f.e * k * k))
	G.pe(" · light rays", t0)


func _cone(ci: CanvasItem, o: Vector2, ang: float, col: Color) -> void:
	var pts := PackedVector2Array([o])
	var cols := PackedColorArray([col])
	for i in CONE_RAYS + 1:
		var a := ang - VIS_HALF + (2.0 * VIS_HALF) * i / CONE_RAYS
		var d := Vector2.from_angle(a)
		var dist := world.ray_dist(o, d, VIS_RANGE)
		# soft edge on the outermost rays
		var edge := 1.0 if i > 1 and i < CONE_RAYS - 1 else 0.35
		pts.append(o + d * dist)
		cols.append(col * (1.0 - dist / VIS_RANGE) * edge)
	_fan(ci, pts, cols)


func _halo(ci: CanvasItem, o: Vector2, col: Color) -> void:
	var pts := PackedVector2Array([o])
	var cols := PackedColorArray([col])
	for i in HALO_RAYS + 1:
		var d := Vector2.from_angle(TAU * i / HALO_RAYS)
		var dist := world.ray_dist(o, d, HALO)
		pts.append(o + d * dist)
		cols.append(col * (1.0 - dist / HALO) * 0.0)
	_fan(ci, pts, cols)


func _radial(ci: CanvasItem, o: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([o])
	var cols := PackedColorArray([col])
	for i in 25:
		pts.append(o + Vector2.from_angle(TAU * i / 24.0) * r)
		cols.append(Color(0, 0, 0))
	_fan(ci, pts, cols)


func _fan(ci: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	## Triangle fan around pts[0]; explicit indices, so no triangulation step.
	var idx := PackedInt32Array()
	for i in range(1, pts.size() - 1):
		idx.append(0)
		idx.append(i)
		idx.append(i + 1)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func in_cone(m: Mech, p: Vector2) -> bool:
	var v := p - m.position
	var d2 := v.length_squared()
	if d2 < HALO * HALO:
		return true
	if d2 > VIS_RANGE * VIS_RANGE:
		return false
	return absf(m.aim_dir.angle_to(v)) < VIS_HALF
