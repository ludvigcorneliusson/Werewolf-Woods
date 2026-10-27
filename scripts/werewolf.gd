extends "res://scripts/player.gd"
## The werewolf. Uses the settler's movement/camera code (player.gd) with its own
## sprites: idles facing right/up/down (left mirrors right) and runs right
## (gallop, left mirrored), up-right and down-right (diagonals; the left ones
## mirrored), up (away from the camera) and down (towards it): all 8 directions.
##
## Playable (start menu -> Werewolf), or as an AI hunter when you play the human:
## it wanders the forest, chases when it senses you, searches where it lost you,
## and catches you on contact.

## Fired each time it lands a bite on the human (main.gd takes health off and
## ends the round when it reaches 0). After a bite it backs off for a moment.
signal caught(target: Node2D)

const W_RIGHT := preload("res://assets/characters/werewolf_right.png")
const W_UP := preload("res://assets/characters/werewolf_up.png")
const W_DOWN := preload("res://assets/characters/werewolf_down.png")
## Run strips: frames, frame size, offset that puts the feet on the origin, and
## "cycle" = seconds per run cycle at walking speed (sprint plays faster).
## "steps" = gallop beats in the cycle (hind paws, then front paws) for the
## footstep sound. The werewolf is ~73 px tall (1.7x the settler).
const W_RUN := {
	"right": {"tex": preload("res://assets/characters/werewolf_run_right.png"), "frames": 12, "size": Vector2i(134, 66), "offset": Vector2(-66, -59), "cycle": 0.55, "steps": [0.25, 0.8]},
	"up": {"tex": preload("res://assets/characters/werewolf_run_up.png"), "frames": 12, "size": Vector2i(76, 77), "offset": Vector2(-37, -67), "cycle": 0.55, "steps": [0.38, 0.8]},
	"down": {"tex": preload("res://assets/characters/werewolf_run_down.png"), "frames": 13, "size": Vector2i(64, 92), "offset": Vector2(-31, -79), "cycle": 0.55, "steps": [0.0, 0.5]},
	"up_right": {"tex": preload("res://assets/characters/werewolf_run_up_right.png"), "frames": 13, "size": Vector2i(115, 82), "offset": Vector2(-54, -70), "cycle": 0.55, "steps": [0.25, 0.8]},
	"down_right": {"tex": preload("res://assets/characters/werewolf_run_down_right.png"), "frames": 14, "size": Vector2i(122, 90), "offset": Vector2(-58, -76), "cycle": 0.55, "steps": [0.25, 0.8]},
}

# --- AI (used when ai_controlled) ----------------------------------------------
var target: Node2D                 # the human to hunt
var map_rect := Rect2()            # where to wander
var sense_radius := 320.0          # starts chasing within this distance (world px)
var lose_radius := 560.0           # gives up the chase beyond this
var catch_radius := 20.0
var search_time := 7.0             # seconds spent searching where it lost you
var attack_interval := 1.2         # seconds between bites
var _attack_left := 0.0
var _recoil_left := 0.0

enum State { WANDER, CHASE, SEARCH }
var state := State.WANDER
var _goal := Vector2.ZERO
var _goal_timer := 0.0
var _last_seen := Vector2.ZERO
var _search_left := 0.0
var _stuck_timer := 0.0
var _detour := Vector2.ZERO
var _detour_left := 0.0
var _last_pos := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _caught := false


func _init() -> void:
	walk_speed = 140.0
	sprint_speed = 215.0
	body_radius = 10.0
	shadow_radius = 17.0
	see_through_size = Vector2(19, 38)
	# Same step sound, a bit louder and carrying further (you hear it before you see it).
	step_volume_db = -3.0
	step_hear_distance = 900.0


func _ready() -> void:
	super._ready()
	_rng.randomize()
	_last_pos = global_position
	_pick_wander_goal()


func _physics_process(delta: float) -> void:
	if ai_controlled:
		_think(delta)
	super._physics_process(delta)


