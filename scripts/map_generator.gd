@tool
extends Node2D
## Procedurally generates the play area from a seed:
##   - a clearing in the center where settlers spawn
##   - a forest ring whose density varies with noise (good hiding spots)
##   - rocky mountains toward the edges
## The same seed always gives the same map, which makes multiplayer sync easy
## later: the host only has to send the seed.
##
## View: Don't Starve-style 3/4 camera. Objects stand upright and live in the
## y-sorted `entities` node together with the player.

const Prop := preload("res://scripts/prop.gd")

## The fixed map used for now. Change it (or use random seeds) later.
const DEFAULT_SEED := 777

const CELL := 32                # world pixels per placement cell
const GRID := 128               # cells per side -> 4096 x 4096 px map
const GROUND_RES := 2           # ground texture pixels per cell
const CLEARING_RADIUS := 0.12   # fraction of half the map width
const MOUNTAIN_START := 0.80    # fraction of half the map width

# Light masks: props are lit by the player's vision light but never darkened by
# its shadows (they stay readable as silhouettes). Ground and characters are on
# layer 1 and DO get shadowed, so anyone standing behind a tree is hidden.
const PROP_LIGHT_MASK := 2

enum Biome { CLEARING, FOREST, MOUNTAIN }

const PROP_SHADER := """
shader_type canvas_item;
// Makes a tree/rock see-through when the local player stands behind it.
uniform vec2 player_pos;
uniform float fade_radius = 34.0;
varying vec2 world_pos;
varying float base_y;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	base_y = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y;
}
void fragment() {
	vec2 d = (world_pos - (player_pos + vec2(0.0, -16.0))) * vec2(1.0, 0.7);
	float near = 1.0 - smoothstep(fade_radius * 0.6, fade_radius, length(d));
	float in_front = step(player_pos.y, base_y);
	COLOR.a *= 1.0 - near * in_front * 0.7;
}
"""

var map_size := Vector2(GRID * CELL, GRID * CELL)
var center := map_size / 2.0
var entities: Node2D            # y-sorted: props + characters

var _rng := RandomNumberGenerator.new()
var _forest_noise := FastNoiseLite.new()
var _mountain_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _body: StaticBody2D
var _occluders: Node2D
var _prop_material: ShaderMaterial


func generate(seed_value: int) -> void:
	_rng.seed = seed_value
	_forest_noise.seed = seed_value
	_forest_noise.frequency = 0.0012
	_forest_noise.fractal_octaves = 4
	_mountain_noise.seed = seed_value + 1
	_mountain_noise.frequency = 0.0025
	_detail_noise.seed = seed_value + 2
	_detail_noise.frequency = 0.02

	var shader := Shader.new()
	shader.code = PROP_SHADER
	_prop_material = ShaderMaterial.new()
	_prop_material.shader = shader
	_prop_material.set_shader_parameter("player_pos", Vector2(-9999, -9999))

	_build_ground()

	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	_body = StaticBody2D.new()
	add_child(_body)
	_occluders = Node2D.new()
	add_child(_occluders)

	_place_objects()
	_build_borders()


func get_spawn_point() -> Vector2:
	return center + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.0, 60.0)


func set_player_position(p: Vector2) -> void:
	if _prop_material:
		_prop_material.set_shader_parameter("player_pos", p)


## Returns [biome, forest_density 0..1] for a world position.
func sample(p: Vector2) -> Array:
	var d := p.distance_to(center) / (map_size.x / 2.0)
	var m := _mountain_noise.get_noise_2dv(p) * 0.18
	if d + m > MOUNTAIN_START:
		return [Biome.MOUNTAIN, 0.0]
	var clearing_r := CLEARING_RADIUS + _forest_noise.get_noise_2dv(p * 3.0) * 0.03
	if d < clearing_r:
		return [Biome.CLEARING, 0.0]
	var n := _forest_noise.get_noise_2dv(p)
	var ramp := smoothstep(clearing_r, clearing_r + 0.12, d)
	var density := clampf((0.55 + n * 1.1) * ramp, 0.0, 1.0)
	return [Biome.FOREST, density]


# --- Ground -----------------------------------------------------------------

