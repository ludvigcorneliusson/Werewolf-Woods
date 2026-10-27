extends Node2D
## Entry point. Builds the night darkness, the player, the map and a small HUD.
## Everything is created in code so the project has no binary/scene assets yet.

const MapGenerator := preload("res://scripts/map_generator.gd")
const Player := preload("res://scripts/player.gd")
## Shared by every prop scene; we feed it the player position so trees fade
## when the player walks behind them.
const PROP_MATERIAL := preload("res://assets/props/prop_material.tres")

## false = use the hand-painted World node in main.tscn (default).
## true  = use the old procedural generator (R makes a new random map).
@export var use_generated_map := false

var map: Node2D
var world: Node2D
var player: CharacterBody2D
var darkness: CanvasModulate
var fog_enabled := true
var seed_value := 0

var _hud_label: Label
var _stamina_bar: ProgressBar


func _ready() -> void:
	_setup_input()

	# Night: everything outside a light source is tinted almost black.
	darkness = CanvasModulate.new()
	darkness.color = Color(0.07, 0.08, 0.13)
	add_child(darkness)

	player = Player.new()
	add_child(player)

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
	_stamina_bar.value = player.stamina
	_stamina_bar.modulate = Color(1, 0.4, 0.4) if player.exhausted else Color(1, 1, 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate") and map:
		_new_map(randi())
	elif event.is_action_pressed("toggle_fog"):
		fog_enabled = not fog_enabled
		darkness.visible = fog_enabled
		player.light.enabled = fog_enabled
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

	_stamina_bar = ProgressBar.new()
	_stamina_bar.position = Vector2(16, 44)
	_stamina_bar.size = Vector2(220, 14)
	_stamina_bar.max_value = 100
	_stamina_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.75, 0.35)
	fill.set_corner_radius_all(4)
	_stamina_bar.add_theme_stylebox_override("background", bg)
	_stamina_bar.add_theme_stylebox_override("fill", fill)
	hud.add_child(_stamina_bar)


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
