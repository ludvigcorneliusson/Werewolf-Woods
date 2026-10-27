extends Node
## Bends plants (props with bend > 0 in scripts/varied_prop.gd: ferns, grass,
## mushrooms) away from the settler when he walks through them, then lets them
## spring back with a small wobble. Only plants near the player are touched each
## frame, so it stays cheap with thousands of plants.
## Created by main.gd, which passes in its Plants settings.

const CELL := 64.0

var player: CharacterBody2D
var props: Node              # World/Props TileMapLayer (plants are its children)
var placed: Node             # World/Placed: your painted props (optional)
var walk_speed := 120.0

var push_strength := 0.45    # max lean in radians at full bend, walking speed
var push_radius := 20.0      # world px from the feet
var spring := 140.0          # how hard plants pull back upright
var damping := 7.0           # higher = less wobble

var _grid := {}              # Vector2i cell -> Array of [Node2D prop, Sprite2D, bend]
var _active := {}            # Sprite2D -> [angle, velocity]
var _indexed_count := -1


func _physics_process(delta: float) -> void:
	if player == null or props == null:
		return
	if _child_count() != _indexed_count:
		_index()

	var feet := player.global_position
	var speed_factor := clampf(player.velocity.length() / walk_speed, 0.0, 2.0)
	var reach := push_radius + 8.0
	var touched := {}
	var c0 := Vector2i(((feet - Vector2(reach, reach)) / CELL).floor())
	var c1 := Vector2i(((feet + Vector2(reach, reach)) / CELL).floor())
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for entry in _grid.get(Vector2i(cx, cy), []):
				var prop: Node2D = entry[0]
				if not is_instance_valid(prop):
					continue
				var rel: Vector2 = prop.global_position - feet
				var d := Vector2(rel.x, rel.y * 1.6).length()     # flatter: 3/4 view
				if d >= push_radius:
					continue
				var sprite: Sprite2D = entry[1]
				var dir := signf(rel.x)
				if absf(rel.x) < 1.5:
					dir = signf(player.velocity.x) if absf(player.velocity.x) > 1.0 else 1.0
				var amount := 1.0 - d / push_radius
				# Standing still bends a little, running through bends more.
				var target := dir * push_strength * float(entry[2]) * amount * (0.4 + 0.6 * speed_factor)
				touched[sprite] = target
				if not _active.has(sprite):
					_active[sprite] = [0.0, 0.0]

	for sprite: Sprite2D in _active.keys():
		if not is_instance_valid(sprite):
			_active.erase(sprite)
			continue
		var st: Array = _active[sprite]
		var target: float = touched.get(sprite, 0.0)
		var acc: float = (target - st[0]) * spring - st[1] * damping
		st[1] += acc * delta
		st[0] += st[1] * delta
		if not touched.has(sprite) and absf(st[0]) < 0.002 and absf(st[1]) < 0.02:
			sprite.skew = 0.0
			_active.erase(sprite)
		else:
			sprite.skew = st[0]       # positive = top leans right (origin = foot)


func _child_count() -> int:
	return props.get_child_count() + (placed.get_child_count() if is_instance_valid(placed) else 0)


func _index() -> void:
	_grid.clear()
	_indexed_count = _child_count()
	var all_props := props.get_children()
	if is_instance_valid(placed):
		all_props.append_array(placed.get_children())
	for prop in all_props:
		var b = prop.get("bend")
		if b == null or float(b) <= 0.0:
			continue
		var sprite := prop.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			continue
		var cell := Vector2i((prop.global_position / CELL).floor())
		_grid.get_or_add(cell, []).append([prop, sprite, float(b)])
