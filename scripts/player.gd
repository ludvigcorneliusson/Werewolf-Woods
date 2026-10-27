extends CharacterBody2D
## The settler. Movement with unlimited sprint, pixel-art sprite in 8 directions
## (up, up-right, right, down-right, down; the left side mirrors the right), a
## vision light that acts as fog of war, and the following camera. Origin = feet.
##
## Run cycles come from the H3 videos (keyed, snapped back to the native pixel
## grid and the settler palette): assets/characters/settler_run_<dir>.png are
## horizontal strips. Idle = the original still sprites (diagonal idles are the
## standing first frame of their H3 video).

const WALK_SPEED := 120.0
const SPRINT_SPEED := 200.0
const DEPTH_SQUASH := 0.85       # up/down moves a bit slower on screen (3/4 view)

const TEX_UP := preload("res://assets/characters/settler_up.png")
const TEX_DOWN := preload("res://assets/characters/settler_down.png")
const TEX_RIGHT := preload("res://assets/characters/settler_right.png")
const TEX_UP_RIGHT := preload("res://assets/characters/settler_up_right.png")
const TEX_DOWN_RIGHT := preload("res://assets/characters/settler_down_right.png")

## Run strips: frame count, frame size and the offset that puts the feet on the
## node origin (lined up with the idle sprite so start/stop doesn't jump).
const RUN := {
	"right": {"tex": preload("res://assets/characters/settler_run_right.png"), "frames": 29, "size": Vector2i(31, 47), "offset": Vector2(-15, -45), "cycle": 1.1, "steps": [0.1, 0.36, 0.62, 0.88]},
	"up": {"tex": preload("res://assets/characters/settler_run_up.png"), "frames": 16, "size": Vector2i(27, 48), "offset": Vector2(-13, -44), "cycle": 0.5, "steps": [0.0, 0.5]},
	"down": {"tex": preload("res://assets/characters/settler_run_down.png"), "frames": 12, "size": Vector2i(31, 45), "offset": Vector2(-16, -42), "cycle": 0.5, "steps": [0.15, 0.65]},
	"up_right": {"tex": preload("res://assets/characters/settler_run_up_right.png"), "frames": 16, "size": Vector2i(28, 48), "offset": Vector2(-12, -44), "cycle": 0.5, "steps": [0.25, 0.7]},
	"down_right": {"tex": preload("res://assets/characters/settler_run_down_right.png"), "frames": 30, "size": Vector2i(32, 46), "offset": Vector2(-18, -41), "cycle": 0.9, "steps": [0.12, 0.38, 0.62, 0.88]},
}
## "cycle" = seconds per full run cycle (two steps) at WALK_SPEED, per direction.
## Higher = slower legs. Sprint plays faster automatically. Each direction has
## its own value. Left, up-left and down-left mirror right, up_right, down_right
## (and share their cycle).
## "steps" = where in the cycle a foot hits the ground (0..1, 0 = first frame);
## a footstep sound plays as the animation passes each one. The right and
## down_right strips hold two strides, so they have four steps.

## Axe chop (left click), from the H3 videos via tools/chop_from_video.py: one
## strip per side (right = ClipProj_H3_00018, left = ClipProj_H3_00005). Facing
## up/down he chops toward his last sideways side. "impact" = the frame where
## the blade lands. "durations" = how long each frame shows, in 1/fps steps:
## the top of the wind-up and the end of the swing are held a moment.
const CHOP := {
	# Filmed at ~12 fps (distinct frames only), so each frame shows twice as long.
	"right": {"tex": preload("res://assets/characters/settler_chop_right.png"), "frames": 13,
		"size": Vector2i(62, 48), "offset": Vector2(-30, -47), "fps": 30.0, "impact": 9,
		"durations": {0: 0.5, 1: 2.0, 2: 2.0, 3: 2.0, 4: 2.0, 5: 2.0, 6: 5.0, 7: 2.0, 8: 2.0,
			9: 5.0, 10: 2.0, 11: 2.0, 12: 2.0}},
	"left": {"tex": preload("res://assets/characters/settler_chop_left.png"), "frames": 26,
		"size": Vector2i(56, 50), "offset": Vector2(-32, -49), "fps": 30.0, "impact": 18,
		"durations": {0: 0.5, 13: 4.0, 19: 5.0, 20: 1.2, 21: 1.2, 22: 1.2, 23: 1.2, 24: 1.2, 25: 1.2}},
}
## How far in front of the feet the axe lands (world px) and how big the hit area is.
const CHOP_REACH := Vector2(17.0, -3.0)
const CHOP_HIT_RADIUS := 13.0

