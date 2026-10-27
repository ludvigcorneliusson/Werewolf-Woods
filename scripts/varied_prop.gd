@tool
extends Node2D
## Any placed prop (pines, stumps, logs, rocks, ferns, ...). Each instance picks
## its own size, colour and facing from its position on the map, so the same map
## always looks the same (and in multiplayer every client agrees without syncing).
##
## Each prop scene stores its own values on its root: edit the root of e.g.
## assets/props/pine.tscn or fern_a.tscn to change ALL of that prop.
## Size scales the whole prop: sprite, collision and vision blocker.
## Small pixel-art props stay at 1.0 so their pixels match the settler's.

## Smallest size (x the art). Trees use 2.0-2.6 (set in tools/build_world.gd).
@export_range(0.5, 8.0, 0.05) var min_scale := 1.0:
	set(v):
		min_scale = v
		_vary()
## Largest size.
@export_range(0.5, 8.0, 0.05) var max_scale := 1.0:
	set(v):
		max_scale = v
		_vary()
## Hue shift, +/- this fraction of the colour wheel (0.03 = from bluer to yellower green).
@export_range(0.0, 0.2, 0.005) var hue_variance := 0.02:
	set(v):
		hue_variance = v
		_vary()
## Saturation change, +/- this fraction.
@export_range(0.0, 0.5, 0.01) var saturation_variance := 0.12:
	set(v):
		saturation_variance = v
		_vary()
## Brightness change, +/- this fraction.
@export_range(0.0, 0.5, 0.01) var brightness_variance := 0.1:
	set(v):
		brightness_variance = v
		_vary()
## How much the wind bends this prop (0 = rigid, 1 = full). Wind settings are on Main.
@export_range(0.0, 1.0, 0.05) var sway := 0.0:
	set(v):
		sway = v
		_vary()
## How much it bends when the settler walks through it (0 = not at all, e.g. rocks).
## Push settings are on Main (Plants group).
@export_range(0.0, 3.0, 0.05) var bend := 0.0
## Randomly mirror the prop so the forest looks less repetitive.
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
	# Mirror collision and vision blocker along with the art (matters for lopsided props).
	for part in ["Body", "VisionBlocker"]:
		var n := get_node_or_null(part) as Node2D
		if n:
			n.scale.x = -1.0 if sprite.flip_h else 1.0
	# Encoded for prop_fade.gdshader (color_variance): 0.5 = unchanged; alpha = sway.
	sprite.self_modulate = Color(
		0.5 + rng.randf_range(-hue_variance, hue_variance),
		0.5 * (1.0 + rng.randf_range(-saturation_variance, saturation_variance)),
		0.5 * (1.0 + rng.randf_range(-brightness_variance, brightness_variance)),
		0.5 + clampf(sway, 0.0, 1.0) * 0.5)