func _build_ground() -> void:
	var res := GRID * GROUND_RES
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	var px := float(CELL) / GROUND_RES
	for y in res:
		for x in res:
			var p := Vector2((x + 0.5) * px, (y + 0.5) * px)
			var s := sample(p)
			var col: Color
			match s[0]:
				Biome.CLEARING:
					col = Color(0.40, 0.50, 0.27)
				Biome.FOREST:
					col = Color(0.36, 0.45, 0.24).lerp(Color(0.18, 0.25, 0.14), s[1])
				_:
					col = Color(0.42, 0.40, 0.38)
			var detail := _detail_noise.get_noise_2dv(p) * 0.08
			col = col.lightened(detail) if detail > 0.0 else col.darkened(-detail)
			img.set_pixel(x, y, col)

	var ground := Sprite2D.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.centered = false
	ground.scale = Vector2(px, px)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ground.z_index = -10
	add_child(ground)


# --- Trees and rocks ----------------------------------------------------------

func _place_objects() -> void:
	var circles := {}       # shared collision shapes by radius
	var occ_polys := {}     # shared occluder polygons by size
	for gy in GRID:
		for gx in GRID:
			var p := Vector2(
				(gx + _rng.randf_range(0.15, 0.85)) * CELL,
				(gy + _rng.randf_range(0.15, 0.85)) * CELL)
			var s := sample(p)
			match s[0]:
				Biome.FOREST:
					if _rng.randf() < s[1] * 0.55:
						var kind := Prop.Kind.PINE if _rng.randf() < 0.7 else Prop.Kind.LEAFY
						_add_tree(p, kind, _rng.randf_range(32.0, 56.0), circles, occ_polys)
				Biome.MOUNTAIN:
					var roll := _rng.randf()
					if roll < 0.13:
						_add_rock(p, _rng.randf_range(16.0, 40.0))
					elif roll < 0.19:
						_add_tree(p, Prop.Kind.PINE, _rng.randf_range(24.0, 36.0), circles, occ_polys)


func _add_tree(p: Vector2, kind: int, width: float, circles: Dictionary, occ_polys: Dictionary) -> void:
	var prop := Prop.new()
	prop.kind = kind
	prop.width = width
	prop.height = width * _rng.randf_range(1.8, 2.3)
	prop.tint = _rng.randf()
	_setup_prop(prop, p)

	# Collision at the trunk only.
	var trunk_r := int(clampf(width * 0.12, 5.0, 7.0))
	if not circles.has(trunk_r):
		var c := CircleShape2D.new()
		c.radius = trunk_r
		circles[trunk_r] = c
	var cs := CollisionShape2D.new()
	cs.shape = circles[trunk_r]
	cs.position = p
	_body.add_child(cs)

	# Vision blocker: a flat ellipse around the trunk base. Small enough that the
	# player (radius 7) can never stand inside it.
	var occ_r := trunk_r + 4
	if not occ_polys.has(occ_r):
		var op := OccluderPolygon2D.new()
		op.polygon = _ellipse_points(occ_r, occ_r * 0.6)
		occ_polys[occ_r] = op
	var occ := LightOccluder2D.new()
	occ.occluder = occ_polys[occ_r]
	occ.position = p
	_occluders.add_child(occ)


func _add_rock(p: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var n := _rng.randi_range(6, 9)
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.2, 0.2)
		pts.append(Vector2.from_angle(a) * r * _rng.randf_range(0.8, 1.1))

	var prop := Prop.new()
	prop.kind = Prop.Kind.ROCK
	prop.width = r
	prop.points = pts
	prop.tint = _rng.randf()
	_setup_prop(prop, p)

	# Footprint on the ground (squashed for the 3/4 view) = collision + vision blocker.
	var footprint := PackedVector2Array()
	for v in pts:
		footprint.append(Vector2(v.x, v.y * 0.55))
	var col := CollisionPolygon2D.new()
	col.polygon = footprint
	col.position = p
	_body.add_child(col)
	var op := OccluderPolygon2D.new()
	op.polygon = footprint
	var occ := LightOccluder2D.new()
	occ.occluder = op
	occ.position = p
	_occluders.add_child(occ)


func _setup_prop(prop: Node2D, p: Vector2) -> void:
	prop.position = p
	prop.light_mask = PROP_LIGHT_MASK
	prop.material = _prop_material
	entities.add_child(prop)


func _ellipse_points(rx: float, ry: float, segments: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _build_borders() -> void:
	var t := 64.0
	var rects := [
		Rect2(-t, -t, map_size.x + 2 * t, t),
		Rect2(-t, map_size.y, map_size.x + 2 * t, t),
		Rect2(-t, 0, t, map_size.y),
		Rect2(map_size.x, 0, t, map_size.y),
	]
	for rect in rects:
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = rect.get_center()
		_body.add_child(cs)
