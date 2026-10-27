extends Node2D
## Placing things you build (scripts/buildables.gd). start(id) shows a see-through
## preview that follows the mouse. Its footprint is drawn on the ground: green
## when it can go there, red when it can't - and everything in the way (trunks,
## rocks, you) gets its collision outline drawn in red. Left click builds it
## (the materials come out of the backpack), right click / Esc / B cancels.
## It can't be placed out of reach, off the map or on top of anything solid.
## Created by main.gd.

signal placed(id: String, node: Node2D)
signal cancelled

const Buildables := preload("res://scripts/buildables.gd")
const OK_COLOR := Color(0.45, 0.95, 0.45)
const BAD_COLOR := Color(1.0, 0.25, 0.22)

var world: Node2D
var player: Node2D
var inventory: Node
var hud: Node
var map_rect := Rect2()
var reach := 140.0                 # how far from you it can be placed (world px)

var active := ""
var _ghost: Node2D
var _valid := false
var _reason := ""
var _blockers: Array = []          # colliders in the way: [CollisionObject2D, ...]


func _ready() -> void:
	z_index = 50                     # above props and the night darkness
	z_as_relative = false


func is_placing() -> bool:
	return active != ""


func start(id: String) -> void:
	cancel(true)
	active = id
	_ghost = _make_ghost(Buildables.ALL[id].scene)
	add_child(_ghost)
	_update()


## Stops placing (quiet = don't fire `cancelled`, e.g. when switching).
func cancel(quiet := false) -> void:
	if active == "":
		return
	active = ""
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_blockers.clear()
	if hud:
		hud.show_prompt(null)
	queue_redraw()
	if not quiet:
		cancelled.emit()


func _process(_delta: float) -> void:
	if active != "":
		_update()


func _unhandled_input(event: InputEvent) -> void:
	if active == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			_try_place()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			cancel()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("build"):
		get_viewport().set_input_as_handled()
		cancel()


func _try_place() -> void:
	_update()
	if not _valid:
		if hud:
			hud.note(_reason, _ghost.global_position + Vector2(0, -40), BAD_COLOR.lightened(0.3))
		return
	var id := active
	var b: Dictionary = Buildables.ALL[id]
	Buildables.pay(id, inventory)
	var node := (load(b.scene) as PackedScene).instantiate() as Node2D
	node.position = world.to_local(_ghost.global_position)
	world.add_child(node)
	cancel(true)
	placed.emit(id, node)


## Where the mouse points, whether it fits there, and what's in the way.
func _update() -> void:
	var b: Dictionary = Buildables.ALL[active]
	var at := get_global_mouse_position().round()
	_ghost.global_position = at
	var centre: Vector2 = at + b.footprint[0]
	var size: Variant = b.footprint[1]          # radius (round) or Vector2 (rectangle)
	var is_rect := size is Vector2
	var half: Vector2 = (size / 2.0) if is_rect else Vector2(size, size)
	_blockers.clear()
	_valid = true
	_reason = ""
	if not Buildables.can_afford(active, inventory):
		_valid = false
		_reason = "Not enough materials"
	elif is_instance_valid(player) and player.global_position.distance_to(at) > reach:
		_valid = false
		_reason = "Too far away"
	elif map_rect.has_area() and not map_rect.grow_individual(-half.x, -half.y, -half.x, -half.y).has_point(centre):
		_valid = false
		_reason = "Off the map"
	# Anything solid under the footprint (also you).
	var shape: Shape2D
	if is_rect:
		shape = RectangleShape2D.new()
		(shape as RectangleShape2D).size = size
	else:
		shape = CircleShape2D.new()
		(shape as CircleShape2D).radius = size
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, centre)
	q.collide_with_bodies = true
	for r in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c := r.collider as CollisionObject2D
		if c and not _blockers.has(c):
			_blockers.append(c)
	if not _blockers.is_empty() and _valid:
		_valid = false
		_reason = "Something is in the way"
	_ghost.modulate = Color(0.7, 1.0, 0.7, 0.75) if _valid else Color(1.0, 0.55, 0.5, 0.6)
	queue_redraw()


