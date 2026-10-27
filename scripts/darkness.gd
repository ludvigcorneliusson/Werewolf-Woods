extends Node2D
## Night darkness made of soft light cells that react to the props.
##
## The map is split into square cells. Each prop makes the cells it stands on
## soak up some light (trunks most, canopies and bushes some, rocks and logs a
## little). Light travels outward from the settler in straight lines, cell by
## cell, so anything in the way casts a soft shadow wedge behind it, and dense
## forest dims the light while gaps let it through. A cell always shows the light
## that reaches it, so props never show up as dark boxes.
## The player's light is recalculated only when he steps into another cell, so it
## never moves by itself; campfire light is calculated once. The cells are blended
## smoothly and drawn by one shader as darkness over the GROUND only (between the
## ground and the props). Props and plants are lit by proximity to the player
## (prop_fade.gdshader): the shadows are only on the ground, props near you are lit.
## Created by main.gd, which sets the Fog settings; campfires join the
## "light_sources" group (see scripts/campfire.gd).

const SHADER := """
shader_type canvas_item;
uniform sampler2D player_light : filter_linear, repeat_disable;
uniform sampler2D static_light : filter_linear, repeat_disable;
uniform vec2 world_origin;          // world px at the rect's top-left corner (rect_size in world px)
uniform vec2 rect_size;
uniform float world_per_unit = 1.0;
uniform vec2 player_origin;         // world px of the player texture's top-left
uniform vec2 player_size;           // world px covered by the player texture
uniform vec2 static_origin;
uniform vec2 static_size;
uniform float static_strength = 1.0;  // campfire flicker
uniform vec3 dark_color = vec3(0.0);
uniform float darkness = 1.0;

float sample_in(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return texture(tex, uv).r;
}

void fragment() {
	vec2 world = world_origin + UV * rect_size * world_per_unit;
	float lit = sample_in(player_light, (world - player_origin) / player_size);
	lit = max(lit, sample_in(static_light, (world - static_origin) / static_size) * static_strength);
	COLOR = vec4(dark_color, darkness * (1.0 - clamp(lit, 0.0, 1.0)));
}
"""

# Light soaked up per cell, per prop image (ground footprint, radius in ART px,
# scaled by the prop's size): [core radius, core absorption, wide radius, wide absorption].
# Trees: trunk core + canopy shade around it. Main's Trunk Shade / Canopy Shade
# / Prop Shade scale these.
const PROP_MATERIAL := preload("res://assets/props/varied_material.tres")
const CHARACTER_MATERIAL := preload("res://assets/characters/character_material.tres")

const ABSORB := {
	"pine_tall.png": [13.0, 0.9, 42.0, 0.06],
	"pine_dark.png": [7.0, 0.9, 26.0, 0.06],
	"dead_pine.png": [11.0, 0.9, 20.0, 0.04],
	"dead_tree.png": [11.0, 0.9, 20.0, 0.04],
	"bush_big.png": [30.0, 0.35, 0.0, 0.0],
	"bush_small.png": [18.0, 0.25, 0.0, 0.0],
	"boulder.png": [16.0, 0.8, 0.0, 0.0],
	"mossy_rock.png": [10.0, 0.35, 0.0, 0.0],
	"stump.png": [12.0, 0.35, 0.0, 0.0],
	"stump_log.png": [26.0, 0.25, 0.0, 0.0],
	"log.png": [24.0, 0.25, 0.0, 0.0],
	"fallen_tree.png": [44.0, 0.25, 0.0, 0.0],
}
const TREES := ["pine_tall.png", "pine_dark.png", "dead_pine.png", "dead_tree.png"]
# Where the trunk/rock actually meets the ground, in ART px from the foot point
# (same offsets as the collision in tools/build_world.gd).
const BASE_AT := {
	"pine_tall.png": Vector2(0, -6), "pine_dark.png": Vector2(0, -3),
	"dead_pine.png": Vector2(-1, -7), "dead_tree.png": Vector2(2, -6),
	"stump.png": Vector2(0, -7), "boulder.png": Vector2(0, -5), "mossy_rock.png": Vector2(0, -4),
}