## The axe hits (at the impact frame). point = where the blade lands (world px),
## side = 1 right / -1 left. main.gd passes this on to scripts/tree_chopping.gd.
signal chop_hit(point: Vector2, side: int)
## The pickaxe hits. Same point/side as chop_hit; main.gd passes it on to
## scripts/mining.gd (ore nodes).
signal mine_hit(point: Vector2, side: int)

## Pickaxe swing (left click with the pickaxe), from ClipProj_H3_00021 via
## tools/chop_from_video.py (sides mine_right / mine_left, ClipProj_H3_00021 /
## 00023): rest, raise overhead (held), strike down (impact), hold, back up.
## Same keys as CHOP. Without a "left" entry the right strip is mirrored. (With MINE empty the
## pickaxe falls back to MINE_PLACEHOLDER: the standing sprite leans and swings.)
const MINE := {
	# Filmed at 24 fps, distinct frames only; the raised pick and the strike are held.
	"right": {"tex": preload("res://assets/characters/settler_mine_right.png"), "frames": 12,
		"size": Vector2i(51, 52), "offset": Vector2(-23, -49), "fps": 30.0, "impact": 8,
		"durations": {0: 0.5, 1: 2.0, 2: 2.0, 3: 2.0, 4: 4.0, 5: 3.0, 6: 2.0, 7: 1.5, 8: 6.0,
			9: 3.0, 10: 2.0, 11: 2.0}},
	# ClipProj_H3_00023 (facing left), same timing: wind-up held at the top, strike held.
	"left": {"tex": preload("res://assets/characters/settler_mine_left.png"), "frames": 14,
		"size": Vector2i(53, 51), "offset": Vector2(-33, -48), "fps": 30.0, "impact": 9,
		"durations": {0: 0.5, 1: 2.0, 2: 2.0, 3: 2.0, 4: 2.0, 5: 4.0, 6: 3.0, 7: 2.0, 8: 1.5,
			9: 6.0, 10: 3.0, 11: 2.0, 12: 2.0, 13: 2.0}},
}
## Spade dig (left click with the spade), from ClipProj_H3_00025 via
## tools/chop_from_video.py (side dig_right): push the blade in, lever (the
## dig), lift the dirt, back to rest. Same keys as CHOP; facing left plays the
## right strip mirrored until a "left" entry is added.
const DIG := {
	"right": {"tex": preload("res://assets/characters/settler_dig_right.png"), "frames": 18,
		"size": Vector2i(41, 48), "offset": Vector2(-15, -45), "fps": 30.0, "impact": 9,
		"durations": {0: 0.5, 1: 2.0, 2: 2.0, 3: 2.5, 4: 2.0, 5: 2.0, 6: 2.0, 7: 2.0, 8: 2.0,
			9: 4.0, 10: 2.0, 11: 2.0, 12: 2.0, 13: 3.0, 14: 2.0, 15: 2.0, 16: 2.0, 17: 2.0}},
}
## Watering (left click with the watering can), from ClipProj_H3_00029 via
## tools/chop_from_video.py (side water_right): lift the can, tilt, pour (frames
## 5-9; the water itself is particles from main.gd), lower it. Facing left
## plays it mirrored. "pour" = how long the pour lasts in frames from "impact".
const WATER := {
	"right": {"tex": preload("res://assets/characters/settler_water_right.png"), "frames": 14,
		"size": Vector2i(46, 46), "offset": Vector2(-15, -45), "fps": 30.0, "impact": 5,
		"durations": {0: 0.5, 1: 2.0, 2: 2.0, 3: 2.0, 4: 2.0, 5: 4.0, 6: 4.0, 7: 4.0, 8: 4.0, 9: 3.0,
			10: 2.0, 11: 2.0, 12: 2.0, 13: 2.0}},
}
## Sneaking (hold Ctrl), from ClipProj_H3_00031 via tools/chop_from_video.py
## (side sneak_right): frame 0 = crouched still, frames 1-4 = crouched steps.
## Side view only (faces his last sideways side), mirrored for left. He's
## tilted forward a little (SNEAK_LEAN radians, around the feet) because the
## filmed crouch stands too upright.
const SNEAK := {"tex": preload("res://assets/characters/settler_sneak_right.png"), "frames": 5,
	"size": Vector2i(32, 44), "offset": Vector2(-10, -43), "fps": 5.5}
