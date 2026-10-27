extends Node
## Animal eyes in the trees at night: now and then a pair of tiny glowing eyes
## peers out of a pine canopy (rarely two or three pairs in one tree). They fade
## in as night falls, blink, and shut when you come close. A few world pixels
## each with a faint glow; drawn above the night darkness so you see them in the
## black. Which trees get eyes comes from the map seed (same for every player).
## Created by main.gd, which passes its Night Eyes settings and the night amount.

const VARIED_MATERIAL := preload("res://assets/props/varied_material.tres")
const LIVING := ["pine_tall.png", "pine_dark.png"]
const COLORS := [Color(1.0, 0.78, 0.3), Color(0.78, 1.0, 0.4), Color(0.95, 0.95, 0.7), Color(1.0, 0.55, 0.25)]

var tree_share := 0.01            # share of living pines that get eyes
var extra_pair_chance := 0.3      # chance of each further pair in the same tree (max 3)
var glow := 0.3                   # glow strength around each eye (0 = none)
var close_distance := 150.0       # eyes shut when a character is this close (world px)
var night := 0.0                  # 0 = day .. 1 = full night (main.gd)
var player: Node2D

var _eyes: Array[Node2D] = []
var _alpha_cache := {}            # texture path -> Image (to find solid canopy pixels)


## Picks the trees (after the forest's scene tiles exist) and gives them eyes.
func setup(props: TileMapLayer, seed_value: int) -> void:
	for e in _eyes:
		if is_instance_valid(e):
			e.queue_free()
	_eyes.clear()
	if props == null:
		return
	# Scene tiles are instanced a moment after the map is built.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(props):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	for tree in props.get_children():
		var sprite := tree.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null or not sprite.texture.resource_path.get_file() in LIVING:
			continue
		if rng.randf() >= tree_share:
			continue
		var pairs := 1
		while pairs < 3 and rng.randf() < extra_pair_chance:
			pairs += 1
		var spots := []
		for i in pairs:
			var s = _spot(sprite, rng, spots)
			if s != null:
				spots.append(s)
		if spots.is_empty():
			continue
		var e := Eyes.new()
		e.manager = self
		e.tree = tree
		e.sprite = sprite
		for s in spots:
			e.add_pair(s, COLORS[rng.randi() % COLORS.size()], rng)
		tree.add_child(e)
		_eyes.append(e)


## A spot inside the canopy (sprite pixels) where both eyes sit on solid,
## darkish needles - not on the trunk, not in thin air. null if none found.
func _spot(sprite: Sprite2D, rng: RandomNumberGenerator, taken: Array) -> Variant:
	var img := _image(sprite.texture)
	if img == null:
		return null
	var w := img.get_width()
	var h := img.get_height()
	for attempt in 40:
		var x := rng.randi_range(int(w * 0.28), int(w * 0.68))
		var y := rng.randi_range(int(h * 0.25), int(h * 0.68))
		var ok := true
		for t in taken:
			if Vector2(x, y).distance_to(t) < 10:
				ok = false
		for dx in range(-2, 6):
			for dy in range(-2, 3):
				var c := img.get_pixel(clampi(x + dx, 0, w - 1), clampi(y + dy, 0, h - 1))
				if c.a < 0.9 or c.get_luminance() > 0.45:
					ok = false
		if ok:
			return Vector2(x, y)
	return null


func _image(tex: Texture2D) -> Image:
	var key := tex.resource_path
	if not _alpha_cache.has(key):
		var img := tex.get_image()
		if img and img.is_compressed():
			img.decompress()
		_alpha_cache[key] = img
	return _alpha_cache[key]


