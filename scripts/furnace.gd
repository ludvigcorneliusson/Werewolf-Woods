extends Node2D
## Furnace (built from the build menu): smelts iron ore into iron ingots and
## silver ore into silver ingots (one kind of ore at a time; it won't smelt
## silver onto iron ingots still waiting in the output, or the other way round).
## Walk up and press E (scripts/pickups.gd) to open its panel
## (scripts/furnace_panel.gd): drag ore and fuel (logs, twigs) in from the
## backpack, switch it on, take the ingots out.
## While it's on it burns fuel (a log lasts FUEL.log seconds, a twig FUEL.twig),
## and every SMELT_TIME seconds of burning turns one ore into one ingot. When
## the fuel runs out it goes out by itself. Burning: fire in the mouth, embers,
## smoke from the top, a warm flickering light that also opens the night
## darkness around it (group "light_sources", like campfires).

signal changed

## Ore it smelts -> the ingot it makes.
const SMELTS := {"iron_ore": "iron_ingot", "silver_ore": "silver_ingot"}
## Seconds of burning per ingot (1 ore -> 1 ingot).
const SMELT_TIME := 10.0
## Fuel items -> seconds of burning each.
const FUEL := {"log": 30.0, "twig": 8.0}
## Most of each it holds.
const CAPACITY := 20

## Radius of the area the fire lights up, in world pixels (darkness.gd).
@export_range(20.0, 600.0, 1.0, "suffix:px") var light_radius := 120.0
@export var prompt_height := 58.0

var ore := 0
var ore_id := ""                    # "iron_ore" / "silver_ore" ("" = empty)
var output_id := ""                 # ingot kind in the output ("" = empty)
var fuel_id := ""                   # "log" or "twig" ("" = empty)
var fuel_count := 0
var ingots := 0
var burning := false
var burn_left := 0.0                # seconds left on the piece of fuel that's burning
var progress := 0.0                 # seconds towards the next ingot

var flicker_now := 0.0              # read by darkness.gd
var glow_scale := 1.0               # set by main.gd's day/night
var _t := 0.0
var _noise := FastNoiseLite.new()
var _fx: Array[CPUParticles2D] = []
var _light: PointLight2D
var _sound: AudioStreamPlayer2D

const FIRE_SOUND := "res://assets/sounds/soundreality-fire-sound-334130 (mp3cut.net).mp3"
## Where the effects come out (world px from the foot point).
const MOUTH := Vector2(-1, -9)
const TOP := Vector2(-1, -46)


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("furnaces")
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite and sprite.material == null:
		sprite.material = preload("res://assets/props/varied_material.tres")
		sprite.self_modulate = Color(0.5, 0.5, 0.5, 0.5)     # shaded like the props at night
	_noise.seed = int(global_position.x * 7.0 + global_position.y)
	_noise.frequency = 1.0
	_build_effects()
	_apply_burning()


## E next to it: open its panel.
func interact() -> String:
	get_tree().call_group("furnace_ui", "open_furnace", self)
	return ""


# --- loading ------------------------------------------------------------------------

## Puts up to n of an item in; returns how many it took.
func add_item(id: String, n: int) -> int:
	var take := 0
	if SMELTS.has(id) and (ore_id == "" or ore_id == id):
		take = mini(n, CAPACITY - ore)
		if take > 0:
			ore_id = id
			ore += take
	elif FUEL.has(id) and (fuel_id == "" or fuel_id == id):
		take = mini(n, CAPACITY - fuel_count)
		if take > 0:
			fuel_id = id
			fuel_count += take
	if take > 0:
		changed.emit()
	return take


## False while the output holds a different ingot than this ore makes.
func can_smelt() -> bool:
	return ore_id != "" and (output_id == "" or output_id == SMELTS[ore_id])


## Takes everything out of one slot ("ore", "fuel", "output"): [item id, count].
func take_all(slot: String) -> Array:
	var out := []
	match slot:
		"ore":
			out = [ore_id, ore]
			ore = 0
			ore_id = ""
			progress = 0.0
		"fuel":
			out = [fuel_id, fuel_count]
			fuel_count = 0
			fuel_id = ""
		"output":
			out = [output_id, ingots]
			ingots = 0
			output_id = ""
	changed.emit()
	return out


## Puts back what didn't fit in the backpack.
func give_back(slot: String, id: String, n: int) -> void:
	if n <= 0:
		return
	match slot:
		"ore":
			ore_id = id
			ore += n
		"fuel":
			fuel_id = id
			fuel_count += n
		"output":
			output_id = id
			ingots += n
	changed.emit()


## On/off switch. Returns false if it can't light (no fuel at all).
func toggle() -> bool:
	if burning:
		burning = false
	elif burn_left > 0.0 or fuel_count > 0:
		burning = true
	else:
		return false
	_apply_burning()
	changed.emit()
	return true