const SNEAK_LEAN := 0.14
## Sneaking speed x walk speed.
var sneak_speed_scale := 0.45
## True while the local player sneaks (Ctrl): slow, no footstep sounds, no
## footprints; the AI werewolf only notices you from closer (werewolf.gd).
var sneaking := false

## Where the spout tip is while pouring (world px from the feet, facing right).
const SPOUT := Vector2(29, -11)
## The can starts pouring: from = the spout, seconds = how long it pours.
signal water_pour(from: Vector2, side: int, seconds: float)

## The spade digs (at the dig frame): point = where the blade goes in.
signal dig_hit(point: Vector2, side: int)

## Placeholder swing timing (seconds) and lean (radians, around the feet).
const MINE_PLACEHOLDER := {"windup": 0.3, "strike": 0.07, "recover": 0.28, "back": 0.16, "forward": 0.12}
## Tools that swing on left click.
const SWING_TOOLS := ["axe", "pickaxe", "spade", "watering_can"]

## Default footsteps: soft grass steps, three takes played in turn so walking
## doesn't sound like one sample on repeat (tools/make_sounds.py). The werewolf
## sets its own (werewolf.gd).
const STEP_SOUNDS := ["res://assets/sounds/footsteps/grass_soft_1.wav",
		"res://assets/sounds/footsteps/grass_soft_2.wav", "res://assets/sounds/footsteps/grass_soft_3.wav"]
const STEP_SOUND := "res://assets/sounds/footsteps/grass_soft_1.wav"   # first take (kept for older code)
## Whoosh per swinging tool (tools/make_sounds.py), heard as the tool comes down.
const SWING_SOUNDS := {"axe": "res://assets/sounds/swing_axe.wav", "pickaxe": "res://assets/sounds/swing_pickaxe.wav",
		"spade": "res://assets/sounds/swing_spade.wav", "watering_can": "res://assets/sounds/swing_can.wav"}
## How long before the hit the whoosh starts (its loudest part is near its end).
const SWING_LEAD := 0.24
const DEFAULT_STEPS := [0.0, 0.5]

## The character you control has the camera and the light; others (an AI
## werewolf) are darkened by the night like the props.
var is_local := true
## AI control instead of the keyboard (set ai_dir / ai_sprint each frame).
var ai_controlled := false
var ai_dir := Vector2.ZERO
var ai_sprint := false
## Keyboard control on/off (main.gd turns it off while the Esc menu is open).
var input_enabled := true
var walk_speed := WALK_SPEED
var sprint_speed := SPRINT_SPEED
var body_radius := 6.0
var shadow_radius := 9.0
## Half-size of the see-through area in props when you stand behind them
## (hugs the body; centred on the body, not the feet).
var see_through_size := Vector2(11, 23)