func _draw() -> void:
	if active == "" or not is_instance_valid(_ghost):
		return
	var b: Dictionary = Buildables.ALL[active]
	var col := OK_COLOR if _valid else BAD_COLOR
	var centre: Vector2 = to_local(_ghost.global_position + b.footprint[0])
	# Footprint, squashed like the 3/4 ground.
	if b.footprint[1] is Vector2:
		var r := Rect2(centre - b.footprint[1] / 2.0, b.footprint[1])
		draw_rect(r, Color(col, 0.22), true)
		draw_rect(r, col, false, 1.5)
	else:
		_ellipse(centre, b.footprint[1], Color(col, 0.22), true)
		_ellipse(centre, b.footprint[1], col, false)
	# Reach ring around you while it's too far.
	if _reason == "Too far away" and is_instance_valid(player):
		_ellipse(to_local(player.global_position), reach, Color(BAD_COLOR, 0.5), false)
	# The collision of everything in the way, in red.
	for c in _blockers:
		if is_instance_valid(c):
			_draw_collision(c)


## Outlines a body's collision shapes (polygons and circles/rectangles).
func _draw_collision(body: CollisionObject2D) -> void:
	for owner_id in body.get_shape_owners():
		var o := body.shape_owner_get_owner(owner_id)
		if o is CollisionPolygon2D:
			var poly := (o as CollisionPolygon2D).polygon
			var xf: Transform2D = get_global_transform().affine_inverse() * (o as Node2D).global_transform
			var pts := PackedVector2Array()
			for p in poly:
				pts.append(xf * p)
			if pts.size() > 2:
				draw_colored_polygon(pts, Color(BAD_COLOR, 0.25))
				pts.append(pts[0])
				draw_polyline(pts, BAD_COLOR, 1.5)
		elif o is CollisionShape2D and (o as CollisionShape2D).shape:
			var cs := o as CollisionShape2D
			var xf2: Transform2D = get_global_transform().affine_inverse() * cs.global_transform
			if cs.shape is CircleShape2D:
				var r: float = (cs.shape as CircleShape2D).radius * xf2.get_scale().x
				draw_circle(xf2.origin, r, Color(BAD_COLOR, 0.25))
				draw_arc(xf2.origin, r, 0, TAU, 32, BAD_COLOR, 1.5)
			elif cs.shape is RectangleShape2D:
				var e: Vector2 = (cs.shape as RectangleShape2D).size / 2.0
				var pts2 := PackedVector2Array([xf2 * Vector2(-e.x, -e.y), xf2 * Vector2(e.x, -e.y),
						xf2 * Vector2(e.x, e.y), xf2 * Vector2(-e.x, e.y)])
				draw_colored_polygon(pts2, Color(BAD_COLOR, 0.25))
				pts2.append(pts2[0])
				draw_polyline(pts2, BAD_COLOR, 1.5)


func _ellipse(c: Vector2, r: float, color: Color, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * r, sin(a) * r * 0.6))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		draw_polyline(pts, color, 1.5)


## A see-through copy of the scene to show where it will go: only its pictures
## and particles (no script, collision, light or sound).
func _make_ghost(path: String) -> Node2D:
	var g := (load(path) as PackedScene).instantiate() as Node2D
	g.set_script(null)
	for c in g.get_children():
		if c is CollisionObject2D or c is Light2D or c is LightOccluder2D \
				or c is AudioStreamPlayer or c is AudioStreamPlayer2D:
			g.remove_child(c)
			c.free()
		elif c is CPUParticles2D:
			(c as CPUParticles2D).local_coords = true      # sparks move with the preview, no trail
		elif c is Sprite2D and (c as Sprite2D).material is ShaderMaterial:
			# The prop shader reads the tint as colour data: use a plain material so
			# the green/red preview tint shows as it should.
			(c as Sprite2D).material = null
			(c as Sprite2D).self_modulate = Color.WHITE
	return g
