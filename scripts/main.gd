extends Node2D
## Entry point. Builds the night darkness, the player, the map and a small HUD.
## Everything is created in code so the project has no binary/scene assets yet.

const MapGenerator := preload("res://scripts/map_generator.gd")
const Player := preload("res://scripts/player.gd")
## Shared by every prop scene; we feed it the player position so trees fade
## when the player walks behind them.
const PROP_MATERIAL := preload("res://assets/props/prop_material.tres")
## Same fade, plus per-tree colour variation (see scripts/pine.gd).
const PINE_MATERIAL := preload("res://assets/props/pine_material.tres")
const VISION_TEX_SIZE := 512

## false = use the hand-painted World node in main.tscn (default).
## true  = use the old procedural generator (R makes a new random map).
@export var use_generated_map := false

# --- Fog of war ---------------------------------------------------------------
# Select the Main node to tweak these in the Inspector. They also update live
# while the game runs (Remote scene tree -> Main), so you can tune by eye.
@export_group("Fog")
## Start with the fog on (F toggles it in game).
@export var fog_enabled := true:
	set(v):
		fog_enabled = v
		_apply_fog()
## Colour of total darkness outside your vision.
@export var fog_color := Color.BLACK:
	set(v):
		fog_color = v
		_apply_fog()
## How dark the fog gets at its thickest. 1 = completely fog_color (black), 0 = no darkness.
@export_range(0.0, 1.0, 0.01) var fog_darkness := 1.0:
	set(v):
		fog_darkness = v
		_apply_fog()
## How far you can see, in world pixels (the settler is 43 px tall). Beyond this it is fully dark.
@export_range(40.0, 800.0, 1.0, "suffix:px") var vision_radius := 175.0:
	set(v):
		vision_radius = v
		_apply_fog()
## Where the fade to black begins, as a fraction of vision_radius. 0 = darkens right from your feet, 0.9 = clear until a hard edge.
@export_range(0.0, 0.95, 0.01) var fog_start := 0.3:
	set(v):
		fog_start = v
		_apply_fog()
## Fog thickness: how quickly it goes dark once it starts. 1 = even fade, higher = thicker (darkens sooner), lower = thinner.
@export_range(0.2, 6.0, 0.05) var fog_density := 1.5:
	set(v):
		fog_density = v
		_apply_fog()
## Brightness of what you can see.
@export_range(0.0, 3.0, 0.05) var vision_brightness := 1.1:
	set(v):
		vision_brightness = v
		_apply_fog()
## Tint of your vision (slightly cold moonlight by default).
@export var vision_tint := Color(0.9, 0.95, 1.0):
	set(v):
		vision_tint = v
		_apply_fog()
## Height / width of the vision area. Below 1 makes it look round on the tilted 3/4 ground.
@export_range(0.3, 1.0, 0.01) var vision_squash := 0.78:
	set(v):
		vision_squash = v
		_apply_fog()
## Blur on the line-of-sight shadows behind trunks.
@export_range(0.0, 10.0, 0.1) var shadow_softness := 2.0:
	set(v):
		shadow_softness = v
		_apply_fog()
@export_group("")

var map: Node2D
var world: Node2D
var player: CharacterBody2D
var darkness: CanvasModulate
var seed_value := 0

var _hud_label: Label
var _vision_tex: GradientTexture2D


func _ready() -> void:
	_setup_input()

	# Night: everything outside a light source fades to fog_color.
	darkness = CanvasModulate.new()
	add_child(darkness)

	player = Player.new()
	add_child(player)
	_apply_fog()

	_build_hud()
	world = get_node_or_null("World")
	if use_generated_map or world == null:
		if world:
			world.queue_free()
		_new_map(MapGenerator.DEFAULT_SEED)
	else:
		_setup_painted_world()


func _process(_delta: float) -> void:
	if map:
		map.set_player_position(player.global_position)
	else:
		PROP_MATERIAL.set_shader_parameter("player_pos", player.global_position)
		PINE_MATERIAL.set_shader_parameter("player_pos", player.global_position)


## Pushes the Fog settings to the darkness and the player's vision light.
func _apply_fog() -> void:
	if darkness == null or player == null or player.light == null:
		return
	darkness.visible = fog_enabled
	darkness.color = Color.WHITE.lerp(fog_color, fog_darkness)
	var light: PointLight2D = player.light
	light.enabled = fog_enabled
	light.energy = vision_brightness
	light.color = vision_tint
	light.shadow_filter_smooth = shadow_softness
	var tex := _make_vision_texture()
	if light.texture != tex:
		light.texture = tex
	light.texture_scale = vision_radius * 2.0 / VISION_TEX_SIZE


