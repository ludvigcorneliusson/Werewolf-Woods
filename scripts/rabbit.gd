extends CharacterBody2D
## Wild rabbit. Sits and looks around, hops about on its own, and bolts away
## when the settler or the werewolf comes close - so a rabbit suddenly fleeing
## out of the dark can give away that someone is there.
##
## Sprites: assets/characters/rabbit/ (made from H3 videos with
## tools/rabbit_from_video.py): idle stills + hop strips facing right (left is
## mirrored), up (away from the camera) and down (towards it). Origin = feet.
##
## Spawned by the WorldBuilder (Rabbits amount) into World/Rabbits every round,
## or drag assets/characters/rabbit.tscn into World yourself. Tune all rabbits
## on the root of rabbit.tscn.

## Hop speed while wandering (world px per second; the settler walks 120).
@export_range(5.0, 200.0, 1.0) var wander_speed := 38.0
## Hop speed when fleeing (the settler sprints 200).
@export_range(20.0, 400.0, 1.0) var flee_speed := 170.0
## Flees when the settler comes this close.
@export_range(10.0, 600.0, 1.0, "suffix:px") var notice_radius := 110.0
## Flees when the werewolf comes this close (it is bigger and scarier).
@export_range(10.0, 800.0, 1.0, "suffix:px") var werewolf_notice_radius := 170.0
## Keeps fleeing until everyone is at least this far away.
@export_range(50.0, 1200.0, 1.0, "suffix:px") var safe_radius := 280.0
## Seconds it sits still between hops (min, max).
@export var sit_time := Vector2(1.5, 5.0)
## Seconds it hops around before sitting again (min, max).
@export var hop_time := Vector2(0.6, 1.8)
## Rabbits further than this from every character stop thinking (saves CPU).
@export_range(200.0, 5000.0, 10.0, "suffix:px") var wake_radius := 1500.0

## Hop strips: frame count, frame size, foot point in the frame.
const ANIM := {
	"right": {"idle": preload("res://assets/characters/rabbit/rabbit_right.png"), "run": preload("res://assets/characters/rabbit/rabbit_run_right.png"), "frames": 11, "size": Vector2i(21, 16), "foot": Vector2(10, 16)},
	"up": {"idle": preload("res://assets/characters/rabbit/rabbit_up.png"), "run": preload("res://assets/characters/rabbit/rabbit_run_up.png"), "frames": 12, "size": Vector2i(14, 23), "foot": Vector2(7, 23)},
	"down": {"idle": preload("res://assets/characters/rabbit/rabbit_down.png"), "run": preload("res://assets/characters/rabbit/rabbit_run_down.png"), "frames": 11, "size": Vector2i(10, 21), "foot": Vector2(5, 19)},
}
## Seconds per hop at wander speed (the videos hop about twice a second).
const HOP_CYCLE := 0.47
const CHARACTER_MATERIAL := preload("res://assets/characters/character_material.tres")

enum State { SIT, HOP, FLEE }
var state := State.SIT
var facing := Vector2.DOWN
var sprite: AnimatedSprite2D

var _dir := Vector2.ZERO
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _stuck := 0.0
var _last_pos := Vector2.ZERO
var _view := "down"


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0              # nobody bumps into rabbits
	collision_mask = 1               # but they don't hop through trunks, rocks or walls
	var shape := CircleShape2D.new()
	shape.radius = 3.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	var preview := get_node_or_null("Preview")   # editor-only picture in rabbit.tscn
	if preview:
		preview.queue_free()

	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.sprite_frames = _build_frames()
	sprite.material = CHARACTER_MATERIAL         # dark at night, lit by your light / fires
	sprite.light_mask = 4
	add_child(sprite)

	_rng.seed = hash(Vector2i(global_position.round()))
	facing = Vector2.from_angle(_rng.randf() * TAU)
	_sit()
	_last_pos = global_position


