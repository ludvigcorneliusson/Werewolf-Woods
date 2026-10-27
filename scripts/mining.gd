extends Node
## Mining ore nodes with the pickaxe: the same hit mechanic as chopping trees
## (scripts/tree_chopping.gd). The player's pickaxe hit (player.gd: mine_hit)
## comes here: the node under the pick shakes and throws rock chips; after
## enough hits it crumbles into ore you can pick up, and the spot is clear.
## Created by main.gd, which passes in its Mining settings.

## A node broke (main.gd gives experience and rebuilds the night darkness).
signal node_broken(node: Node2D, image: String)

## Minable prop images -> kind (sets how many hits: hits_to_break[kind]), what
## they drop ("drops": [item id, min, max] each) and the colours of the chips.
## Copper deposits give ore plus a little stone; the small one about half.
const STONE_CHIPS := {"chip": Color(0.62, 0.5, 0.47), "ore_chip": Color(0.8, 0.66, 0.6)}
const NODES := {
	"copper_node.png": {"kind": "ore", "drops": [["copper_ore", 2, 3], ["stone", 1, 2]],
		"chip": Color(0.62, 0.57, 0.53), "ore_chip": Color(0.88, 0.45, 0.22)},
	"copper_node_small.png": {"kind": "ore_small", "drops": [["copper_ore", 1, 2], ["stone", 0, 1]],
		"chip": Color(0.62, 0.57, 0.53), "ore_chip": Color(0.88, 0.45, 0.22)},
	"stone_node_a.png": {"kind": "stone", "drops": [["stone", 3, 5]],
		"chip": STONE_CHIPS.chip, "ore_chip": STONE_CHIPS.ore_chip},
	"stone_node_b.png": {"kind": "stone", "drops": [["stone", 3, 4]],
		"chip": STONE_CHIPS.chip, "ore_chip": STONE_CHIPS.ore_chip},
	"stone_node_c.png": {"kind": "stone", "drops": [["stone", 2, 3]],
		"chip": STONE_CHIPS.chip, "ore_chip": STONE_CHIPS.ore_chip},
}
const HIT_SOUND := "res://assets/sounds/mine_hit.wav"
const BREAK_SOUND := "res://assets/sounds/rock_break.wav"

var player: Node2D
var pickups: Node                 # scripts/pickups.gd
var hits_to_break := {"ore": 5, "ore_small": 3, "stone": 4}   # pickaxe hits per node, by kind
var hit_radius := 13.0            # world px around the pick
var volume_db := -4.0

var _hits := {}                   # node instance id -> hits so far
var _hit_sound: AudioStream
var _break_sound: AudioStream


func _ready() -> void:
	if ResourceLoader.exists(HIT_SOUND):
		_hit_sound = load(HIT_SOUND)
	if ResourceLoader.exists(BREAK_SOUND):
		_break_sound = load(BREAK_SOUND)


## player.mine_hit -> here.
func on_mine_hit(point: Vector2, side: int) -> void:
	var node := _node_at(point)
	if node == null:
		return
	var spec: Dictionary = NODES[_image(node)]
	var id := node.get_instance_id()
	_hits[id] = int(_hits.get(id, 0)) + 1
	_sound(_hit_sound, point, randf_range(0.93, 1.08))
	_chips(point, side, spec)
	if _hits[id] >= maxi(int(hits_to_break.get(spec.kind, 5)), 1):
		_hits.erase(id)
		_break(node, spec)
	else:
		_shake(node)


## The ore node whose collision Body is under the pick, or null.
func _node_at(point: Vector2) -> Node2D:
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
		if prop == null or prop.has_meta("breaking") or not NODES.has(_image(prop)):
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


## A short, stiff shudder (rock doesn't sway like a tree).
func _shake(node: Node2D) -> void:
	var sprite := node.get_node_or_null("Sprite") as Node2D
	if sprite == null:
		return
	var t := node.create_tween()
	for x in [1.0, -1.0, 1.0, 0.0]:
		t.tween_property(sprite, "position:x", x, 0.035)


## Grey rock chips and a few orange ore flecks, away from the pick.
func _chips(point: Vector2, side: int, spec: Dictionary) -> void:
	for kind in [[spec.chip, 7, 1.0, 2.0], [spec.ore_chip, 3, 1.0, 1.5]]:
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = kind[1]
		p.lifetime = 0.5
		p.explosiveness = 1.0
		p.direction = Vector2(-side, -1.4).normalized()
		p.spread = 45.0
		p.initial_velocity_min = 60.0
		p.initial_velocity_max = 120.0
		p.gravity = Vector2(0, 420)
		p.scale_amount_min = kind[2]
		p.scale_amount_max = kind[3]
		p.color = kind[0]
		p.z_index = 1
		p.global_position = point + Vector2(0, -10)
		player.get_parent().add_child(p)
		p.emitting = true
		get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)


## Crumbles: dust, rubble sound, ore pops out around it, the rock sinks away.
func _break(node: Node2D, spec: Dictionary) -> void:
	node.set_meta("breaking", true)
	var at := node.global_position
	var image := _image(node)
	_sound(_break_sound, at, randf_range(0.95, 1.05))
	_dust(at + Vector2(0, -6))
	# Solid ground straight away (you can walk and see through where it stood).
	for part in ["Body", "VisionBlocker"]:
		var n := node.get_node_or_null(part)
		if n:
			n.queue_free()
	if pickups:
		var spread: float = {"ore": 30.0, "ore_small": 20.0}.get(spec.kind, 40.0)
		for d in spec.drops:
			for i in randi_range(d[1], d[2]):
				var to := at + Vector2(randf_range(-spread, spread), randf_range(-4, 16))
				pickups.spawn_drop(d[0], to, at + Vector2(0, -16))
	var sprite := node.get_node_or_null("Sprite") as Node2D
	var t := node.create_tween()
	if sprite:
		t.tween_property(sprite, "scale:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
	t.tween_callback(_remove.bind(node, image))


func _remove(node: Node2D, image: String) -> void:
	if not is_instance_valid(node):
		return
	var layer := node.get_parent() as TileMapLayer
	if layer and node.position == layer.map_to_local(layer.local_to_map(node.position)):
		layer.erase_cell(layer.local_to_map(node.position))
	else:
		node.queue_free()
	node_broken.emit(node, image)


func _dust(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 26
	p.lifetime = 0.8
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(26, 8)
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 15.0
	p.initial_velocity_max = 45.0
	p.gravity = Vector2(0, 30)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.57, 0.53, 0.6))
	ramp.set_color(1, Color(0.6, 0.57, 0.53, 0.0))
	p.color_ramp = ramp
	p.z_index = 1
	p.global_position = at
	player.get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4, false).timeout.connect(p.queue_free)


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
