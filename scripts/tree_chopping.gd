extends Node
## Chopping trees. The player's axe hit (player.gd: chop_hit at the impact frame)
## comes here: the tree whose trunk is under the blade shakes and throws wood
## chips; after enough hits it falls over away from you and leaves a stump.
## Created by main.gd, which passes in its Chopping settings.

signal tree_felled(tree: Node2D)
## The moment a tree is cut through (before it falls): image = its prop image,
## e.g. "pine_tall.png" (main.gd gives experience for it).
signal tree_cut(tree: Node2D, image: String)
## A stump was chopped out (main.gd gives a little experience).
signal stump_cleared(stump: Node2D)

## Prop images that count as trees (the same names as scripts/darkness.gd).
const LIVING := ["pine_tall.png", "pine_dark.png"]
const DEAD := ["dead_pine.png", "dead_tree.png"]
## Stumps can be chopped out too: they drop a log and some twigs and are gone.
const STUMPS := ["stump.png", "pine_tall_stump.png"]
const STUMP_SCENE := "res://assets/props/stump.tscn"
## Trees that split when felled: the moment it goes, the tree's own picture is
## cut in two at "cut" (art row): the top falls, pivoting on the trunk at the
## cut; the bottom stays and gets the cut face (stump_tex, made by
## tools/make_pine_stump.py from the same art, so nothing jumps). Afterwards the
## tree becomes stump_scene, which has the tree's size/colour/flip settings and
## so rolls the identical look from its map position.
const SPLIT := {
	"pine_tall.png": {"cut": 144, "stump_tex": "res://assets/props/pine_tall_stump.png",
			"stump_scene": "res://assets/props/pine_tall_stump.tscn"},
}
## Stump size per tree image, x the tree's own size, so the stump matches the trunk.
const STUMP_SCALE := {"pine_tall.png": 0.8, "pine_dark.png": 0.45, "dead_pine.png": 0.6, "dead_tree.png": 0.65}
const CHOP_SOUND := "res://assets/sounds/chop.wav"
const FALL_SOUND := "res://assets/sounds/tree_fall.wav"

var player: Node2D
var pickups: Node                 # scripts/pickups.gd: felled trees drop logs and twigs
## What a felled tree drops: [logs, twigs min, twigs max] per tree image.
const DROPS := {"pine_tall.png": [2, 2, 3], "pine_dark.png": [1, 1, 2],
		"dead_pine.png": [1, 2, 4], "dead_tree.png": [1, 2, 4]}
var hits_to_fell := 4             # living pines
var dead_hits_to_fell := 2        # dead trees are dry and brittle
var stump_hits := 3               # hits to chop out a stump
var hit_radius := 13.0            # world px around the blade
var damage := 1.0                 # how many "hits" one swing counts as
var hits_saved := 0               # Heavy Blade: every tree and stump needs this many fewer hits (min 1)
var volume_db := -4.0
var fall_time := 1.1              # seconds for a tree to topple
var face_delay := 0.3             # split trees: seconds into the fall before the cut face shows

var _hits := {}                   # tree instance id -> hits so far
var _chop_sound: AudioStream
var _fall_sound: AudioStream


func _ready() -> void:
	if ResourceLoader.exists(CHOP_SOUND):
		_chop_sound = load(CHOP_SOUND)
	if ResourceLoader.exists(FALL_SOUND):
		_fall_sound = load(FALL_SOUND)


## player.chop_hit -> here.
func on_chop_hit(point: Vector2, side: int) -> void:
	var tree := _tree_at(point)
	if tree == null:
		return
	var id := tree.get_instance_id()
	_hits[id] = float(_hits.get(id, 0.0)) + damage
	_sound(_chop_sound, point, randf_range(0.92, 1.08))
	_chips(point, side)
	var img := _image(tree)
	if img in STUMPS:
		if _hits[id] >= maxi(stump_hits - hits_saved, 1) - 0.001:
			_hits.erase(id)
			_clear_stump(tree)
		else:
			_shake(tree)
		return
	var needed := maxi((dead_hits_to_fell if img in DEAD else hits_to_fell) - hits_saved, 1)
	if _hits[id] >= needed - 0.001:
		_hits.erase(id)
		tree_cut.emit(tree, _image(tree))
		_fell(tree, side)
	else:
		_shake(tree)


