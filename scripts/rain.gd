extends Node2D
## Rain effect: falling streaks over the world, small splashes on the ground and
## a looping rain sound. Everything follows the camera and scales with
## `intensity` (0..1, from scripts/weather.gd via main.gd), so rain fades in and
## out smoothly. Created and configured by main.gd (Main > Weather settings).
##
## Streaks are drawn above props and characters but read the same light map as
## the night darkness (scripts/darkness.gd), so they only show where there is
## light: in your vision and around campfires. Splashes sit on the ground under
## the darkness overlay, so the same goes for them.

var camera: Camera2D
var intensity := 0.0               # 0 = dry .. 1 = full rain
var brightness := 1.0              # overall streak opacity multiplier

# Settings (main.gd sets these, then calls apply())
var drops := 900                   # streaks on screen at full rain (at camera zoom 1)
var splashes := 140                # ground splashes at full rain
var color := Color(0.8, 0.87, 1.0, 0.7)
var fall_speed := 650.0            # world px per second
var slant := 0.18                  # sideways drift per px fallen (+ = to the right)
var sound: AudioStream
var volume_db := -8.0

## The night darkness puts its light map on the shared prop material; the
## streak shader reads the same textures/values from there every frame.
const PROP_MATERIAL := preload("res://assets/props/varied_material.tres")
const DK_PARAMS := ["dk_player_light", "dk_static_light", "dk_player_origin", "dk_player_size",
		"dk_static_origin", "dk_static_size", "dk_static_strength", "dk_darkness"]
const DROP_SHADER := """
shader_type canvas_item;
// Rain streaks lit like the ground: they fade out where the night darkness is.
uniform sampler2D dk_player_light : filter_linear, repeat_disable;
uniform sampler2D dk_static_light : filter_linear, repeat_disable;
uniform vec2 dk_player_origin;
uniform vec2 dk_player_size = vec2(1.0);
uniform vec2 dk_static_origin;
uniform vec2 dk_static_size = vec2(1.0);
uniform float dk_static_strength = 1.0;
uniform float dk_darkness = 0.0;
uniform vec2 view_origin;            // world px at the top-left of the screen
uniform vec2 view_size = vec2(1.0);  // world px covered by the screen

float sample_in(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return texture(tex, uv).r;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 world = view_origin + SCREEN_UV * view_size;
	float lit = sample_in(dk_player_light, (world - dk_player_origin) / dk_player_size);
	lit = max(lit, sample_in(dk_static_light, (world - dk_static_origin) / dk_static_size) * dk_static_strength);
	c.a *= 1.0 - dk_darkness * (1.0 - clamp(lit, 0.0, 1.0));
	COLOR = c;
}
"""

var _drops: GPUParticles2D
var _drop_shader_mat: ShaderMaterial
var _splash: GPUParticles2D
var _audio: AudioStreamPlayer
var _drop_mat: ParticleProcessMaterial
var _splash_mat: ParticleProcessMaterial
var _view := Vector2.ZERO


func _ready() -> void:
	top_level = true

	_drop_mat = ParticleProcessMaterial.new()
	_drop_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_drop_mat.gravity = Vector3.ZERO
	_drop_mat.spread = 2.0
	_drop_mat.particle_flag_align_y = true
	_drop_mat.particle_flag_disable_z = true
	_drop_mat.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.15, 0.8, 1.0])
	_drops = GPUParticles2D.new()
	_drops.process_material = _drop_mat
	_drops.texture = _streak_texture()
	_drops.lifetime = 0.45
	_drops.local_coords = false
	_drops.z_index = 40                       # above props and characters
	_drops.z_as_relative = false
	_drop_shader_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = DROP_SHADER
	_drop_shader_mat.shader = sh
	_drops.material = _drop_shader_mat
	add_child(_drops)

	_splash_mat = ParticleProcessMaterial.new()
	_splash_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_splash_mat.gravity = Vector3.ZERO
	_splash_mat.initial_velocity_min = 0.0
	_splash_mat.initial_velocity_max = 0.0
	_splash_mat.particle_flag_disable_z = true
	_splash_mat.scale_min = 0.8
	_splash_mat.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = grow
	_splash_mat.scale_curve = ct
	_splash_mat.color_ramp = _ramp([Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)], [0.0, 1.0])
	_splash = GPUParticles2D.new()
	_splash.process_material = _splash_mat
	_splash.texture = _ring_texture()
	_splash.lifetime = 0.35
	_splash.local_coords = false
	_splash.z_index = -9                      # on the ground: above it (-10), under the darkness (-5)
	_splash.z_as_relative = false
	add_child(_splash)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	# Particles emit by default: start switched off, spread over the whole
	# screen (not from one point), until we know where the camera is.
	_drops.emitting = false
	_splash.emitting = false
	var half := get_viewport().get_visible_rect().size * 0.5 + Vector2(80, 80)
	_drop_mat.emission_box_extents = Vector3(half.x, half.y, 0.0)
	_splash_mat.emission_box_extents = Vector3(half.x, half.y, 0.0)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame, not per physics tick
	apply()


