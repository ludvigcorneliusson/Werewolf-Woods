extends CharacterBody2D
## The settler. Movement with sprint + stamina, pixel-art sprite that switches
## between up/down/right (left = mirrored right), a vision light that acts as
## fog of war, and the following camera. Origin = feet.
##
## Run cycles come from the H3 videos (keyed, snapped back to the native pixel
## grid and the settler palette): assets/characters/settler_run_<dir>.png are
## horizontal strips. Idle = the original still sprites.

const WALK_SPEED := 120.0
const SPRINT_SPEED := 200.0
const DEPTH_SQUASH := 0.85       # up/down moves a bit slower on screen (3/4 view)
const STAMINA_DRAIN := 32.0      # per second while sprinting
const STAMINA_REGEN := 18.0      # per second otherwise
const EXHAUST_RECOVER := 30.0    # stamina needed before you can sprint again

const TEX_UP := preload("res://assets/characters/settler_up.png")
const TEX_DOWN := preload("res://assets/characters/settler_down.png")
const TEX_RIGHT := preload("res://assets/characters/settler_right.png")

## Run strips: frame count, frame size and the offset that puts the feet on the
## node origin (lined up with the idle sprite so start/stop doesn't jump).
const RUN := {
	"right": {"tex": preload("res://assets/characters/settler_run_right.png"), "frames": 29, "size": Vector2i(31, 47), "offset": Vector2(-15, -45), "cycle": 0.8},
	"up": {"tex": preload("res://assets/characters/settler_run_up.png"), "frames": 16, "size": Vector2i(27, 48), "offset": Vector2(-13, -44), "cycle": 0.5},
	"down": {"tex": preload("res://assets/characters/settler_run_down.png"), "frames": 12, "size": Vector2i(31, 45), "offset": Vector2(-16, -42), "cycle": 0.5},
}
## "cycle" = seconds per full run cycle (two steps) at WALK_SPEED, per direction.
## Higher = slower legs. Sprint plays faster automatically. Left uses "right".

var stamina := 100.0
var exhausted := false
var facing := Vector2.DOWN
var light: PointLight2D
var camera: Camera2D
var sprite: AnimatedSprite2D

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
	add_child(sprite)
	_play("idle_down")

	# Vision: a light that casts shadows behind trunks and bushes. Ground and
	# characters in shadow stay dark (line-of-sight fog of war). Props are lit
	# but not shadowed so the forest stays readable.
	light = PointLight2D.new()
	light.texture = _make_light_texture()
	light.texture_scale = 0.75
	light.energy = 1.1
	light.color = Color(0.9, 0.95, 1.0)
	light.range_item_cull_mask = 1 | 2
	light.shadow_enabled = true
	light.shadow_item_cull_mask = 1
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

	var sprinting := Input.is_action_pressed("sprint") and _moving and not exhausted
	if sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, 100.0)
		if exhausted and stamina >= EXHAUST_RECOVER:
			exhausted = false

	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	velocity = Vector2(dir.x, dir.y * DEPTH_SQUASH) * speed
	move_and_slide()

	_speed = speed
	if _moving:
		facing = dir
	_update_sprite()
	queue_redraw()


func _update_sprite() -> void:
	# Pick the view: sideways wins on diagonals.
	var view := "right"
	if absf(facing.x) >= absf(facing.y) * 0.9:
		sprite.flip_h = facing.x < 0.0
	else:
		view = "up" if facing.y < 0.0 else "down"
		sprite.flip_h = false
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
	for view: String in ["up", "down", "right"]:
		var idle_tex: Texture2D = {"up": TEX_UP, "down": TEX_DOWN, "right": TEX_RIGHT}[view]
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


func _make_light_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.85))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	# Wider than tall: the vision circle looks like a circle on the tilted ground.
	tex.width = 512
	tex.height = 400
	return tex