## The tree whose trunk (its collision Body) is under the blade, or null.
func _tree_at(point: Vector2) -> Node2D:
	var shape := CircleShape2D.new()
	shape.radius = hit_radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, point)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	if player is CollisionObject2D:
		q.exclude = [(player as CollisionObject2D).get_rid()]
	var best: Node2D = null
	var best_d := INF
	for r in player.get_world_2d().direct_space_state.intersect_shape(q, 16):
		var body := r.collider as Node
		if body == null or body.name != "Body":
			continue
		var prop := body.get_parent() as Node2D
		if prop == null or prop.has_meta("felling"):
			continue
		var img := _image(prop)
		if not (img in LIVING or img in DEAD or img in STUMPS):
			continue
		var d := prop.global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = prop
	return best


func _image(prop: Node) -> String:
	if prop.has_meta("tree_image"):
		return prop.get_meta("tree_image")
	var sprite := prop.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return ""
	return sprite.texture.resource_path.get_file()


## A quick side-to-side shudder of the tree art.
func _shake(tree: Node2D) -> void:
	var sprite := tree.get_node_or_null("Sprite") as Node2D
	if sprite == null:
		return
	var px := 1.5 / maxf(tree.scale.x, 0.01)        # sprite px per world px
	var t := tree.create_tween()
	for x in [2.0, -2.0, 1.2, -0.6, 0.0]:
		t.tween_property(sprite, "position:x", x * px, 0.04)


## Wood chips flying off the trunk, away from the axe.
func _chips(point: Vector2, side: int) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 9
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector2(-side, -1.2).normalized()
	p.spread = 40.0
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 110.0
	p.gravity = Vector2(0, 380)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.86, 0.68, 0.42)
	p.hue_variation_min = -0.03
	p.hue_variation_max = 0.03
	p.z_index = 1
	p.global_position = point + Vector2(0, -8)
	player.get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)


