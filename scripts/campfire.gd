extends Node2D
## Campfire: Godot particles (Fire, Core, Embers, Smoke) over a pixel-art base,
## plus a warm flickering glow. It also cuts an organic hole in the night darkness
## (scripts/darkness.gd) - light_radius sets its size.
## Tweak the particles directly on the child nodes in assets/props/campfire.tscn.

## Radius of the area the fire lights up, in world pixels.
@export_range(20.0, 600.0, 1.0, "suffix:px") var light_radius := 190.0
## Base brightness of the light.
@export_range(0.0, 4.0, 0.05) var light_energy := 0.55
## How much the light flickers (0 = steady).
@export_range(0.0, 1.0, 0.01) var flicker_strength := 0.16
## How fast the light flickers.
@export_range(0.1, 10.0, 0.1) var flicker_speed := 3.0

@onready var light: PointLight2D = $Light

var _noise := FastNoiseLite.new()
var _t := 0.0
var flicker_now := 0.0       # read by darkness.gd so the lit area flickers with the glow
var glow_scale := 1.0        # set by main.gd's day/night: dim glow in daylight


func _ready() -> void:
	add_to_group("light_sources")
	_noise.seed = int(global_position.x * 13.0 + global_position.y)
	_noise.frequency = 1.0
	_noise.fractal_octaves = 2


func _process(delta: float) -> void:
	_t += delta * flicker_speed
	var n := _noise.get_noise_1d(_t)                 # roughly -0.6..0.6
	flicker_now = n * flicker_strength * 1.8
	light.energy = light_energy * glow_scale * (1.0 + n * flicker_strength * 1.8)
	var tex_w := float(light.texture.get_width()) if light.texture else 256.0
	light.texture_scale = light_radius * 2.0 / tex_w * (1.0 + n * flicker_strength * 0.15)