var facing := Vector2.DOWN
var god_mode := false            # set by main.gd: walk through everything, much faster
var god_speed := 4.0             # speed multiplier in god mode
var light: PointLight2D
var camera: Camera2D
var sprite: AnimatedSprite2D

# Idle breathing (assets/characters/idle_breathe.gdshader). main.gd sets these
# from its Idle settings.
var idle_enabled := true
var breath_amount := 1.0
var breath_speed := 0.35
var idle_sway := 0.4
var idle_sway_speed := 0.18
var _idle_mat: ShaderMaterial
var _idle := 0.0

# Footsteps (grass). Synced to the run animation, so they speed up with it
# when sprinting. main.gd sets these from its Footsteps settings.
var footsteps_enabled := true
var step_volume_db := -6.0         # same every step; the sound itself is never pitched
var step_hear_distance := 600.0    # world px; how far others hear these steps
var step_sound: AudioStream        # current footstep sound (null = STEP_SOUNDS); change with set_step_sound()
var step_takes: Array = STEP_SOUNDS   # default footstep files, played in turn (werewolf.gd sets its own)
var swing_volume_db := -8.0
var _takes: Array[AudioStream] = []
var _take_i := 0
var _custom_step := false
var _step_player: Node             # AudioStreamPlayer (you) or AudioStreamPlayer2D (others)
var _step_phase := -1.0            # last run-cycle phase (0..1); -1 = not running
var _step_cooldown := 0.0
var _steps := {}                   # run animation -> step phases

var _moving := false
var _speed := 0.0
## Chopping speed (1 = as built; 1.5 = half again as fast). main.gd sets it.
var chop_speed := 1.0
var chopping := false
## Tool in hand (the tools bar in hud.gd sets it). Left click swings the axe
## (chop), the pickaxe (mine), the spade (dig) or the watering can (water).
var held_tool := "axe"
## Pickaxe swing speed (1 = as built).
var mine_speed := 1.0
var _swing_tool := ""              # the tool of the swing in progress
## Push from a hit (world px/s); fades out quickly. main.gd sets it when you're attacked.
var knockback := Vector2.ZERO
var _chop_queued := false
var _chop_held := false
## True while placing something you build (scripts/placer.gd): clicks place, not chop.
var build_mode := false            # left button held since a press in the game (not on a menu)
var _side := 1                     # last sideways facing: 1 right, -1 left
var _offsets := {}


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("scares_rabbits")       # wildlife flees from every character (scripts/rabbit.gd)

	var shape := CircleShape2D.new()
	shape.radius = body_radius
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.sprite_frames = _build_frames()
	_idle_mat = ShaderMaterial.new()
	_idle_mat.shader = preload("res://assets/characters/idle_breathe.gdshader")
	# Local: breathing idle. Others: darkened by the night like props.
	sprite.material = _idle_mat if is_local else preload("res://assets/characters/character_material.tres")
	sprite.light_mask = 4          # characters: lit only by vision and fires
	add_child(sprite)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	_play("idle_down")
	_setup_footsteps()

	if not is_local:
		return

	# Vision: a light that casts shadows behind trunks and bushes. Ground and
	# characters in shadow stay dark (line-of-sight fog of war). Props are lit
	# but not shadowed so the forest stays readable.
	# Size, falloff and brightness are set by main.gd from its Fog settings.
	light = PointLight2D.new()
	# Light layers: 1 = ground/small plants, 2 = big props (never shadowed),
	# 4 = characters (lit only by vision and fires).
	light.range_item_cull_mask = 1 | 2 | 4
	light.shadow_enabled = true
	light.shadow_item_cull_mask = 1 | 4
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	add_child(light)

	camera = Camera2D.new()
	camera.position = Vector2(0, -20)   # center on the body, not the feet (offset would ignore camera limits)
	# Smooth follow. Movement runs in fixed physics steps; physics interpolation
	# (project setting) smooths it between steps, so the camera never stutters.
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	add_child(camera)
	camera.make_current()