## Topples the tree away from you, then leaves a stump where it stood.
func _fell(tree: Node2D, side: int) -> void:
	tree.set_meta("felling", true)
	tree.set_meta("tree_image", _image(tree))       # the split swaps the textures below
	var sprite := tree.get_node_or_null("Sprite") as Sprite2D
	var spec: Dictionary = SPLIT.get(_image(tree), {})
	if not spec.is_empty() and sprite:
		_split(tree, sprite, spec)        # the stump (and its collision) stays
	else:
		# You can walk (and see) through it straight away.
		for part in ["Body", "VisionBlocker"]:
			var n := tree.get_node_or_null(part)
			if n:
				n.queue_free()
	if sprite:
		var t := tree.create_tween()
		# A slow lean at first, then it goes: rotation around the foot (the origin).
		t.tween_property(sprite, "rotation", side * PI * 0.47, fall_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(sprite, "rotation", side * PI * 0.44, 0.08)      # small bounce on landing
		t.tween_property(sprite, "rotation", side * PI * 0.47, 0.1)
		# Thud as it hits the ground.
		var land := tree.global_position + Vector2(side * _length(tree) * 0.5, -4.0)
		t.tween_callback(func(): _sound(_fall_sound, land, randf_range(0.95, 1.05)))
		t.tween_callback(_dust.bind(land))
		t.tween_callback(_drop_wood.bind(tree, side))
		t.tween_interval(0.25)
		t.tween_callback(_replace_with_stump.bind(tree))
	else:
		_sound(_fall_sound, tree.global_position, randf_range(0.95, 1.05))
		_replace_with_stump(tree)


## Cuts the tree's picture in two at the cut row: the top (pivoting at the cut,
## so it can fall) and the stump below (same pixels, then the cut face).
## Both halves are full-size copies of the tree image with the other half
## cleared, drawn exactly where the whole tree was: with the project's pixel
## snapping on, that's what keeps the swap invisible.
func _split(tree: Node2D, sprite: Sprite2D, spec: Dictionary) -> void:
	var cut: int = spec.cut
	var halves := _halves(sprite.texture, cut)
	var whole_offset := sprite.offset
	var stump := Sprite2D.new()
	stump.name = "Stump"
	stump.texture = halves[1]
	stump.centered = false
	stump.offset = whole_offset
	stump.flip_h = sprite.flip_h
	stump.material = sprite.material
	stump.light_mask = sprite.light_mask
	stump.texture_filter = sprite.texture_filter
	stump.self_modulate = Color(sprite.self_modulate, 0.5)     # same colour, no sway
	tree.add_child(stump)
	tree.move_child(stump, sprite.get_index())                 # behind the top
	# Top: pivots on the trunk at the cut. The pivot is put on a whole screen
	# pixel (world px x the tree's size) so pixel snapping doesn't nudge it.
	var top_tex: Texture2D = halves[0]
	sprite.texture = top_tex
	var size := top_tex.get_size()
	var s := absf(tree.global_scale.y)
	var pivot := Vector2(whole_offset.x + size.x / 2.0, whole_offset.y + cut)
	pivot = (pivot * s).round() / s
	sprite.position = pivot
	sprite.offset = whole_offset - pivot
	# Once the top has visibly tipped away from the stump, show the cut face.
	var stump_tex := load(spec.stump_tex) as Texture2D
	if stump_tex:
		get_tree().create_timer(face_delay, false).timeout.connect(func():
			if is_instance_valid(stump):
				stump.texture = stump_tex)


var _halves_cache := {}

## [top, bottom] textures: the tree image with the rows below / above the cut cleared.
func _halves(tex: Texture2D, cut: int) -> Array:
	var key := "%s:%d" % [tex.resource_path, cut]
	if not _halves_cache.has(key):
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var top := img.duplicate() as Image
		var bottom := img.duplicate() as Image
		var w := img.get_width()
		var h := img.get_height()
		top.fill_rect(Rect2i(0, cut, w, h - cut), Color(0, 0, 0, 0))
		bottom.fill_rect(Rect2i(0, 0, w, cut), Color(0, 0, 0, 0))
		_halves_cache[key] = [ImageTexture.create_from_image(top), ImageTexture.create_from_image(bottom)]
	return _halves_cache[key]


## Rough length of the tree in world px (for where the dust lands).
func _length(tree: Node2D) -> float:
	var sprite := tree.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return 100.0
	return sprite.texture.get_height() * tree.scale.y


## Logs and twigs scattered along where the trunk came down.
func _drop_wood(tree: Node2D, side: int) -> void:
	if pickups == null or not is_instance_valid(tree):
		return
	var d: Array = DROPS.get(_image(tree), [1, 1, 2])
	var base := tree.global_position
	var length := _length(tree)
	var items := []
	for i in d[0]:
		items.append("log")
	for i in randi_range(d[1], d[2]):
		items.append("twig")
	for i in items.size():
		# Logs from the trunk end, twigs further out where the branches were.
		var f := randf_range(0.18, 0.45) if items[i] == "log" else randf_range(0.4, 0.9)
		var at := base + Vector2(side * length * f, randf_range(-10.0, 14.0))
		pickups.spawn_drop(items[i], at, base + Vector2(side * length * f, -10.0))


## Digs a stump out: a puff of dust, a log and twigs, and the spot is clear.
func _clear_stump(stump: Node2D) -> void:
	stump.set_meta("felling", true)
	var at := stump.global_position
	_sound(_fall_sound, at, randf_range(1.25, 1.4))           # a shorter, higher thud
	_dust(at + Vector2(0, -4), 22.0)
	if pickups:
		pickups.spawn_drop("log", at + Vector2(randf_range(-14, 14), randf_range(4, 12)), at + Vector2(0, -10))
		for i in randi_range(1, 2):
			pickups.spawn_drop("twig", at + Vector2(randf_range(-26, 26), randf_range(-6, 16)), at + Vector2(0, -10))
	# Sink and vanish.
	var t := stump.create_tween()
	t.tween_property(stump, "scale:y", 0.0, 0.18).set_ease(Tween.EASE_IN)
	t.tween_callback(_remove_prop.bind(stump))


func _remove_prop(n: Node2D) -> void:
	if not is_instance_valid(n):
		return
	var layer := n.get_parent() as TileMapLayer
	if layer and n.position == layer.map_to_local(layer.local_to_map(n.position)):
		layer.erase_cell(layer.local_to_map(n.position))
	else:
		n.queue_free()
	stump_cleared.emit(n)


func _dust(at: Vector2, width := 60.0) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width, 6)
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 45.0
	p.gravity = Vector2(0, 20)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.55, 0.42, 0.55))
	ramp.set_color(1, Color(0.62, 0.55, 0.42, 0.0))
	p.color_ramp = ramp
	p.z_index = 1
	p.global_position = at
	player.get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4, false).timeout.connect(p.queue_free)