# Settings (main.gd sets these)
var vision_radius := 380.0
var squash := 0.78
var start := 0.3
var density := 1.5
var dark_color := Color.BLACK
var darkness := 1.0               # darkness at full night (Fog setting)
var night := 1.0                  # 0 = day .. 1 = night (day_night.gd via main.gd), scales darkness
var cell := 16
var trunk_absorption := 1.0      # x trunk absorption
var canopy_absorption := 1.0     # x canopy absorption
var prop_absorption := 1.0       # x bushes, rocks, logs
var side_shade := 0.55          # props: far side from your light darkens
var back_shade := 0.3           # props: darker when you stand behind them
var smoothness := 2               # cell blending: texture enlarged this many times with smooth filtering

var player: Node2D
var camera: Camera2D

var _rect: ColorRect
var _mat: ShaderMaterial
var _absorb := PackedFloat32Array()
var _ray_cache := {}                  # window shape -> precomputed ray steps
var _grid := Vector2i.ZERO
var _origin := Vector2.ZERO
var _last_cell := Vector2i(-99999, -99999)
var _player_tex: ImageTexture
var _fires := []


## Sets a darkness parameter on the ground overlay and (prefixed "dk_") on the
## shared prop material, so props can read the light at their base.
func _param(name: String, value) -> void:
	_mat.set_shader_parameter(name, value)
	if name in ["player_light", "static_light", "player_origin", "player_size",
			"static_origin", "static_size", "static_strength", "dark_color", "darkness"]:
		PROP_MATERIAL.set_shader_parameter("dk_" + name, value)
		CHARACTER_MATERIAL.set_shader_parameter("dk_" + name, value)


func _ready() -> void:
	# Drawn in the world between the ground (z -10) and props/characters (z 0).
	_rect = ColorRect.new()
	_rect.top_level = true
	_rect.z_index = -5
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_rect.material = _mat
	add_child(_rect)
	var blank := Image.create(1, 1, false, Image.FORMAT_L8)
	_param("player_light", ImageTexture.create_from_image(blank))
	_param("static_light", ImageTexture.create_from_image(blank))


## Which cells hold a tree trunk (from the prop layers: World/Props and your
## painted World/Placed), then the campfires' light.
func build(layers: Array, area: Rect2) -> void:
	_origin = area.position
	_grid = Vector2i((area.size / cell).ceil())
	_absorb = PackedFloat32Array()
	_absorb.resize(_grid.x * _grid.y)
	var all_props := []
	for layer in layers:
		if is_instance_valid(layer):
			all_props.append_array(layer.get_children())
	for prop in all_props:
		var sprite := prop.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var key := sprite.texture.resource_path.get_file()
		var spec = ABSORB.get(key)
		if spec == null:
			continue
		var sc: float = prop.scale.x
		var tree := key in TREES
		var at: Vector2 = BASE_AT.get(key, Vector2.ZERO)
		var sprite_flipped: bool = sprite.flip_h
		var p: Vector2 = prop.global_position + Vector2(-at.x if sprite_flipped else at.x, at.y) * sc
		if spec[3] > 0.0:
			_stamp(p, spec[2] * sc, spec[3] * (canopy_absorption if tree else prop_absorption))
		_stamp(p, spec[0] * sc, spec[1] * (trunk_absorption if tree else prop_absorption))
	_last_cell = Vector2i(-99999, -99999)
	_build_static()