## Pushes the settings (call after changing them).
func apply() -> void:
	if _drops == null:
		return
	_drops.amount = maxi(drops, 1)
	_splash.amount = maxi(splashes, 1)
	_drop_mat.direction = Vector3(slant, 1.0, 0.0).normalized()
	_drop_mat.initial_velocity_min = fall_speed * 0.9
	_drop_mat.initial_velocity_max = fall_speed * 1.1
	_drop_mat.color = color
	_splash_mat.color = Color(color, 1.0)
	if _audio.stream != sound:
		_audio.stop()
		_audio.stream = _looping(sound)
	_view = Vector2.ZERO                      # resize the emitters on the next frame


func _process(_delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		_drops.emitting = false                   # no camera yet: nowhere to put the rain
		_splash.emitting = false
		return
	var on := intensity > 0.001
	_drops.emitting = on
	_splash.emitting = on
	_drops.amount_ratio = intensity
	_splash.amount_ratio = intensity
	_drops.modulate.a = brightness
	global_position = camera.get_screen_center_position()
	if on:
		# Same light as the ground: copy the darkness light map + screen area.
		for p: String in DK_PARAMS:
			_drop_shader_mat.set_shader_parameter(p, PROP_MATERIAL.get_shader_parameter(p))
		var screen := get_viewport().get_visible_rect().size / camera.zoom
		_drop_shader_mat.set_shader_parameter("view_origin", global_position - screen * 0.5)
		_drop_shader_mat.set_shader_parameter("view_size", screen)

	# Cover the whole view (and a margin), also when the zoom changes.
	var view := get_viewport().get_visible_rect().size / camera.zoom
	if not view.is_equal_approx(_view):
		_view = view
		var half := view * 0.5 + Vector2(80, 80)
		# Drops spawn a bit higher so they fall into view from the top edge too.
		_drop_mat.emission_box_extents = Vector3(half.x, half.y, 0.0)
		_splash_mat.emission_box_extents = Vector3(half.x, half.y, 0.0)
		var vis := Rect2(-half - Vector2(0, 400), half * 2.0 + Vector2(0, 800))
		_drops.visibility_rect = vis
		_splash.visibility_rect = vis

	if _audio.stream:
		if on and not _audio.playing:
			_audio.play()
		elif not on and _audio.playing:
			_audio.stop()
		_audio.volume_db = volume_db + linear_to_db(maxf(intensity, 0.0001))


func _looping(stream: AudioStream) -> AudioStream:
	if stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif stream != null and "loop" in stream:
		stream.loop = true                    # .ogg / .mp3
	return stream


func _ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


## A thin 1 x 18 px streak, faint at the tail (top) and bright at the head.
func _streak_texture() -> ImageTexture:
	var img := Image.create(1, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		img.set_pixel(0, y, Color(1, 1, 1, pow((y + 1) / 18.0, 0.8)))
	return ImageTexture.create_from_image(img)


## A small flat ring (3/4 view) for splashes.
func _ring_texture() -> ImageTexture:
	var w := 13
	var h := 6
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (x + 0.5 - w / 2.0) / (w / 2.0)
			var dy := (y + 0.5 - h / 2.0) / (h / 2.0)
			var d := sqrt(dx * dx + dy * dy)
			if d > 0.6 and d <= 1.05:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0))
	return ImageTexture.create_from_image(img)
