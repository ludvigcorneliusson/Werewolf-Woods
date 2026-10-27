extends Node2D
## Placing things you build (scripts/buildables.gd). start(id) shows a see-through
## preview that follows the mouse. Its footprint is drawn on the ground: green
## when it can go there, red when it can't - and everything in the way (trunks,
## rocks, you) gets its collision outline drawn in red. Left click builds it
## (the materials come out of the backpack), right click / Esc / B cancels.
## It can't be placed out of reach, off the map or on top of anything solid.
## Buildables with "variants" (walls): R cycles them, they sit on a grid
## (GRID px) and an end that comes near the end of a built wall (SNAP px)
## clicks onto it, so walls join up into a fence line.
## Created by main.gd.

signal placed(id: String, node: Node2D)
signal cancelled

const Buildables := preload("res://scripts/buildables.gd")
const OK_COLOR := Color(0.45, 0.95, 0.45)
const BAD_COLOR := Color(1.0, 0.25, 0.22)
const END_COLOR := Color(1.0, 0.85, 0.35)
## Walls: grid step and how close an end must come to a built wall's end to join it.
const GRID := 4.0
const SNAP := 30.0
## Walls: the ground strip checked for room stops this far short of each end and
## is this thick (so walls can meet end to end).
const WALL_INSET := 5.0
const WALL_THICK := 4.0

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
var _variant := 0                  # which of the buildable's "variants" (R)
var _ends: Array = []              # the variant's two ends (local), [] = not a wall
var _joined: Array = []            # built walls the preview is snapped onto
var _last_variant := {}            # id -> variant, remembered between builds


func _ready() -> void:
	z_index = 50                     # above props and the night darkness
	z_as_relative = false


func is_placing() -> bool:
	return active != ""


func start(id: String) -> void:
	cancel(true)
	active = id
	_variant = int(_last_variant.get(id, 0))
	_rebuild_ghost()


## The scene being placed (the chosen variant, for walls).
func _scene() -> String:
	var b: Dictionary = Buildables.ALL[active]
	var v: Array = b.get("variants", [])
	return v[_variant % v.size()] if not v.is_empty() else b.scene


func _rebuild_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.free()
	var packed := load(_scene()) as PackedScene
	_ghost = _make_ghost(_scene())
	add_child(_ghost)
	_ends = []
	var probe := packed.instantiate()
	if probe.has_meta("wall_ends"):
		_ends = probe.get_meta("wall_ends")
	probe.free()
	_update()


## Footprint: [centre offset, radius or Vector2 size, angle].
func _footprint() -> Array:
	if _ends.size() == 2:
		var a: Vector2 = _ends[0]
		var b: Vector2 = _ends[1]
		return [(a + b) / 2.0, Vector2(maxf(a.distance_to(b) - WALL_INSET * 2.0, 2.0), WALL_THICK), (b - a).angle()]
	var fp: Array = Buildables.ALL[active].footprint
	return [fp[0], fp[1], 0.0]


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
	elif event.is_action_pressed("rotate") and Buildables.ALL[active].has("variants"):
		get_viewport().set_input_as_handled()
		_variant = (_variant + 1) % (Buildables.ALL[active].variants as Array).size()
		_last_variant[active] = _variant
		_rebuild_ghost()
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
	var node := (load(_scene()) as PackedScene).instantiate() as Node2D
	node.position = world.to_local(_ghost.global_position)
	world.add_child(node)
	if b.has("variants") and Buildables.can_afford(id, inventory):
		placed.emit(id, node)                  # walls: keep placing the next one
		_update()
		return
	cancel(true)
	placed.emit(id, node)


