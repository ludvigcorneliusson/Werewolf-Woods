@tool
extends Node2D
## A pine tree. Every pine picks its own size, colour and facing from its
## position on the map, so the same map always looks the same (and in
## multiplayer every client agrees without syncing anything).
##
## Edit these on the root of assets/props/pine.tscn to change ALL pines.
## Size scales the whole tree: sprite, trunk collision and vision blocker.
## Reference: settler = 43 px tall, pine art = 101 px at scale 1.

## Smallest tree size (x the original 101 px art). 2.7 = 270 px ~= 6x the settler.
@export_range(0.5, 8.0, 0.05) var min_scale := 2.7:
	set(v):
		min_scale = v
		_vary()
## Largest tree size. 3.9 = 390 px ~= 9x the settler.
@export_range(0.5, 8.0, 0.05) var max_scale := 3.9:
	set(v):
		max_scale = v
		_vary()
## Hue shift, +/- this fraction of the colour wheel (0.03 = from bluer to yellower green).
@export_range(0.0, 0.2, 0.005) var hue_variance := 0.03:
	set(v):
		hue_variance = v
		_vary()
## Saturation change, +/- this fraction.
@export_range(0.0, 0.5, 0.01) var saturation_variance := 0.2:
	set(v):
		saturation_variance = v
		_vary()
## Brightness change, +/- this fraction.
@export_range(0.0, 0.5, 0.01) var brightness_variance := 0.15:
	set(v):
		brightness_variance = v
		_vary()
## Randomly mirror trees so the forest looks less repetitive.
@export var random_flip := true:
	set(v):
		random_flip = v
		_vary()

var _rolled_at := Vector2.INF


func _ready() -> void:
	set_notify_transform(Engine.is_editor_hint())
	_vary()


func _notification(what: int) -> void:
	# Re-roll when the tree is moved in the editor (not when we rescale it).
	if what == NOTIFICATION_TRANSFORM_CHANGED and position != _rolled_at:
		_vary()


func _vary() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position.round()))
	# Bias toward the middle of the range: few tiny or giant trees.
	var t := (rng.randf() + rng.randf()) * 0.5
	var s := lerpf(min_scale, maxf(max_scale, min_scale), t)
	_rolled_at = position
	scale = Vector2(s, s)
	sprite.flip_h = random_flip and rng.randf() < 0.5
	# Encoded for prop_fade.gdshader (color_variance): 0.5 = unchanged.
	sprite.self_modulate = Color(
		0.5 + rng.randf_range(-hue_variance, hue_variance),
		0.5 * (1.0 + rng.randf_range(-saturation_variance, saturation_variance)),
		0.5 * (1.0 + rng.randf_range(-brightness_variance, brightness_variance)),
		1.0)
