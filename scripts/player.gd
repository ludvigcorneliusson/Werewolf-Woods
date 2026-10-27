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
	"right": {"tex": preload("res://assets/characters/settler_run_right.png"), "frames": 29, "size": Vector2i(31, 47), "offset": Vector2(-15, -45), "cycle": 1.1},
	"up": {"tex": preload("res://assets/characters/settler_run_up.png"), "frames": 16, "size": Vector2i(27, 48), "offset": Vector2(-13, -44), "cycle": 0.5},
	"down": {"tex": preload("res://assets/characters/settler_run_down.png"), "frames": 12, "size": Vector2i(31, 45), "offset": Vector2(-16, -42), "cycle": 0.5},
	"up_right": {"tex": preload("res://assets/characters/settler_run_up_right.png"), "frames": 16, "size": Vector2i(28, 48), "offset": Vector2(-12, -44), "cycle": 0.5},
	"down_right": {"tex": preload("res://assets/characters/settler_run_down_right.png"), "frames": 30, "size": Vector2i(32, 46), "offset": Vector2(-18, -41), "cycle": 0.9},
}
## "cycle" = seconds per full run cycle (two steps) at WALK_SPEED, per direction.
## Higher = slower legs. Sprint plays faster automatically. Each direction has
## its own value. Left, up-left and down-left mirror right, up_right, down_right
## (and share their cycle).

var facing := Vector2.DOWN
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

var _moving := false
var _speed := 0.0
var _offsets := {}


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	var shape := CircleShape2D.new()
	shape.radius = 6.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.sprite_frames = _build_frames()
	_idle_mat = ShaderMaterial.new()
	_idle_mat.shader = preload("res://assets/characters/idle_breathe.gdshader")
	sprite.material = _idle_mat
	sprite.light_mask = 4          # characters: lit only by vision and fires
	add_child(sprite)
	_play("idle_down")

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
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	camera.make_current()


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_moving = dir != Vector2.ZERO

	var sprinting := Input.is_action_pressed("sprint") and _moving   # no stamina: sprint forever

	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity = Vector2(dir.x, dir.y * DEPTH_SQUASH) * speed
	move_and_slide()

	_speed = speed
	if _moving:
		facing = dir
	_update_sprite()
	_update_idle(delta)
	queue_redraw()


## Fades the breathing in after he stops and out as soon as he moves.
func _update_idle(delta: float) -> void:
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
		sprite.speed_scale = _speed / WALK_SPEED
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
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