func _replace_with_stump(tree: Node2D) -> void:
	if not is_instance_valid(tree):
		return
	var parent := tree.get_parent()
	var layer := parent as TileMapLayer
	var spec: Dictionary = SPLIT.get(_image(tree), {})
	var split := not spec.is_empty()
	var scene_path: String = spec.stump_scene if split else STUMP_SCENE
	var stump_scale := tree.scale.x * float(STUMP_SCALE.get(_image(tree), 0.7))
	var at := tree.position
	var stump_id := _scene_tile(layer, scene_path) if layer else -1
	if layer and stump_id >= 0 and tree.position == layer.map_to_local(layer.local_to_map(tree.position)):
		# Painted/generated props are scene tiles: swap the tile.
		var cell := layer.local_to_map(tree.position)
		layer.erase_cell(cell)
		layer.set_cell(cell, 0, Vector2i.ZERO, stump_id)
		if not split:
			_size_stump.call_deferred(layer, at, stump_scale)
	else:
		# A scene placed by hand: put a stump node in its place.
		var stump := (load(scene_path) as PackedScene).instantiate() as Node2D
		stump.position = tree.position
		parent.add_child(stump)
		if not split:
			stump.scale = Vector2(stump_scale, stump_scale)
		tree.queue_free()
	tree_felled.emit(tree)


## The new stump tile shows up a moment later; size it like the felled trunk.
func _size_stump(layer: TileMapLayer, at: Vector2, s: float) -> void:
	await get_tree().process_frame
	if not is_instance_valid(layer):
		return
	for c in layer.get_children():
		if c is Node2D and c.position == at and _image(c) == "stump.png":
			c.scale = Vector2(s, s)
			return


## Scene-tile id of a scene in the layer's tileset (source 0), or -1.
func _scene_tile(layer: TileMapLayer, path: String) -> int:
	if layer.tile_set == null or not layer.tile_set.has_source(0):
		return -1
	var src := layer.tile_set.get_source(0) as TileSetScenesCollectionSource
	if src == null:
		return -1
	for i in src.get_scene_tiles_count():
		var id := src.get_scene_tile_id(i)
		var scene := src.get_scene_tile_scene(id)
		if scene and scene.resource_path == path:
			return id
	return -1


func _sound(stream: AudioStream, at: Vector2, pitch: float) -> void:
	if stream == null:
		return
	var a := AudioStreamPlayer2D.new()
	a.stream = stream
	a.volume_db = volume_db
	a.pitch_scale = pitch
	a.max_distance = 900.0
	a.global_position = at
	player.get_parent().add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