# --- animation ----------------------------------------------------------------

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for view: String in ["right", "up", "down"]:
		var tex: Texture2D = {"right": W_RIGHT, "up": W_UP, "down": W_DOWN}[view]
		var idle := "idle_" + view
		sf.add_animation(idle)
		sf.add_frame(idle, tex)
		_offsets[idle] = Vector2(-tex.get_width() / 2, -tex.get_height() + 1)
	for view: String in W_RUN:
		var r: Dictionary = W_RUN[view]
		var run := "run_" + view
		sf.add_animation(run)
		sf.set_animation_loop(run, true)
		sf.set_animation_speed(run, r.frames / r.cycle)
		_steps[run] = r.get("steps", DEFAULT_STEPS)
		for i in r.frames:
			var at := AtlasTexture.new()
			at.atlas = r.tex
			at.region = Rect2(Vector2(i * r.size.x, 0), Vector2(r.size))
			sf.add_frame(run, at)
		_offsets[run] = r.offset
	return sf


func _update_sprite() -> void:
	# 8 directions (sector 0 = right, clockwise). Diagonal runs while moving;
	# when standing still on a diagonal the side idle is used.
	var sector := posmod(int(round(facing.angle() / (PI / 4.0))), 8)
	var view: String = ["right", "down_right", "down", "down_right", "right", "up_right", "up", "up_right"][sector]
	sprite.flip_h = sector >= 3 and sector <= 5
	if view.ends_with("_right") and not _moving:
		view = "right"
	# See-through area follows the pose: long and low when galloping sideways.
	see_through_size = Vector2(46, 26) if (_moving and view in ["right", "up_right", "down_right"]) else Vector2(19, 38)
	if _moving:
		_play("run_" + view)
		sprite.speed_scale = _speed / walk_speed
	else:
		_play("idle_" + view)
		sprite.speed_scale = 1.0
	_apply_flip_offset()


# --- AI -----------------------------------------------------------------------

func _think(delta: float) -> void:
	ai_sprint = false
	if _caught or not is_instance_valid(target):
		ai_dir = Vector2.ZERO
		return
	var to_t := target.global_position - global_position
	var dist := to_t.length()
	_attack_left -= delta
	_recoil_left -= delta

	if _recoil_left > 0.0:
		# Just bit: back off a little before going again.
		ai_dir = -to_t.normalized() * 0.6
		return
	if dist < catch_radius and _attack_left <= 0.0:
		_attack_left = attack_interval
		_recoil_left = 0.45
		ai_dir = Vector2.ZERO
		caught.emit(target)
		return

	match state:
		State.WANDER:
			if dist < sense_radius:
				state = State.CHASE
		State.CHASE:
			if dist > lose_radius:
				state = State.SEARCH
				_search_left = search_time
			else:
				_last_seen = target.global_position
		State.SEARCH:
			_search_left -= delta
			if dist < sense_radius:
				state = State.CHASE
			elif _search_left <= 0.0:
				state = State.WANDER
				_pick_wander_goal()

	var goal := _goal
	match state:
		State.CHASE:
			goal = target.global_position
			ai_sprint = true
		State.SEARCH:
			goal = _last_seen
			ai_sprint = true
			if global_position.distance_to(_last_seen) < 30.0:
				# Sniff around the last place it saw you.
				_last_seen += Vector2.from_angle(_rng.randf() * TAU) * 120.0
		State.WANDER:
			_goal_timer -= delta
			if _goal_timer <= 0.0 or global_position.distance_to(_goal) < 30.0:
				_pick_wander_goal()
			goal = _goal

	var dir := (goal - global_position).normalized()

	# Stuck on a trunk/rock: take a short detour sideways.
	if _detour_left > 0.0:
		_detour_left -= delta
		dir = (_detour * 0.8 + dir * 0.2).normalized()
	else:
		var moved := global_position.distance_to(_last_pos)
		var expected := (sprint_speed if ai_sprint else walk_speed) * delta * 0.3
		_stuck_timer = _stuck_timer + delta if moved < expected else 0.0
		if _stuck_timer > 0.25:
			_stuck_timer = 0.0
			_detour = dir.rotated(deg_to_rad(80.0 if _rng.randf() < 0.5 else -80.0))
			_detour_left = 0.6
	_last_pos = global_position
	ai_dir = dir


func _pick_wander_goal() -> void:
	_goal_timer = 8.0
	if map_rect.has_area():
		var r := map_rect.grow(-150.0)
		_goal = Vector2(_rng.randf_range(r.position.x, r.end.x), _rng.randf_range(r.position.y, r.end.y))
	else:
		_goal = global_position + Vector2.from_angle(_rng.randf() * TAU) * 600.0