## Eyes in one tree: up to three pairs, drawn in world pixels above the canopy.
class Eyes extends Node2D:
	var manager: Node
	var tree: Node2D
	var sprite: Sprite2D
	var pairs := []               # [{at (sprite px), color, blink_in, blink, open}]
	var _shown := 0.0

	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD      # glow adds light to the dark
		material = m                                           # drawn with its tree (y-sorted), so trees in front still cover it

	func add_pair(at: Vector2, color: Color, rng: RandomNumberGenerator) -> void:
		pairs.append({"at": at, "color": color, "blink_in": rng.randf_range(0.5, 5.0),
				"blink": 0.0, "open": 1.0, "speed": rng.randf_range(0.8, 1.3)})

	func _process(delta: float) -> void:
		if not is_instance_valid(tree) or tree.has_meta("felling"):
			queue_free()                                       # tree coming down: the animal is gone
			return
		var target: float = manager.night
		var p: Node2D = manager.player
		if is_instance_valid(p) and p.global_position.distance_to(tree.global_position) < manager.close_distance:
			target = 0.0                                       # you're right under it: eyes shut
		_shown = move_toward(_shown, target, delta * (0.5 if target > _shown else 3.0))
		visible = _shown > 0.01
		if not visible:
			return
		for pr in pairs:
			pr.blink_in -= delta * pr.speed
			if pr.blink_in <= 0.0:
				pr.blink = 0.16                                # one blink
				pr.blink_in = randf_range(2.0, 7.0)
				if randf() < 0.2:
					pr.blink_in = 0.3                          # sometimes a double blink
			pr.blink = maxf(pr.blink - delta, 0.0)
			pr.open = 0.0 if pr.blink > 0.0 else 1.0
		_follow_wind()
		queue_redraw()

	## Sit where the canopy is now: the prop shader bends trees in the wind
	## (top moves most), so move the eyes the same way.
	func _follow_wind() -> void:
		var sc := absf(tree.scale.x)
		scale = Vector2.ONE / maxf(sc, 0.01)                # draw in world pixels
		var sway := clampf((sprite.self_modulate.a - 0.5) * 2.0, 0.0, 1.0)
		var px := 0.0
		if sway > 0.0:
			var m := VARIED_MATERIAL
			var dir: Vector2 = m.get_shader_parameter("wind_dir") if m.get_shader_parameter("wind_dir") != null else Vector2.RIGHT
			dir = dir.normalized()
			var strength: float = m.get_shader_parameter("wind_strength") if m.get_shader_parameter("wind_strength") != null else 0.0
			var lean: float = m.get_shader_parameter("wind_lean") if m.get_shader_parameter("wind_lean") != null else 0.0
			var speed: float = m.get_shader_parameter("wind_speed") if m.get_shader_parameter("wind_speed") != null else 0.0
			var spread: float = m.get_shader_parameter("wave_spread") if m.get_shader_parameter("wave_spread") != null else 0.0
			var t := Time.get_ticks_msec() / 1000.0
			var phase := tree.global_position.dot(dir) * spread * TAU
			px = sway * (lean * signf(dir.x + 0.0001) + strength * sin(t * speed * TAU - phase))
		set_meta("wind_px", px)

	func _draw() -> void:
		var tex_size := sprite.texture.get_size()
		var sc := absf(tree.scale.x)
		var px: float = get_meta("wind_px", 0.0)
		for pr in pairs:
			var at: Vector2 = pr.at
			if sprite.flip_h:
				at.x = tex_size.x - at.x - 4.0
			# Sprite pixels -> this node's world-pixel space; plus the wind bend
			# at that height (0 at the sprite's bottom, full at its top).
			var local := (sprite.offset + at) * sc
			local.x += px * (1.0 - at.y / tex_size.y)
			local = local.round()
			var col: Color = pr.color
			var a: float = _shown
			var g: float = manager.glow
			for k in [Vector2(0, 0), Vector2(4, 0)]:          # two eyes, 4 px apart
				var c: Vector2 = local + k + Vector2(1, 0.5)
				if g > 0.0:
					draw_circle(c, 3.5, Color(col, g * 0.35 * a))
					draw_circle(c, 2.0, Color(col, g * 0.6 * a))
				if pr.open > 0.0:
					draw_rect(Rect2(local + k, Vector2(2, 1)), Color(col, 0.95 * a))
				else:
					draw_rect(Rect2(local + k + Vector2(0, 0), Vector2(2, 1)), Color(col, 0.08 * a))