func _physics_process(_delta: float) -> void:
	var dir := Vector2.ZERO
	if ai_controlled:
		dir = ai_dir.limit_length(1.0)
	elif input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Holding the button keeps chopping: the next swing starts as soon as one ends.
	if _chop_held:
		if Input.is_action_pressed("chop") and input_enabled and held_tool in SWING_TOOLS and not build_mode:
			if not chopping:
				_chop_queued = true
		else:
			_chop_held = false
	if _chop_queued and not chopping:
		_start_chop()
	_chop_queued = false
	if chopping:
		dir = Vector2.ZERO                  # stand still while swinging
	_moving = dir.length() > 0.05

	sneaking = is_local and not ai_controlled and input_enabled and not god_mode \
			and InputMap.has_action("sneak") and Input.is_action_pressed("sneak")
	var sprint_on := ai_sprint if ai_controlled else (input_enabled and Input.is_action_pressed("sprint"))
	var sprinting := sprint_on and _moving and not sneaking   # no stamina: sprint forever

	var speed := sprint_speed if sprinting else walk_speed
	if sneaking:
		speed = walk_speed * sneak_speed_scale
	velocity = Vector2(dir.x, dir.y * DEPTH_SQUASH) * speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 1400.0 * _delta)
	if god_mode:
		global_position += velocity * god_speed * _delta     # no collisions
	else:
		move_and_slide()

	_speed = speed
	if _moving:
		facing = dir
		if absf(dir.x) > 0.05:
			_side = 1 if dir.x > 0.0 else -1
	if not chopping:
		_update_sprite()
	_update_idle(_delta)
	queue_redraw()


func _process(delta: float) -> void:
	_update_footsteps(delta)


func _unhandled_input(event: InputEvent) -> void:
	# Clicks on menus/HUD never get here (the GUI takes them first).
	if is_local and not ai_controlled and input_enabled and held_tool in SWING_TOOLS and not build_mode \
			and event.is_action_pressed("chop"):
		_chop_queued = true
		_chop_held = true


# --- chopping -------------------------------------------------------------------

func _start_chop() -> void:
	chopping = true
	_moving = false
	_swing_tool = held_tool
	sprite.rotation = 0.0                         # no sneaking lean while swinging
	_swing_whoosh.call_deferred()
	if held_tool == "spade" or held_tool == "watering_can":
		var table: Dictionary = DIG if held_tool == "spade" else WATER
		var prefix := "dig_" if held_tool == "spade" else "water_"
		var own_left := _side < 0 and table.has("left")
		sprite.play(prefix + ("left" if own_left else "right"))
		sprite.flip_h = _side < 0 and not own_left
		sprite.speed_scale = mine_speed
		sprite.frame = 0
		_apply_flip_offset()
		return
	if held_tool == "pickaxe":
		if MINE.is_empty():
			_start_mine_placeholder()
			return
		var own_left := _side < 0 and MINE.has("left")
		sprite.play("mine_left" if own_left else "mine_right")
		sprite.flip_h = _side < 0 and not own_left        # no left strip yet: mirror the right one
		sprite.speed_scale = mine_speed
		sprite.frame = 0
		_apply_flip_offset()
		return
	sprite.flip_h = false                 # each side has its own strip
	sprite.speed_scale = chop_speed
	sprite.play("chop_right" if _side > 0 else "chop_left")
	sprite.frame = 0
	_apply_flip_offset()


## No pickaxe art yet: face the swing side, lean back, swing forward (the hit),
## straighten up. Rotation is around the feet (the sprite's origin).
func _start_mine_placeholder() -> void:
	facing = Vector2(_side, 0.0)
	_update_sprite()
	var m := MINE_PLACEHOLDER
	var k := 1.0 / maxf(mine_speed, 0.05)
	var t := create_tween()
	t.tween_property(sprite, "rotation", -m.back * _side, m.windup * k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	t.tween_property(sprite, "rotation", m.forward * _side, m.strike * k).set_ease(Tween.EASE_IN)
	t.tween_callback(_emit_hit)
	t.tween_property(sprite, "rotation", 0.0, m.recover * k).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_end_swing)


