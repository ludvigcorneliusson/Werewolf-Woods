extends Node
## Picking things up. Stones and twigs already lying in the forest (pebble and
## stick props, see "prop" in scripts/items.gd) and items dropped in the world
## (logs and twigs from felled trees, spawn_drop) can be picked up: walk close,
## the nearest one gets an "E" prompt (hud.gd), press E and it goes into the
## backpack (inventory.gd). Created by main.gd.

const Items := preload("res://scripts/items.gd")
const VARIED_MATERIAL := preload("res://assets/props/varied_material.tres")
const GROUP := "pickups"
const CELL := 64.0

var player: Node2D
var world: Node2D
var inventory: Node
var hud: Node
var enabled := true
var reach := 30.0                 # world px from the feet
var interact_reach := 52.0        # fires and torches (they're solid, so a bit further)
var lifetime := 30.0              # seconds a dropped item stays on the ground (0 = forever)

var _grid := {}                   # Vector2i cell -> Array of prop nodes that are items
var _layers: Array[Node] = []
var _pending: Array[Node] = []     # props added since the last index update
var _target: Node2D


func _process(_delta: float) -> void:
	_target = null
	if not enabled or not is_instance_valid(player) or not is_instance_valid(world):
		if hud:
			hud.show_prompt(null)
		return
	if player.get("chopping") or not player.get("input_enabled") or not player.is_physics_processing():
		hud.show_prompt(null)
		return
	_target = _nearest()
	if _target:
		var h: float = float(_target.get("prompt_height")) if _target.is_in_group("interactables") else _height(_target)
		hud.show_prompt(_target.global_position + Vector2(0, -h - 12))
	else:
		hud.show_prompt(null)


## E pressed: pick up the nearest item (if there's room in the backpack).
func try_pick() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _target.is_in_group("interactables"):
		var what: String = _target.call("interact")
		if what != "":
			hud.note(what, _target.global_position + Vector2(0, -float(_target.get("prompt_height")) - 16))
		return
	var id := _item_of(_target)
	if id == "":
		return
	if not inventory.can_add(id):
		hud.note("Backpack full", _target.global_position + Vector2(0, -20), Color(1.0, 0.6, 0.5))
		return
	inventory.add(id, 1)
	hud.note("+1 " + Items.display_name(id), _target.global_position + Vector2(0, -20))
	_fly_to_player(_target)
	_remove(_target)
	_target = null