## Radial light texture: fully bright up to fog_start, then fades to zero at the
## edge following fog_density. Outside the light only fog_color remains.
func _make_vision_texture() -> Texture2D:
	if _vision_tex == null:
		_vision_tex = GradientTexture2D.new()
		_vision_tex.fill = GradientTexture2D.FILL_RADIAL
		_vision_tex.fill_from = Vector2(0.5, 0.5)
		_vision_tex.fill_to = Vector2(0.5, 0.0)
		_vision_tex.width = VISION_TEX_SIZE
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	var steps := 32
	for i in steps + 1:
		var t := float(i) / steps
		var k := clampf((t - fog_start) / maxf(1.0 - fog_start, 0.001), 0.0, 1.0)
		var a := pow(1.0 - smoothstep(0.0, 1.0, k), fog_density)
		offsets.append(t)
		colors.append(Color(1, 1, 1, a))
	g.offsets = offsets
	g.colors = colors
	_vision_tex.gradient = g
	_vision_tex.height = maxi(int(VISION_TEX_SIZE * vision_squash), 8)
	return _vision_tex


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate") and map:
		_new_map(randi())
	elif event.is_action_pressed("toggle_fog"):
		fog_enabled = not fog_enabled
	elif event is InputEventMouseButton and event.pressed:
		var cam: Camera2D = player.camera
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = (cam.zoom * 1.15).clamp(Vector2(0.12, 0.12), Vector2(6, 6))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = (cam.zoom / 1.15).clamp(Vector2(0.12, 0.12), Vector2(6, 6))


func _new_map(new_seed: int) -> void:
	seed_value = new_seed
	if map:
		player.reparent(self)       # rescue the player before the old map is freed
		map.queue_free()
	map = MapGenerator.new()
	add_child(map)
	map.generate(seed_value)

	# The player lives in the map's y-sorted node so trees draw in front of or
	# behind them depending on who is lower on the screen.
	player.reparent(map.entities)
	player.global_position = map.get_spawn_point()
	var cam: Camera2D = player.camera
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map.map_size.x)
	cam.limit_bottom = int(map.map_size.y)
	cam.reset_smoothing()

	_hud_label.text = "Seed %d   |   WASD move · Shift sprint · R new map · F toggle fog · Mouse wheel zoom" % seed_value


func _setup_painted_world() -> void:
	# The player joins the World's y-sorted node so trees/props painted there
	# draw in front of or behind them correctly.
	player.reparent(world)
	var spawn := world.get_node_or_null("Spawn")
	player.global_position = spawn.global_position if spawn else Vector2.ZERO
	player.camera.zoom = Vector2(3, 3)         # pixel art: 1 art pixel = 3 screen px
	_add_world_borders()
	player.camera.reset_smoothing()
	_hud_label.text = "WASD move · Shift sprint · F toggle fog · Mouse wheel zoom"


func _add_world_borders() -> void:
	# Invisible walls + camera limits around whatever ground you have painted,
	# so the map edge follows your painting automatically.
	var ground := world.get_node_or_null("Ground") as TileMapLayer
	if ground == null or ground.get_used_rect().size == Vector2i.ZERO:
		return
	var cell := Vector2(ground.tile_set.tile_size)
	var r := ground.get_used_rect()
	var rect := Rect2(ground.to_global(Vector2(r.position) * cell), Vector2(r.size) * cell)
	var t := 64.0
	var body := StaticBody2D.new()
	add_child(body)
	for wall in [
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + 2 * t, t + 12),   # top (walk a bit under the edge)
		Rect2(rect.position.x - t, rect.end.y - 4, rect.size.x + 2 * t, t),
		Rect2(rect.position.x - t, rect.position.y, t + 8, rect.size.y),
		Rect2(rect.end.x - 8, rect.position.y, t, rect.size.y),
	]:
		var shape := RectangleShape2D.new()
		shape.size = wall.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = wall.get_center()
		body.add_child(cs)
	var cam: Camera2D = player.camera
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.end.x)
	cam.limit_bottom = int(rect.end.y)


func _build_hud() -> void:
	# CanvasLayer is not affected by the CanvasModulate darkness.
	var hud := CanvasLayer.new()
	add_child(hud)

	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_hud_label)


func _setup_input() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"regenerate": [KEY_R],
		"toggle_fog": [KEY_F],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
