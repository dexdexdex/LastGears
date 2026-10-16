class_name GameCamera
extends Camera2D
## Follows the player with aim look-ahead. Hold R2 to pull back to the
## tactical view. Trauma-based screen shake.

const ZOOM_FIELD := 1.55
const ZOOM_TACTICAL := 0.42

var trauma := 0.0
var tac_blend := 0.0
var look := Vector2.ZERO


func _ready() -> void:
	zoom = Vector2.ONE * ZOOM_FIELD
	position_smoothing_enabled = false


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	var tac_target := 1.0 if G.tactical else 0.0
	tac_blend = move_toward(tac_blend, tac_target, delta * 3.5)
	var e := ease(tac_blend, -2.0)
	zoom = Vector2.ONE * lerpf(ZOOM_FIELD, ZOOM_TACTICAL, e)
	var p := G.player
	if p == null:
		return
	var want_look := p.aim_dir * 90.0 if p.alive and not p.busy_menu else Vector2.ZERO
	if p.busy_menu:
		want_look = Vector2(140, 0)    # shift view so the refit panel doesn't hide the mech
	look = look.lerp(want_look, clampf(delta * 3.0, 0, 1))
	var focus := p.position + look * (1.0 - e)
	if e > 0.0:
		focus = focus.lerp(G.squad_centroid() + Vector2(200, 0), e * 0.6)
	global_position = global_position.lerp(focus, clampf(delta * 6.0, 0, 1))
	trauma = maxf(0.0, trauma - delta * 1.6)
	var s := trauma * trauma
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * s


func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / zoom
	return Rect2(global_position - vs * 0.5, vs)