func _physics_process(delta: float) -> void:
	var threat := _nearest_threat()
	var t_node: Node2D = threat[0]
	var t_dist: float = threat[1]
	if state != State.FLEE and t_dist > wake_radius:
		return                                      # nobody around: sleep

	if t_node and t_dist < _notice(t_node):
		if state != State.FLEE:
			state = State.FLEE
			_stuck = 0.0
		var away := (global_position - t_node.global_position).normalized()
		# A little zig-zag, like a real rabbit.
		_dir = away.rotated(sin(Time.get_ticks_msec() * 0.006 + _rng.randf() * 0.3) * 0.5)
	elif state == State.FLEE and (t_node == null or t_dist > safe_radius):
		_sit()

	_timer -= delta
	match state:
		State.SIT:
			velocity = Vector2.ZERO
			if _timer <= 0.0:
				_hop()
		State.HOP:
			velocity = _dir * wander_speed
			if _timer <= 0.0:
				_sit()
		State.FLEE:
			velocity = _dir * flee_speed

	velocity.y *= 0.85                              # 3/4 view: depth looks shorter
	move_and_slide()

	# Hopped into a trunk: turn and try another way.
	if state != State.SIT:
		var moved := global_position.distance_to(_last_pos)
		_stuck = _stuck + delta if moved < velocity.length() * delta * 0.3 else 0.0
		if _stuck > 0.2:
			_dir = _dir.rotated(deg_to_rad(70.0 if _rng.randf() < 0.5 else -70.0))
			_stuck = 0.0
	_last_pos = global_position

	if velocity.length() > 1.0:
		facing = velocity
	_update_sprite()


func _sit() -> void:
	state = State.SIT
	_timer = _rng.randf_range(sit_time.x, maxf(sit_time.y, sit_time.x))
	# Sometimes look the other way while sitting.
	if _rng.randf() < 0.4:
		facing = Vector2.from_angle(_rng.randf() * TAU)


func _hop() -> void:
	state = State.HOP
	_timer = _rng.randf_range(hop_time.x, maxf(hop_time.y, hop_time.x))
	_dir = Vector2.from_angle(_rng.randf() * TAU)


## Characters that scare rabbits are in the "scares_rabbits" group (player.gd
## puts the settler and the werewolf there). Returns [node, distance].
func _nearest_threat() -> Array:
	var best: Node2D = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("scares_rabbits"):
		var d := global_position.distance_to((n as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return [best, best_d]


func _notice(n: Node) -> float:
	return werewolf_notice_radius if n.has_signal("caught") else notice_radius


func _update_sprite() -> void:
	# Mostly sideways -> side view (left mirrors right), else up/down.
	var f := facing
	_view = "right" if absf(f.x) > absf(f.y) * 1.2 else ("up" if f.y < 0.0 else "down")
	sprite.flip_h = _view == "right" and f.x < 0.0
	var moving := state != State.SIT
	var anim := ("run_" if moving else "idle_") + _view
	if sprite.animation != anim:
		sprite.play(anim)
	sprite.speed_scale = clampf(velocity.length() / wander_speed, 1.0, 2.2) if moving else 1.0
	var a: Dictionary = ANIM[_view]
	var foot: Vector2 = a.foot
	var size: Vector2i = a.size
	var off := -foot
	if sprite.flip_h:
		off.x = -(size.x - foot.x)
	sprite.offset = off


func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for view: String in ANIM:
		var a: Dictionary = ANIM[view]
		sf.add_animation("idle_" + view)
		sf.add_frame("idle_" + view, a.idle)
		var run := "run_" + view
		sf.add_animation(run)
		sf.set_animation_loop(run, true)
		sf.set_animation_speed(run, a.frames / HOP_CYCLE)
		for i in a.frames:
			var at := AtlasTexture.new()
			at.atlas = a.run
			at.region = Rect2(Vector2(i * a.size.x, 0), Vector2(a.size))
			sf.add_frame(run, at)
	return sf