## The tool's whoosh, timed so it peaks as the tool comes down on the hit frame.
func _swing_whoosh() -> void:
	var path: String = SWING_SOUNDS.get(_swing_tool, "")
	if path == "" or not ResourceLoader.exists(path) or not chopping:
		return
	var delay := 0.25                              # placeholder pickaxe swing (no strip)
	var anim := String(sprite.animation)
	for prefix in ["chop_", "mine_", "dig_", "water_"]:
		if anim.begins_with(prefix):
			var table: Dictionary = {"chop_": CHOP, "mine_": MINE, "dig_": DIG, "water_": WATER}[prefix]
			var w: Dictionary = table.get(anim.trim_prefix(prefix), {})
			if w.is_empty():
				break
			var frames := 0.0
			for f in w.impact:
				frames += float(w.durations.get(f, 1.0))
			delay = frames / w.fps / maxf(absf(sprite.speed_scale), 0.05)
	if _swing_tool == "watering_can":
		delay *= 0.35                              # the can's swish is the lift, not a strike
	get_tree().create_timer(maxf(delay - SWING_LEAD, 0.0), false).timeout.connect(func():
		if not is_instance_valid(self):
			return
		var a: Node = AudioStreamPlayer.new() if is_local else AudioStreamPlayer2D.new()
		a.stream = load(path)
		a.volume_db = swing_volume_db
		a.pitch_scale = randf_range(0.95, 1.06)
		add_child(a)
		a.play()
		a.finished.connect(a.queue_free))


func _emit_hit() -> void:
	var point := global_position + Vector2(CHOP_REACH.x * _side, CHOP_REACH.y)
	if _swing_tool == "pickaxe":
		mine_hit.emit(point, _side)
	elif _swing_tool == "spade":
		dig_hit.emit(global_position + Vector2(13.0 * _side, 1.0), _side)
	elif _swing_tool == "watering_can":
		var w: Dictionary = WATER.right
		var frames := 0.0
		for f in range(w.impact, w.impact + 5):
			frames += float(w.durations.get(f, 1.0))
		water_pour.emit(global_position + Vector2(SPOUT.x * _side, SPOUT.y), _side,
				frames / w.fps / maxf(mine_speed, 0.05))
	else:
		chop_hit.emit(point, _side)


func _end_swing() -> void:
	chopping = false
	sprite.rotation = 0.0
	facing = Vector2(_side, 0.0)
	_update_sprite()


func _on_frame_changed() -> void:
	if not chopping:
		return
	var anim := String(sprite.animation)
	for prefix in ["chop_", "mine_", "dig_", "water_"]:
		if anim.begins_with(prefix):
			var table: Dictionary = {"chop_": CHOP, "mine_": MINE, "dig_": DIG, "water_": WATER}[prefix]
			if sprite.frame == table[anim.trim_prefix(prefix)].impact:
				_emit_hit()


func _on_animation_finished() -> void:
	if sprite.animation.begins_with("chop_") or sprite.animation.begins_with("mine_") \
			or sprite.animation.begins_with("dig_") or sprite.animation.begins_with("water_"):
		_end_swing()


# --- footsteps ----------------------------------------------------------------

func _setup_footsteps() -> void:
	# Your own steps: plain (not positional), so they always sound the same.
	# Other characters: positional, so you hear where they are and how far.
	_step_player = AudioStreamPlayer.new() if is_local else AudioStreamPlayer2D.new()
	for path: String in step_takes:
		if ResourceLoader.exists(path):
			_takes.append(load(path))
	if step_sound == null and not _takes.is_empty():
		step_sound = _takes[0]                   # no files = no footstep sound
	_step_player.stream = step_sound
	_step_player.max_polyphony = 2          # let the tail of one step finish under the next
	add_child(_step_player)
	apply_footsteps()


