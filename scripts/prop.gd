@tool
extends Node2D
## One standing world object (pine, leafy tree or boulder), drawn upright in a
## Don't Starve-style 3/4 view. The node's origin is the object's FOOT on the
## ground, so y-sorting puts it in front of or behind characters correctly.

enum Kind { PINE, LEAFY, ROCK }

var kind: int = Kind.PINE
var width := 40.0          # trees: canopy width; rocks: radius
var height := 80.0
var tint := 0.0
var points := PackedVector2Array()   # rock outline (footprint, unsquashed)


func _draw() -> void:
	match kind:
		Kind.PINE:
			_draw_pine()
		Kind.LEAFY:
			_draw_leafy()
		Kind.ROCK:
			_draw_rock()


func _ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pine() -> void:
	var dark := Color(0.08, 0.20, 0.12).lerp(Color(0.10, 0.24, 0.10), tint)
	var light := dark.lightened(0.2)
	_ellipse(Vector2(5, 2), width * 0.55, width * 0.2, Color(0, 0, 0, 0.35))
	var tw := maxf(width * 0.14, 5.0)
	draw_rect(Rect2(-tw / 2.0, -height * 0.24, tw, height * 0.24), Color(0.30, 0.19, 0.11))
	for i in 3:
		var base_y := -height * 0.18 - i * height * 0.22
		var top_y := base_y - height * 0.40
		var half_w := width * (1.0 - i * 0.24) * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half_w, base_y), Vector2(half_w, base_y), Vector2(0, top_y)]), dark)
		# lit left side
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half_w * 0.85, base_y - 1.5), Vector2(-1, base_y - 1.5), Vector2(-1, top_y + 3)]), light)


func _draw_leafy() -> void:
	var dark := Color(0.12, 0.25, 0.11).lerp(Color(0.18, 0.27, 0.10), tint)
	var light := dark.lightened(0.18)
	var r := width * 0.5
	_ellipse(Vector2(5, 2), r * 1.05, r * 0.4, Color(0, 0, 0, 0.35))
	var tw := maxf(width * 0.16, 5.0)
	draw_rect(Rect2(-tw / 2.0, -height * 0.45, tw, height * 0.45), Color(0.33, 0.22, 0.13))
	var c := Vector2(0, -height + r)
	draw_circle(c + Vector2(-r * 0.45, r * 0.25), r * 0.7, dark)
	draw_circle(c + Vector2(r * 0.45, r * 0.25), r * 0.7, dark)
	draw_circle(c, r * 0.8, dark)
	draw_circle(c + Vector2(-r * 0.25, -r * 0.2), r * 0.45, light)


func _draw_rock() -> void:
	var base := Color(0.47, 0.45, 0.43).darkened(tint * 0.25)
	var shadow := PackedVector2Array()
	var body := PackedVector2Array()
	var top := PackedVector2Array()
	for v in points:
		shadow.append(Vector2(v.x + 5, v.y * 0.5 + 2))
		body.append(Vector2(v.x, v.y * 0.75 - width * 0.45))
		top.append(Vector2(v.x * 0.55 - width * 0.12, v.y * 0.4 - width * 0.75))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	draw_colored_polygon(body, base)
	draw_colored_polygon(top, base.lightened(0.15))
