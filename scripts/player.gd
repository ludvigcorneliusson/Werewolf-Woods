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

const STEP_SOUND := "res://assets/sounds/footsteps/grass_step.wav"   # default footstep
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
var step_sound: AudioStream        # current footstep sound (null = STEP_SOUND); change with set_step_sound()
var _step_player: Node             # AudioStreamPlayer (you) or AudioStreamPlayer2D (others)
var _step_phase := -1.0            # last run-cycle phase (0..1); -1 = not running
var _step_cooldown := 0.0
var _steps := {}                   # run animation -> step phases

var _moving := false
var _speed := 0.0
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
	_moving = dir.length() > 0.05

	var sprint_on := ai_sprint if ai_controlled else (input_enabled and Input.is_action_pressed("sprint"))
	var sprinting := sprint_on and _moving   # no stamina: sprint forever

	var speed := sprint_speed if sprinting else walk_speed
	velocity = Vector2(dir.x, dir.y * DEPTH_SQUASH) * speed
	if god_mode:
		global_position += velocity * god_speed * _delta     # no collisions
	else:
		move_and_slide()

	_speed = speed
	if _moving:
		facing = dir
	_update_sprite()
	_update_idle(_delta)
	queue_redraw()


func _process(delta: float) -> void:
	_update_footsteps(delta)


# --- footsteps ----------------------------------------------------------------

func _setup_footsteps() -> void:
	# Your own steps: plain (not positional), so they always sound the same.
	# Other characters: positional, so you hear where they are and how far.
	_step_player = AudioStreamPlayer.new() if is_local else AudioStreamPlayer2D.new()
	if step_sound == null and ResourceLoader.exists(STEP_SOUND):
		step_sound = load(STEP_SOUND)            # no file = no footstep sound
	_step_player.stream = step_sound
	_step_player.max_polyphony = 2          # let the tail of one step finish under the next
	add_child(_step_player)
	apply_footsteps()


## Changes the footstep sound, also while the game runs (e.g. a different sound
## per ground type). null = back to the default STEP_SOUND. Takes effect from
## the next step; a step that is already playing finishes first.
func set_step_sound(stream: AudioStream) -> void:
	if stream == null and ResourceLoader.exists(STEP_SOUND):
		stream = load(STEP_SOUND)
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
	if step_sound == null:
		return                                  # no footstep sound set
	if _step_player.stream != step_sound:
		_step_player.stream = step_sound
	_step_player.play()


## Fades the breathing in after he stops and out as soon as he moves.
func _update_idle(delta: float) -> void:
	if sprite.material != _idle_mat:
		return
	var target := 1.0 if idle_enabled and not _moving else 0.0
	_idle = move_toward(_idle, target, delta * (1.5 if target > _idle else 8.0))
	_idle_mat.set_shader_parameter("active", _idle)
	_idle_mat.set_shader_parameter("breath_amount", breath_amount)
	_idle_mat.set_shader_parameter("breath_speed", breath_speed)
	_idle_mat.set_shader_parameter("sway_amount", idle_sway)
	_idle_mat.set_shader_parameter("sway_speed", idle_sway_speed)


func _update_sprite() -> void:
	# 8 directions: pick the 45-degree sector of the facing direction.
	# Sector 0 = right, then clockwise (screen y points down).
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
	return sf


func _draw() -> void:
	# Soft ground shadow under the feet.
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