# --- running ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta * 3.0
	var n := _noise.get_noise_1d(_t)
	flicker_now = n * 0.3
	if _light:
		_light.energy = 0.6 * glow_scale * (1.0 + n * 0.3)
	if not burning:
		return
	if burn_left <= 0.0:
		if fuel_count > 0:
			fuel_count -= 1
			burn_left += float(FUEL.get(fuel_id, 0.0))
			if fuel_count == 0:
				fuel_id = ""
		else:
			burning = false                    # out of fuel: the fire dies
			_apply_burning()
			changed.emit()
			return
	burn_left = maxf(burn_left - delta, 0.0)
	if ore > 0 and ingots < CAPACITY and can_smelt():
		progress += delta
		if progress >= SMELT_TIME:
			progress -= SMELT_TIME
			output_id = SMELTS[ore_id]
			ore -= 1
			ingots += 1
			if ore == 0:
				ore_id = ""
			changed.emit()


func _apply_burning() -> void:
	for p in _fx:
		p.emitting = burning
	if _light:
		_light.visible = burning
	if _sound:
		if burning and not _sound.playing:
			_sound.play()
		elif not burning:
			_sound.stop()
	if burning:
		add_to_group("light_sources")
	elif is_in_group("light_sources"):
		remove_from_group("light_sources")
	get_tree().call_group("fire_listeners", "on_fire_toggled", self)   # redraw the night darkness


## Fire and embers in the mouth, smoke rising out of the top, a warm light.
func _build_effects() -> void:
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var fire := _particles(MOUTH, 26, 0.45, Vector2.UP, 25.0, 10.0, 26.0, Vector2(0, -30))
	fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fire.emission_rect_extents = Vector2(5, 1.5)
	fire.scale_amount_min = 1.5
	fire.scale_amount_max = 3.0
	fire.color_ramp = _ramp([Color(1.0, 0.85, 0.4, 0.95), Color(1.0, 0.45, 0.12, 0.8), Color(0.6, 0.12, 0.05, 0.0)])
	fire.material = add_mat
	var embers := _particles(MOUTH + Vector2(0, -2), 6, 1.0, Vector2.UP, 40.0, 15.0, 35.0, Vector2(0, -10))
	embers.color_ramp = _ramp([Color(1.0, 0.7, 0.3, 1.0), Color(1.0, 0.4, 0.1, 0.0)])
	embers.material = add_mat
	var glow := _particles(TOP + Vector2(0, 3), 8, 0.5, Vector2.UP, 15.0, 4.0, 10.0, Vector2.ZERO)
	glow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	glow.emission_rect_extents = Vector2(6, 1)
	glow.scale_amount_min = 1.0
	glow.scale_amount_max = 2.0
	glow.color_ramp = _ramp([Color(1.0, 0.6, 0.2, 0.7), Color(1.0, 0.3, 0.05, 0.0)])
	glow.material = add_mat
	# Smoke: soft round puffs that drift up and to the side, growing and fading.
	var smoke := _particles(TOP + Vector2(0, -2), 16, 3.2, Vector2(0.12, -1.0), 10.0, 9.0, 15.0, Vector2(5, -4))
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.emission_rect_extents = Vector2(4, 1)
	smoke.texture = _puff_texture()
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.max_value = 3.0
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 2.4))
	smoke.scale_amount_curve = grow
	smoke.angle_min = 0.0
	smoke.angle_max = 360.0
	smoke.color_ramp = _ramp([Color(0.55, 0.53, 0.5, 0.0), Color(0.5, 0.48, 0.46, 0.55),
			Color(0.55, 0.55, 0.55, 0.3), Color(0.6, 0.6, 0.6, 0.0)])
	_light = PointLight2D.new()
	_light.texture = _light_texture()
	_light.texture_scale = light_radius * 2.0 / 128.0
	_light.color = Color(1.0, 0.62, 0.32)
	_light.position = MOUTH
	_light.range_item_cull_mask = 1 | 2 | 4
	add_child(_light)
	# Same crackle as the campfire (if the project has that sound file).
	if ResourceLoader.exists(FIRE_SOUND):
		_sound = AudioStreamPlayer2D.new()
		_sound.stream = load(FIRE_SOUND)
		_sound.volume_db = -14.0
		_sound.max_distance = 500.0
		add_child(_sound)


func _particles(at: Vector2, amount: int, life: float, dir: Vector2, spread: float,
		vmin: float, vmax: float, gravity: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.direction = dir.normalized()
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.emitting = false
	p.z_index = 1
	add_child(p)
	_fx.append(p)
	return p


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	var offs := PackedFloat32Array()
	for i in colors.size():
		offs.append(float(i) / float(colors.size() - 1))
	g.offsets = offs
	return g


## A soft 16 px smoke puff.
func _puff_texture() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 16
	g.height = 16
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	return g


func _light_texture() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = _ramp([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return g