## Changes the footstep sound, also while the game runs (e.g. a different sound
## per ground type). null = back to the default STEP_SOUND. Takes effect from
## the next step; a step that is already playing finishes first.
func set_step_sound(stream: AudioStream) -> void:
	_custom_step = stream != null
	if stream == null and not _takes.is_empty():
		stream = _takes[0]
	if stream == step_sound:
		return
	step_sound = stream
	if _step_player and not _step_player.playing:
		_step_player.stream = stream


## Pushes the footstep settings to the audio player (call after changing them).
func apply_footsteps() -> void:
	if _step_player == null:
		return
	_step_player.volume_db = step_volume_db
	if _step_player is AudioStreamPlayer2D:
		_step_player.max_distance = step_hear_distance


## Plays a step each time the run animation passes a foot-down point.
## The animation speed already follows walk/sprint speed (speed_scale), so the
## step rate does too.
func _update_footsteps(delta: float) -> void:
	_step_cooldown -= delta
	var running := _moving and sprite != null and sprite.is_playing() \
			and sprite.animation.begins_with("run_") and is_physics_processing()
	if not footsteps_enabled or not running or _step_player == null:
		_step_phase = -1.0
		return
	var n := sprite.sprite_frames.get_frame_count(sprite.animation)
	var phase := (sprite.frame + sprite.frame_progress) / float(n)
	if _step_phase < 0.0:
		# Just started moving: first foot goes down right away.
		_step_phase = phase
		_play_step()
		# Skip a scheduled footfall that comes too soon after this one.
		var cycle := n / maxf(sprite.sprite_frames.get_animation_speed(sprite.animation) * sprite.speed_scale, 0.01)
		var per_cycle: int = maxi(_steps.get(sprite.animation, DEFAULT_STEPS).size(), 1)
		_step_cooldown = maxf(_step_cooldown, cycle / per_cycle * 0.6)
		return
	var prev := _step_phase
	_step_phase = phase
	var wrapped := phase < prev
	if wrapped and prev - phase < 0.5:
		return                                  # small jump back (direction change), not a new cycle
	for s: float in _steps.get(sprite.animation, DEFAULT_STEPS):
		var hit := (s > prev or s <= phase) if wrapped else (s > prev and s <= phase)
		if hit:
			_play_step()
			return


func _play_step() -> void:
	if _step_cooldown > 0.0:                    # guards against key-tapping spam
		return
	_step_cooldown = 0.09
	if not _custom_step and _takes.size() > 1:
		_take_i = (_take_i + 1) % _takes.size()  # next take
		step_sound = _takes[_take_i]
	if step_sound == null:
		return                                  # no footstep sound set
	if _step_player.stream != step_sound:
		_step_player.stream = step_sound
	_step_player.play()


## Fades the breathing in after he stops and out as soon as he moves.
func _update_idle(delta: float) -> void:
	if sprite.material != _idle_mat:
		return
	var target := 1.0 if idle_enabled and not _moving and not chopping else 0.0
	_idle = move_toward(_idle, target, delta * (1.5 if target > _idle else 8.0))
	_idle_mat.set_shader_parameter("active", _idle)
	_idle_mat.set_shader_parameter("breath_amount", breath_amount)
	_idle_mat.set_shader_parameter("breath_speed", breath_speed)
	_idle_mat.set_shader_parameter("sway_amount", idle_sway)
	_idle_mat.set_shader_parameter("sway_speed", idle_sway_speed)