## Where the mouse points, whether it fits there, and what's in the way.
func _update() -> void:
	var at := get_global_mouse_position().round()
	_joined.clear()
	if _ends.size() == 2:
		at = _snap_wall(at)
	_ghost.global_position = at
	var fp := _footprint()
	var centre: Vector2 = at + fp[0]
	var size: Variant = fp[1]                   # radius (round) or Vector2 (rectangle)
	var angle: float = fp[2]
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
	q.transform = Transform2D(angle, centre)
	q.collide_with_bodies = true
	for r in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var c := r.collider as CollisionObject2D
		if c and _joined.has(c.get_parent()):
			continue                               # the wall it joins onto, end to end
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
	var col := OK_COLOR if _valid else BAD_COLOR
	var fp := _footprint()
	var centre: Vector2 = to_local(_ghost.global_position + fp[0])
	# Footprint, squashed like the 3/4 ground.
	if fp[1] is Vector2:
		var e: Vector2 = fp[1] / 2.0
		var xf := Transform2D(fp[2], centre)
		var pts := PackedVector2Array([xf * Vector2(-e.x, -e.y), xf * Vector2(e.x, -e.y),
				xf * Vector2(e.x, e.y), xf * Vector2(-e.x, e.y)])
		draw_colored_polygon(pts, Color(col, 0.22))
		pts.append(pts[0])
		draw_polyline(pts, col, 1.5)
	else:
		_ellipse(centre, fp[1], Color(col, 0.22), true)
		_ellipse(centre, fp[1], col, false)
	# Walls: both ends (filled when joined to a built wall) and the ends of the
	# built walls nearby it can join.
	if _ends.size() == 2:
		for w in get_tree().get_nodes_in_group("walls"):
			var wn := w as Node2D
			if wn.global_position.distance_to(_ghost.global_position) > 120.0:
				continue
			for e2: Vector2 in wn.get_meta("wall_ends", []):
				draw_arc(to_local(wn.global_position + e2), 2.5, 0, TAU, 12, Color(END_COLOR, 0.6), 1.0)
		for e1: Vector2 in _ends:
			var p := to_local(_ghost.global_position + e1)
			var hit := false
			for w in _joined:
				for e2: Vector2 in (w as Node2D).get_meta("wall_ends", []):
					if ((w as Node2D).global_position + e2).distance_to(_ghost.global_position + e1) < 0.5:
						hit = true
			if hit:
				draw_circle(p, 3.0, END_COLOR)
			else:
				draw_arc(p, 3.0, 0, TAU, 12, END_COLOR, 1.5)
		var font := ThemeDB.fallback_font
		var hint := "R: turn  (%d/%d)" % [_variant + 1, (Buildables.ALL[active].variants as Array).size()]
		var w := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		var hp := (centre + Vector2(-w / 2.0, 16.0)).round()
		draw_string_outline(font, hp, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color(0, 0, 0, 0.8))
		draw_string(font, hp, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.9))
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


## Walls: on the grid, or - if one of its ends comes within SNAP of a built
## wall's end - moved so the two ends meet. Fills _joined.
func _snap_wall(at: Vector2) -> Vector2:
	var best := INF
	var best_at := Vector2((at / GRID).round() * GRID)
	for w in get_tree().get_nodes_in_group("walls"):
		var wn := w as Node2D
		if wn.global_position.distance_to(at) > 120.0:
			continue
		for e2: Vector2 in wn.get_meta("wall_ends", []):
			var target := wn.global_position + e2
			for e1: Vector2 in _ends:
				var d := (at + e1).distance_to(target)
				if d < SNAP and d < best:
					best = d
					best_at = target - e1
	if best < INF:
		# Every built wall that has an end exactly where one of ours lands.
		for w in get_tree().get_nodes_in_group("walls"):
			var wn := w as Node2D
			for e2: Vector2 in wn.get_meta("wall_ends", []):
				for e1: Vector2 in _ends:
					if (best_at + e1).distance_to(wn.global_position + e2) < 0.5 and not _joined.has(wn):
						_joined.append(wn)
	return best_at


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
	for grp in g.get_groups():
		g.remove_from_group(grp)                  # e.g. "walls": the preview isn't a built wall
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