## Adds absorption over a flat ellipse (3/4 view footprint) around a prop's base.
func _stamp(p: Vector2, r: float, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	var c := (p - _origin) / cell
	var rx := maxf(r / cell, 0.5)
	var ry := maxf(r * 0.5 / cell, 0.5)
	for y in range(maxi(int(c.y - ry), 0), mini(int(c.y + ry) + 1, _grid.y)):
		for x in range(maxi(int(c.x - rx), 0), mini(int(c.x + rx) + 1, _grid.x)):
			var dx := (x + 0.5 - c.x) / rx
			var dy := (y + 0.5 - c.y) / ry
			if dx * dx + dy * dy <= 1.0:
				var i := y * _grid.x + x
				_absorb[i] = 1.0 - (1.0 - _absorb[i]) * (1.0 - a)


## Campfires: their light is calculated once into a map-wide texture.
func _build_static() -> void:
	_fires = get_tree().get_nodes_in_group("light_sources")
	var img := Image.create(maxi(_grid.x, 1), maxi(_grid.y, 1), false, Image.FORMAT_L8)
	for f in _fires:
		if not (f is Node2D):
			continue
		var r: float = f.get("light_radius") if f.get("light_radius") != null else 150.0
		var res := _flood(f.global_position - Vector2(0, 8), r)
		var w: int = res[1].x
		var h: int = res[1].y
		var x0: int = res[2].x
		var y0: int = res[2].y
		var bytes: PackedByteArray = res[0]
		for y in h:
			for x in w:
				var gx := x0 + x
				var gy := y0 + y
				if gx >= 0 and gy >= 0 and gx < _grid.x and gy < _grid.y:
					var v := bytes[y * w + x]
					if v > img.get_pixel(gx, gy).r8:
						img.set_pixel(gx, gy, Color8(v, v, v))
	img = _soften(img)
	_param("static_light", ImageTexture.create_from_image(img))
	_param("static_origin", _origin)
	_param("static_size", Vector2(_grid) * cell)


func _process(_delta: float) -> void:
	if camera == null or _mat == null:
		return
	var zoom := camera.zoom.x
	var view := get_viewport().get_visible_rect().size / zoom + Vector2(64, 64)
	var centre := camera.get_screen_center_position()
	_rect.global_position = centre - view * 0.5
	_rect.size = view
	_param("world_origin", centre - view * 0.5)
	_param("rect_size", view)
	_param("world_per_unit", 1.0)
	var fl := 0.0
	for f in _fires:
		if is_instance_valid(f) and f.get("flicker_now") != null:
			fl = f.flicker_now
	_param("static_strength", 1.0 + fl * 0.5)

	if _absorb.is_empty() or not is_instance_valid(player):
		return
	var pc := Vector2i(((player.global_position - _origin) / cell).floor())
	if pc == _last_cell:
		return                                  # only when he steps into another cell
	_last_cell = pc
	_update_player()


func _update_player() -> void:
	var res := _flood(player.global_position - Vector2(0, 16), vision_radius)
	var w: int = res[1].x
	var h: int = res[1].y
	var img := Image.create_from_data(w, h, false, Image.FORMAT_L8, res[0])
	img = _soften(img)
	if _player_tex and Vector2i(_player_tex.get_size()) == img.get_size():
		_player_tex.update(img)
	else:
		_player_tex = ImageTexture.create_from_image(img)
		_param("player_light", _player_tex)
	_param("player_origin", _origin + Vector2(res[2]) * cell)
	_param("player_size", Vector2(w, h) * cell)


## Enlarges the cell image with smooth (cubic) filtering: soft squares.
func _soften(img: Image) -> Image:
	if smoothness > 1:
		img.resize(img.get_width() * smoothness, img.get_height() * smoothness, Image.INTERPOLATE_CUBIC)
	else:
		# Hard squares: enlarge with hard edges so the shader's blending can't soften them.
		img.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	return img


## For a window shape: cells sorted from the centre outwards, and for each cell
## the point one step back towards the centre (bilinear: 4 cells + weights).
func _rays(w: int, h: int, cx: int, cy: int) -> Dictionary:
	var key := Vector3i(w, h, int(squash * 1000.0))
	if _ray_cache.has(key):
		return _ray_cache[key]
	var cells := []
	for y in h:
		for x in w:
			var dx := float(x - cx)
			var dy := float(y - cy) / squash
			cells.append([dx * dx + dy * dy, y * w + x])
	cells.sort_custom(func(a, b): return a[0] < b[0])
	var order := PackedInt32Array()
	var p00 := PackedInt32Array()
	var p10 := PackedInt32Array()
	var p01 := PackedInt32Array()
	var p11 := PackedInt32Array()
	var fx := PackedFloat32Array()
	var fy := PackedFloat32Array()
	var dist := PackedFloat32Array()        # world-space distance / cell
	dist.resize(w * h)
	for c in cells:
		var i: int = c[1]
		var x := i % w
		var y := i / w
		var v := Vector2(x - cx, y - cy)
		dist[i] = sqrt(c[0])
		order.append(i)
		if v.length() <= 1.5:
			p00.append(-1); p10.append(-1); p01.append(-1); p11.append(-1)
			fx.append(0.0); fy.append(0.0)
			continue
		var b := Vector2(x, y) - v.normalized()            # one step back towards the source
		var bx := clampi(int(floor(b.x)), 0, w - 2)
		var by := clampi(int(floor(b.y)), 0, h - 2)
		p00.append(by * w + bx)
		p10.append(by * w + bx + 1)
		p01.append((by + 1) * w + bx)
		p11.append((by + 1) * w + bx + 1)
		fx.append(clampf(b.x - bx, 0.0, 1.0))
		fy.append(clampf(b.y - by, 0.0, 1.0))
	var r := {"order": order, "p00": p00, "p10": p10, "p01": p01, "p11": p11, "fx": fx, "fy": fy, "dist": dist}
	_ray_cache[key] = r
	return r


## Light from a world point: straight-line rays outward through the cells within
## reach. Returns [brightness bytes, size, top-left cell].
func _flood(from: Vector2, reach: float) -> Array:
	var steps_x := int(ceil(reach / cell)) + 1
	var steps_y := int(ceil(reach * squash / cell)) + 1
	var w := steps_x * 2 + 1
	var h := steps_y * 2 + 1
	var pc := Vector2i(((from - _origin) / cell).floor())
	var x0 := pc.x - steps_x
	var y0 := pc.y - steps_y
	var ab := PackedFloat32Array()
	ab.resize(w * h)
	for y in h:
		var gy := y0 + y
		for x in w:
			var gx := x0 + x
			if gx >= 0 and gy >= 0 and gx < _grid.x and gy < _grid.y:
				ab[y * w + x] = _absorb[gy * _grid.x + gx]
			else:
				ab[y * w + x] = 1.0
	# Never shade the light's own spot (e.g. the settler standing by a trunk).
	for yy in range(maxi(steps_y - 2, 0), mini(steps_y + 3, h)):
		for xx in range(maxi(steps_x - 2, 0), mini(steps_x + 3, w)):
			ab[yy * w + xx] = 0.0
	var R := _rays(w, h, steps_x, steps_y)
	var order: PackedInt32Array = R.order
	var p00: PackedInt32Array = R.p00
	var p10: PackedInt32Array = R.p10
	var p01: PackedInt32Array = R.p01
	var p11: PackedInt32Array = R.p11
	var fxa: PackedFloat32Array = R.fx
	var fya: PackedFloat32Array = R.fy
	var dist: PackedFloat32Array = R.dist
	var T := PackedFloat32Array()      # light passed on (after this cell soaks some up)
	T.resize(w * h)
	var bytes := PackedByteArray()
	bytes.resize(w * h)
	var reach_cells := reach / cell
	for n in order.size():
		var i := order[n]
		var arriving := 1.0
		var a := p00[n]
		if a >= 0:
			var fx := fxa[n]
			var fy := fya[n]
			arriving = lerpf(lerpf(T[a], T[p10[n]], fx), lerpf(T[p01[n]], T[p11[n]], fx), fy)
		T[i] = arriving * (1.0 - ab[i])
		# What this cell shows: the light reaching it, faded by distance.
		var r := dist[i] / reach_cells
		if r >= 1.0 or arriving <= 0.0:
			continue
		var k := clampf((r - start) / maxf(1.0 - start, 0.001), 0.0, 1.0)
		bytes[i] = int(pow(1.0 - smoothstep(0.0, 1.0, k), density) * arriving * 255.0)
	return [bytes, Vector2i(w, h), Vector2i(x0, y0)]


## Day/night: how far into the night it is (0..1). Cheap, no relighting.
func set_night(v: float) -> void:
	if is_equal_approx(v, night) and _mat != null:
		return
	night = v
	if _mat:
		_param("darkness", darkness * night if visible else 0.0)


## Pushes the look settings (rebuild = cell layout or reach changed).
func apply(rebuild: bool = false) -> void:
	if _mat == null:
		return
	_param("dark_color", Vector3(dark_color.r, dark_color.g, dark_color.b))
	_param("darkness", darkness * night if visible else 0.0)
	for m in [PROP_MATERIAL, CHARACTER_MATERIAL]:
		m.set_shader_parameter("dk_radius", vision_radius)
		m.set_shader_parameter("dk_squash", squash)
		m.set_shader_parameter("dk_start", start)
		m.set_shader_parameter("dk_density", density)
		m.set_shader_parameter("dk_side_shade", side_shade)
		m.set_shader_parameter("dk_back_shade", back_shade)
	_last_cell = Vector2i(-99999, -99999)       # recalculate the player's light
	_ray_cache.clear()
	if rebuild and not _absorb.is_empty():
		_build_static()
