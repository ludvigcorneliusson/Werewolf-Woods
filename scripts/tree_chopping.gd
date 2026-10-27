extends Node
## Chopping trees. The player's axe hit (player.gd: chop_hit at the impact frame)
## comes here: the tree whose trunk is under the blade shakes and throws wood
## chips; after enough hits it falls over away from you and leaves a stump.
## Created by main.gd, which passes in its Chopping settings.

signal tree_felled(tree: Node2D)

## Prop images that count as trees (the same names as scripts/darkness.gd).
const LIVING := ["pine_tall.png", "pine_dark.png"]
const DEAD := ["dead_pine.png", "dead_tree.png"]
const STUMP_SCENE := "res://assets/props/stump.tscn"
## Stump size per tree image, x the tree's own size, so the stump matches the trunk.
const STUMP_SCALE := {"pine_tall.png": 0.8, "pine_dark.png": 0.45, "dead_pine.png": 0.6, "dead_tree.png": 0.65}
const CHOP_SOUND := "res://assets/sounds/chop.wav"
const FALL_SOUND := "res://assets/sounds/tree_fall.wav"

var player: Node2D
var hits_to_fell := 4             # living pines
var dead_hits_to_fell := 2        # dead trees are dry and brittle
var hit_radius := 13.0            # world px around the blade
var volume_db := -4.0
var fall_time := 1.1              # seconds for a tree to topple

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
	_hits[id] = int(_hits.get(id, 0)) + 1
	_sound(_chop_sound, point, randf_range(0.92, 1.08))
	_chips(point, side)
	var needed := dead_hits_to_fell if _image(tree) in DEAD else hits_to_fell
	if _hits[id] >= needed:
		_hits.erase(id)
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
		if not (img in LIVING or img in DEAD):
			continue
		var d := prop.global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = prop
	return best


func _image(prop: Node) -> String:
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
	# You can walk (and see) through it straight away.
	for part in ["Body", "VisionBlocker"]:
		var n := tree.get_node_or_null(part)
		if n:
			n.queue_free()
	var sprite := tree.get_node_or_null("Sprite") as Node2D
	_sound(_fall_sound, tree.global_position, randf_range(0.95, 1.05))
	if sprite:
		var t := tree.create_tween()
		# A slow lean at first, then it goes: rotation around the foot (the origin).
		t.tween_property(sprite, "rotation", side * PI * 0.47, fall_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_property(sprite, "rotation", side * PI * 0.44, 0.08)      # small bounce on landing
		t.tween_property(sprite, "rotation", side * PI * 0.47, 0.1)
		t.tween_callback(_dust.bind(tree.global_position + Vector2(side * _length(tree) * 0.5, -4.0)))
		t.tween_interval(0.25)
		t.tween_callback(_replace_with_stump.bind(tree))
	else:
		_replace_with_stump(tree)


## Rough length of the tree in world px (for where the dust lands).
func _length(tree: Node2D) -> float:
	var sprite := tree.get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		return 100.0
	return sprite.texture.get_height() * tree.scale.y


func _dust(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(60, 6)
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
	var stump_scale := tree.scale.x * float(STUMP_SCALE.get(_image(tree), 0.7))
	var at := tree.position
	var stump_id := _scene_tile(layer, STUMP_SCENE) if layer else -1
	if layer and stump_id >= 0 and tree.position == layer.map_to_local(layer.local_to_map(tree.position)):
		# Painted/generated props are scene tiles: swap the tile.
		var cell := layer.local_to_map(tree.position)
		layer.erase_cell(cell)
		layer.set_cell(cell, 0, Vector2i.ZERO, stump_id)
		_size_stump.call_deferred(layer, at, stump_scale)
	else:
		# A scene placed by hand: put a stump node in its place.
		var stump := (load(STUMP_SCENE) as PackedScene).instantiate() as Node2D
		stump.position = tree.position
		parent.add_child(stump)
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