func _update_sprite() -> void:
	# 8 directions: pick the 45-degree sector of the facing direction.
	# Sector 0 = right, then clockwise (screen y points down).
	if sneaking and sprite.sprite_frames.has_animation("sneak"):
		# Crouched, side view, leaning forward; steps only while moving.
		_play("sneak" if _moving else "sneak_still")
		sprite.flip_h = _side < 0
		sprite.speed_scale = 1.0
		sprite.rotation = SNEAK_LEAN * _side
		_apply_flip_offset()
		return
	sprite.rotation = 0.0
	var sector := posmod(int(round(facing.angle() / (PI / 4.0))), 8)
	var view: String = ["right", "down_right", "down", "down_right", "right", "up_right", "up", "up_right"][sector]
	sprite.flip_h = sector >= 3 and sector <= 5     # left side mirrors the right
	if _moving:
		_play("run_" + view)
		sprite.speed_scale = _speed / walk_speed
	else:
		_play("idle_" + view)
		sprite.speed_scale = 1.0
	_apply_flip_offset()


func _play(anim: String) -> void:
	if sprite.animation == anim and sprite.is_playing():
		return
	# Keep the stride phase when only the direction changes mid-run.
	var phase := 0.0
	if anim.begins_with("run_") and sprite.animation.begins_with("run_"):
		phase = float(sprite.frame) / sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.play(anim)
	if phase > 0.0:
		sprite.frame = int(phase * sprite.sprite_frames.get_frame_count(anim))


## Flipped frames mirror inside their rect; keep the feet on the origin.
func _apply_flip_offset() -> void:
	var off: Vector2 = _offsets[sprite.animation]
	if sprite.flip_h:
		var w := sprite.sprite_frames.get_frame_texture(sprite.animation, 0).get_width()
		off.x = -(off.x + w) + 1
	sprite.offset = off


func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for view: String in RUN:
		var idle_tex: Texture2D = {"up": TEX_UP, "down": TEX_DOWN, "right": TEX_RIGHT,
				"up_right": TEX_UP_RIGHT, "down_right": TEX_DOWN_RIGHT}[view]
		var idle: String = "idle_" + view
		sf.add_animation(idle)
		sf.add_frame(idle, idle_tex)
		_offsets[idle] = Vector2(-idle_tex.get_width() / 2, -idle_tex.get_height() + 1)

		var r: Dictionary = RUN[view]
		var run: String = "run_" + view
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

	# Sneaking: "sneak_still" = the crouched frame, "sneak" = the step loop.
	sf.add_animation("sneak_still")
	var st := AtlasTexture.new()
	st.atlas = SNEAK.tex
	st.region = Rect2(Vector2.ZERO, Vector2(SNEAK.size))
	sf.add_frame("sneak_still", st)
	_offsets["sneak_still"] = SNEAK.offset
	sf.add_animation("sneak")
	sf.set_animation_loop("sneak", true)
	sf.set_animation_speed("sneak", SNEAK.fps)
	for i in range(1, SNEAK.frames):
		var at := AtlasTexture.new()
		at.atlas = SNEAK.tex
		at.region = Rect2(Vector2(i * SNEAK.size.x, 0), Vector2(SNEAK.size))
		sf.add_frame("sneak", at)
	_offsets["sneak"] = SNEAK.offset

	var swings := []
	for side: String in CHOP:
		swings.append(["chop_" + side, CHOP[side]])
	for side: String in MINE:
		swings.append(["mine_" + side, MINE[side]])
	for side: String in DIG:
		swings.append(["dig_" + side, DIG[side]])
	for side: String in WATER:
		swings.append(["water_" + side, WATER[side]])
	for sw in swings:
		var c: Dictionary = sw[1]
		var anim: String = sw[0]
		sf.add_animation(anim)
		sf.set_animation_loop(anim, false)
		sf.set_animation_speed(anim, c.fps)
		for i in c.frames:
			var at := AtlasTexture.new()
			at.atlas = c.tex
			at.region = Rect2(Vector2(i * c.size.x, 0), Vector2(c.size))
			sf.add_frame(anim, at, c.durations.get(i, 1.0))
		_offsets[anim] = c.offset
	return sf


func _draw() -> void:
	# Soft ground shadow under the feet.
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