## Drops an item on the ground at `at`. With `from`, it pops out of that point
## in a little arc (e.g. off a falling tree). expires = false: stays until picked
## up (things you throw out of the backpack yourself).
func spawn_drop(id: String, at: Vector2, from: Variant = null, expires := true) -> Node2D:
	var item := Items.get_item(id)
	if item.is_empty() or not item.has("world"):
		return null
	var n := Node2D.new()
	n.name = "Drop_" + id
	n.set_meta("item_id", id)
	n.add_to_group(GROUP)
	var s := Sprite2D.new()
	s.name = "Sprite"
	s.texture = item.world
	s.centered = false
	var sz: Vector2 = item.world.get_size()
	s.offset = Vector2(-floorf(sz.x / 2.0), -sz.y + 2)
	s.material = VARIED_MATERIAL                     # darkened at night like the props
	if item.get("gleam", false):
		s.material = preload("res://assets/props/silver_material.tres") if id.begins_with("silver") \
				else preload("res://assets/props/ore_material.tres")   # ore glints
	s.self_modulate = Color(0.5, 0.5, 0.5, 0.5)       # = no colour change, no sway
	s.flip_h = randf() < 0.5
	n.add_child(s)
	n.scale = Vector2.ONE * float(item.get("world_scale", 1.0))
	world.add_child(n)
	n.global_position = _free_spot(at)
	if lifetime > 0.0 and expires:
		get_tree().create_timer(lifetime, false).timeout.connect(_expire.bind(n))
	if from != null:
		# Pop out: slide from `from` to the spot while hopping up and down.
		var start: Vector2 = from
		var end := n.global_position
		n.global_position = start
		var t := n.create_tween().set_parallel()
		t.tween_property(n, "global_position", end, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		var hop := n.create_tween()
		hop.tween_property(s, "position:y", -18.0 / n.scale.y, 0.2).set_ease(Tween.EASE_OUT)
		hop.tween_property(s, "position:y", 0.0, 0.25).set_ease(Tween.EASE_IN)
	return n


## The dropped item is gone. Map stones and sticks never expire - only drops.
func _expire(n: Node2D) -> void:
	if is_instance_valid(n):
		n.queue_free()


# --- finding items -----------------------------------------------------------------

func _nearest() -> Node2D:
	_reindex_if_needed()
	var feet := player.global_position
	var best: Node2D = null
	var best_d := reach
	for n in get_tree().get_nodes_in_group(GROUP):
		var d := _dist(n as Node2D, feet)
		if d < best_d:
			best_d = d
			best = n
	# Fires and torches you can put out / light (scripts/campfire.gd).
	for n in get_tree().get_nodes_in_group("interactables"):
		var d := _dist(n as Node2D, feet) * reach / interact_reach   # compared on the same scale
		if d < best_d:
			best_d = d
			best = n
	var c0 := Vector2i(((feet - Vector2(reach, reach)) / CELL).floor())
	var c1 := Vector2i(((feet + Vector2(reach, reach)) / CELL).floor())
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for n in _grid.get(Vector2i(cx, cy), []):
				if not is_instance_valid(n):
					continue
				var d := _dist(n, feet)
				if d < best_d:
					best_d = d
					best = n
	return best


func _dist(n: Node2D, feet: Vector2) -> float:
	var r := n.global_position - feet
	return Vector2(r.x, r.y * 1.4).length()            # flatter: 3/4 view


func _item_of(n: Node) -> String:
	if n.has_meta("item_id"):
		return n.get_meta("item_id")
	return Items.item_for_prop(_image(n))


func _image(n: Node) -> String:
	var s := n.get_node_or_null("Sprite") as Sprite2D
	return s.texture.resource_path.get_file() if s and s.texture else ""


func _height(n: Node2D) -> float:
	var s := n.get_node_or_null("Sprite") as Sprite2D
	if s == null or s.texture == null:
		return 10.0
	return s.texture.get_height() * absf(n.global_scale.y)


## Index the item props (pebbles, sticks) in World/Props and World/Placed by map
## cell, so finding the nearest one is cheap. Redone when props come or go.
func _reindex_if_needed() -> void:
	var layers: Array[Node] = []
	for layer_name in ["Props", "Placed"]:
		var l := world.get_node_or_null(layer_name) if is_instance_valid(world) else null
		if l:
			layers.append(l)
	if layers != _layers:
		# New map: index everything once, then follow the layers' child signals
		# (re-indexing ~13k props whenever one came or went froze the game).
		_layers = layers
		_grid.clear()
		_pending.clear()
		for l in _layers:
			if not l.child_entered_tree.is_connected(_on_prop_added):
				l.child_entered_tree.connect(_on_prop_added)
				l.child_exiting_tree.connect(_on_prop_removed)
			for c in l.get_children():
				_index_prop(c)
	for c in _pending:
		if is_instance_valid(c) and c.is_inside_tree():
			_index_prop(c)
	_pending.clear()


func _index_prop(c: Node) -> void:
	if c is Node2D and Items.item_for_prop(_image(c)) != "":
		var cell := Vector2i((c.global_position / CELL).floor())
		if not _grid.has(cell):
			_grid[cell] = []
		if not _grid[cell].has(c):
			_grid[cell].append(c)


## Indexed a frame later (scene tiles get their position as they're added).
func _on_prop_added(c: Node) -> void:
	_pending.append(c)


func _on_prop_removed(c: Node) -> void:
	if c is Node2D:
		var cell := Vector2i(((c as Node2D).global_position / CELL).floor())
		if _grid.has(cell):
			_grid[cell].erase(c)


# --- removing ----------------------------------------------------------------------

func _remove(n: Node2D) -> void:
	if n.is_in_group(GROUP):
		n.queue_free()
		return
	var cell := Vector2i((n.global_position / CELL).floor())
	if _grid.has(cell):
		_grid[cell].erase(n)
	var layer := n.get_parent() as TileMapLayer
	if layer and n.position == layer.map_to_local(layer.local_to_map(n.position)):
		layer.erase_cell(layer.local_to_map(n.position))    # a painted/generated scene tile
	else:
		n.queue_free()


## A copy of the item's picture that flies into the settler and vanishes.
func _fly_to_player(n: Node2D) -> void:
	var src := n.get_node_or_null("Sprite") as Sprite2D
	if src == null:
		return
	var s := Sprite2D.new()
	s.texture = src.texture
	s.centered = false
	s.offset = src.offset
	s.flip_h = src.flip_h
	s.z_index = 2
	world.add_child(s)
	s.global_position = n.global_position
	s.global_scale = n.global_scale
	var t := s.create_tween().set_parallel()
	t.tween_property(s, "global_position", player.global_position + Vector2(0, -14), 0.18).set_ease(Tween.EASE_IN)
	t.tween_property(s, "scale", s.scale * 0.3, 0.18)
	t.chain().tween_callback(s.queue_free)


## Nudges a drop spot out of tree trunks and rocks so you can reach it.
func _free_spot(at: Vector2) -> Vector2:
	var space := world.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collide_with_bodies = true
	for i in 6:
		var p := at + (Vector2(randf_range(-1, 1), randf_range(0.2, 1)) * 14.0 * i if i > 0 else Vector2.ZERO)
		q.position = p
		var blocked := false
		for r in space.intersect_point(q, 4):
			if r.collider != player:
				blocked = true
				break
		if not blocked:
			return p
	return at
