@tool
extends Node
## Editor helper: select the WorldBuilder node in main.tscn, change the settings
## below and click "Rebuild World". Then save the scene (Ctrl+S).
##
## It replaces the generated parts of World (Ground and Props) and KEEPS
## everything else - Campfire and Spawn where you moved them, plus everything you
## added yourself:
##   - props painted in the World/Placed layer (tents, extra rocks, ...)
##   - scenes you dragged in as direct children of World (e.g. tent.tscn)
## They are kept on every rebuild (editor button and every round in the game),
## and the generator keeps its trees and props clear of them (see the Painted
## Props settings). Only things painted in World/Props are lost. Not undoable with Ctrl+Z: if you don't
## like the result, just close main.tscn without saving.
## In the running game main.gd uses it to generate a fresh forest every round
## from the menu settings (map size + seed); the other settings here still apply.

## Click to regenerate the World with the settings below.
@export_tool_button("Rebuild World", "Reload") var rebuild_button = _on_rebuild_pressed

@export_group("Map")
## Map width/height in ground tiles (1 tile = 105 x 107 px). 40 ~= 4,200 px, 62 ~= 6,500 px.
@export_range(4, 200, 1) var ground_tiles := 100
## Same seed = same forest every rebuild. Change it for a different layout.
@export var map_seed := 67

@export_group("Forest")
## Radius of the open area around the campfire, in px.
@export_range(0.0, 3000.0, 1.0, "suffix:px") var clearing := 300.0
## How gradually the forest thickens after the clearing edge, in px.
@export_range(0.0, 2000.0, 1.0, "suffix:px") var clearing_fade := 200.0
## Distance between candidate tree spots. Lower = denser forest (and more trees to draw).
@export_range(30.0, 500.0, 1.0, "suffix:px") var tree_spacing := 150.0
## Random offset per tree so the forest doesn't look like a grid.
@export_range(0.0, 250.0, 1.0, "suffix:px") var tree_jitter := 150.0
## Chance (0-1) a spot gets a tree where the forest is thickest.
@export_range(0.0, 1.0, 0.01) var forest_fill := 1.0
## Size of thick/thin forest patches. Lower = bigger groves and bigger gaps.
@export_range(0.0002, 0.02, 0.0001) var patch_frequency := 0.02

@export_group("Tree Mix")
# Relative weights of the living pine types (they don't need to add up to 1).
## Big detailed pine (pine_tall.png).
@export_range(0.0, 10.0, 0.05) var tall_pines := 0.5
## Small dark blue-green pine (pine_dark.png).
@export_range(0.0, 10.0, 0.05) var dark_pines := 0.2
## Share of tree spots that get a dead tree instead (0.08 = about 1 in 12).
@export_range(0.0, 1.0, 0.01) var dead_tree_share := 0.08
## Minimum visible gap between two tree trunks (world px). Trunks never touch.
@export_range(0.0, 100.0, 1.0, "suffix:px") var trunk_gap := 8.0

@export_group("Props")
# Amounts per 1000 x 1000 px (about two screens). Props marked "forest" are this
# dense in the thickest forest and thin out with the trees.
## Tree stumps (forest).
@export_range(0.0, 50.0, 0.1) var stumps := 3.0
## Mossy fallen logs (forest).
@export_range(0.0, 50.0, 0.1) var logs := 2.0
## Big mossy boulders that block sight (forest). Some get small rocks around them.
@export_range(0.0, 50.0, 0.1) var boulders := 1.5
## Small mossy rocks (forest and around the clearing edge).
@export_range(0.0, 50.0, 0.1) var mossy_rocks := 3.0
## Ferns, both kinds (mostly forest, a few in the open).
@export_range(0.0, 200.0, 0.5) var ferns := 18.0
## Grass tufts (everywhere, including the clearing).
@export_range(0.0, 200.0, 0.5) var grass_tufts := 22.0
## Small dark bushes you can hide in (forest).
@export_range(0.0, 50.0, 0.1) var small_bushes := 3.0
## Big dark bushes you can hide in (forest).
@export_range(0.0, 50.0, 0.1) var big_bushes := 1.2
## Long fallen trees with roots (forest).
@export_range(0.0, 50.0, 0.1) var fallen_trees := 0.8
## Broken stumps with a snapped-off log (forest).
@export_range(0.0, 50.0, 0.1) var stump_logs := 1.0
## Groups of 2-4 mushrooms (red or brown) at the foot of a pine.
@export_range(0.0, 50.0, 0.1) var mushroom_clusters := 4.0
## Pebbles (everywhere).
@export_range(0.0, 100.0, 0.5) var pebbles := 8.0
## Sticks (everywhere).
@export_range(0.0, 100.0, 0.5) var sticks := 8.0
## Keep this much open ground around the campfire (px).
@export_range(0.0, 400.0, 1.0, "suffix:px") var campfire_space := 60.0

@export_group("Animals")
## Rabbits per million square px (Medium map = about 110 million), placed
## randomly anywhere on the map. 0 = none. Tune their behaviour on assets/characters/rabbit.tscn.
@export_range(0.0, 5.0, 0.01) var rabbits := 0.25

@export_group("Painted Props")
## Generated trees keep their trunks at least this far from props you painted in
## World/Placed (on top of the painted prop's own size). Trees are big, so this
## also keeps their canopies from covering what you painted.
@export_range(0.0, 400.0, 1.0, "suffix:px") var painted_tree_clearance := 60.0
## Other generated props (rocks, logs, bushes, ferns, grass, ...) keep at least
## this far from painted props.
@export_range(0.0, 200.0, 1.0, "suffix:px") var painted_clearance := 16.0
## Also keep trees out of the spot right in front of (below) a painted prop,
## where their tall canopy would hide it. Leaves a small sight-line gap.
@export var keep_painted_visible := true

@export_group("Spawn")
## Where the settler starts, relative to the campfire at the map centre.
@export var spawn_offset := Vector2(0, 70)

const GROUND_TILESET := "res://assets/tiles/ground_tileset.tres"
const PROPS_TILESET := "res://assets/props/props_tileset.tres"
const CAMPFIRE := "res://assets/props/campfire.tscn"
## Per tree type, in ART pixels: [root half-width, visible trunk height below the
## canopy]. Used so trunks never visibly touch. Dead trees show their whole trunk.
const TREE_SHAPE := {
	"pine_tall": [14.0, 32.0],
	"pine_dark": [7.0, 14.0],
	"dead_pine": [13.0, 228.0],
	"dead_tree": [13.0, 175.0],
}


func _ready() -> void:
	# Kept in the running game too: main.gd uses it to generate the forest from
	# the menu settings (map size + seed) at the start of every round.
	pass


func _on_rebuild_pressed() -> void:
	var main := owner if owner else get_parent()
	var placed := rebuild(main)
	var ei := Engine.get_singleton("EditorInterface")
	if ei:
		ei.call("mark_scene_as_unsaved")
	print("World rebuilt: %d x %d tiles, %d props. Save the scene to keep it." % [ground_tiles, ground_tiles, placed])


## Replaces main's World node. Returns the number of props placed.
## Also used by tools/build_world.gd from the command line.
const GENERATED := ["Ground", "Props", "Rabbits"]
const RABBIT := "res://assets/characters/rabbit.tscn"


func rebuild(main: Node) -> int:
	var old := main.get_node_or_null("World")
	var index := old.get_index() if old else 0
	# Everything you added yourself survives the rebuild: take it out before the
	# old World goes (remembering who owns what, so the editor still saves it).
	var placed: TileMapLayer = null
	var kept := []
	var owners := {}
	if old:
		for child in old.get_children():
			if String(child.name) in GENERATED:
				continue
			if child.name == "Placed" and child is TileMapLayer:
				placed = child
			else:
				kept.append(child)
			_remember_owners(child, owners)
			old.remove_child(child)
			child.owner = null              # re-set below, once it sits in the new World
	if old:
		main.remove_child(old)
		old.free()

	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	_add(main, main, world)
	main.move_child(world, index)

	var gts := load(GROUND_TILESET) as TileSet
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = gts
	ground.z_index = -10
	_add(main, world, ground)
	var ground_source := gts.get_source_id(0)
	var half := ground_tiles / 2
	for y in range(-half, ground_tiles - half):
		for x in range(-half, ground_tiles - half):
			ground.set_cell(Vector2i(x, y), ground_source, Vector2i.ZERO)

	var pts := load(PROPS_TILESET) as TileSet
	var props := TileMapLayer.new()
	props.name = "Props"
	props.tile_set = pts
	props.y_sort_enabled = true
	_add(main, world, props)
	if placed == null:
		placed = TileMapLayer.new()
		placed.name = "Placed"
		placed.tile_set = pts
		placed.y_sort_enabled = true
	placed.owner = null
	_add(main, world, placed)
	for n in kept:
		world.add_child(n)
	for n in owners:
		if is_instance_valid(n) and n != placed:
			n.owner = owners[n]
	_keepouts = _painted_keepouts(placed)
	_keepouts.append_array(_node_keepouts(kept))
	var count := _place_props(props, ground)
	_place_rabbits(world, ground)

	# Campfire in the middle of the clearing (instanced, so tweaks in campfire.tscn
	# stay) and the spawn point - only made if there isn't one yet, so if you
	# move them in the editor they stay where you put them.
	if world.get_node_or_null("Campfire") == null:
		var campfire: Node2D = (load(CAMPFIRE) as PackedScene).instantiate()
		campfire.name = "Campfire"
		_add(main, world, campfire)
	if world.get_node_or_null("Spawn") == null:
		var spawn := Marker2D.new()
		spawn.name = "Spawn"
		spawn.position = spawn_offset
		_add(main, world, spawn)
	return count


var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _props: TileMapLayer
var _source := 0
var _ids := {}            # prop name -> scene tile id
var _taken := {}          # cells already holding a prop
var _solid := {}          # 64 px buckets -> [[pos, radius], ...] of trunks/rocks/logs
var _counts := {}
var _trees := {}          # 128 px column buckets -> [[pos, half_width, trunk_height], ...] in world px
var _tree_scale := {}     # tree name -> largest scale it can get (from its scene)
var _keepouts := []       # painted props: [position, radius] the generator stays clear of
var _tree_size := {}      # tree name -> Vector2 sprite size at its largest scale (world px)


func _place_props(props: TileMapLayer, ground: TileMapLayer) -> int:
	_props = props
	_source = props.tile_set.get_source_id(0)
	var coll := props.tile_set.get_source(_source) as TileSetScenesCollectionSource
	_ids.clear()
	for i in coll.get_scene_tiles_count():
		var id := coll.get_scene_tile_id(i)
		_ids[coll.get_scene_tile_scene(id).resource_path.get_file().get_basename()] = id
	if not _ids.has("pine_tall") and not _ids.has("pine_dark"):
		push_error("WorldBuilder: no pine scenes in props_tileset.tres")
		return 0
	var live := {"pine_tall": tall_pines, "pine_dark": dark_pines}
	var live_total := 0.0
	for k in live:
		live_total += live[k] if _ids.has(k) else 0.0
	_rng.seed = map_seed
	_noise.seed = map_seed
	_noise.frequency = patch_frequency
	_taken.clear()
	_solid.clear()
	_counts.clear()
	_trees.clear()
	_tree_scale.clear()
	for name in TREE_SHAPE:
		if _ids.has(name):
			var inst = coll.get_scene_tile_scene(_ids[name]).instantiate()
			_tree_scale[name] = maxf(float(inst.get("max_scale")), float(inst.get("min_scale")))
			var spr := inst.get_node_or_null("Sprite") as Sprite2D
			if spr and spr.texture:
				_tree_size[name] = spr.texture.get_size() * _tree_scale[name]
			inst.free()

	var rect := ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	var area := Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile).grow(-30.0)

	# --- Trees on a jittered grid; density follows noise, ramps up from the clearing.
	# Spots are picked first, then dead trees are placed before living ones:
	# a dead tree shows its whole trunk, so it needs the most room to never touch.
	var spots := []
	var y := area.position.y + 10.0
	while y < area.end.y:
		var x := area.position.x
		while x < area.end.x:
			var p := Vector2(x + _rng.randf_range(-tree_jitter, tree_jitter), y + _rng.randf_range(-tree_jitter, tree_jitter))
			if _rng.randf() < _forest(p) * forest_fill:
				var kind := "pine_tall" if _ids.has("pine_tall") else "pine_dark"
				if _rng.randf() < dead_tree_share:
					kind = "dead_pine" if _rng.randf() < 0.5 else "dead_tree"
				elif live_total > 0.0:
					var roll := _rng.randf() * live_total
					for k in live:
						if not _ids.has(k):
							continue
						roll -= live[k]
						kind = k
						if roll <= 0.0:
							break
				spots.append([kind, p])
			x += tree_spacing
		y += tree_spacing * 0.8      # rows a bit closer: the 3/4 view squashes depth
	var trunks: Array[Vector2] = []
	for dead_pass in [true, false]:
		for s in spots:
			if String(s[0]).begins_with("dead") == dead_pass and _put_tree(s[0], s[1]) and not dead_pass:
				trunks.append(s[1])

	# --- Solid forest props (kept clear of trunks and each other).
	var per := area.get_area() / 1_000_000.0
	for i in int(boulders * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p) and _put("boulder", p, 20.0):
			for k in _rng.randi_range(0, 2):       # a few small rocks around some boulders
				_put("mossy_rock", p + Vector2.from_angle(_rng.randf() * TAU) * Vector2(_rng.randf_range(26, 38), _rng.randf_range(14, 22)), 11.0)
	for i in int(logs * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p):
			_put("log", p, 30.0)
	for i in int(fallen_trees * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p):
			_put("fallen_tree", p, 56.0)
	for i in int(stump_logs * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p):
			_put("stump_log", p, 38.0)
	for i in int(big_bushes * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p):
			_put("bush_big", p, 30.0)
	for i in int(small_bushes * per):
		var p := _random_point(area)
		if _rng.randf() < 0.3 + 0.7 * _forest(p):
			_put("bush_small", p, 18.0)
	for i in int(stumps * per):
		var p := _random_point(area)
		if _rng.randf() < _forest(p):
			_put("stump", p, 14.0)
	for i in int(mossy_rocks * per):
		var p := _random_point(area)
		var edge := 1.0 - clampf(absf(p.length() - clearing) / 160.0, 0.0, 1.0)   # also ring the clearing
		if _rng.randf() < maxf(_forest(p), edge):
			_put("mossy_rock", p, 11.0)

	# --- Mushrooms in small groups at the foot of a pine.
	for i in int(mushroom_clusters * per):
		if trunks.is_empty():
			break
		var t: Vector2 = trunks[_rng.randi() % trunks.size()]
		var c := t + Vector2.from_angle(_rng.randf() * TAU) * Vector2(_rng.randf_range(22, 34), _rng.randf_range(12, 20))
		var kind := "mushroom" if _rng.randf() < 0.5 else "mushroom_brown"   # one kind per group
		for k in _rng.randi_range(2, 4):
			_put(kind, c + Vector2(_rng.randf_range(-9, 9), _rng.randf_range(-5, 5)), 0.0)

	# --- Ground cover (walk through).
	for i in int(ferns * per):
		var p := _random_point(area)
		if _rng.randf() < 0.2 + 0.8 * _forest(p):
			_put("fern_a" if _rng.randf() < 0.5 else "fern_b", p, 0.0)
	for i in int(grass_tufts * per):
		_put("grass_tuft", _random_point(area), 0.0)
	for i in int(pebbles * per):
		_put("pebble", _random_point(area), 0.0)
	for i in int(sticks * per):
		_put("stick", _random_point(area), 0.0)

	print("WorldBuilder placed: ", _counts)
	return _taken.size()


## Rabbits: scattered randomly over the whole map (evenly), just never inside a
## trunk, rock, log, the fire pit or one of your painted props. They live in
## World/Rabbits, which is rebuilt every time (and not saved in main.tscn).
func _place_rabbits(world: Node, ground: TileMapLayer) -> void:
	if rabbits <= 0.0 or not ResourceLoader.exists(RABBIT):
		return
	var scene := load(RABBIT) as PackedScene
	var holder := Node2D.new()
	holder.name = "Rabbits"
	holder.y_sort_enabled = true
	world.add_child(holder)                        # no owner: not saved, made fresh each round
	var rect := ground.get_used_rect()
	var tile := Vector2(ground.tile_set.tile_size)
	var area := Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile).grow(-60.0)
	var want := int(rabbits * area.get_area() / 1_000_000.0)
	var placed := 0
	var tries := 0
	while placed < want and tries < want * 30:
		tries += 1
		var p := _random_point(area)
		# Anywhere on the map, as long as it isn't inside something solid.
		if p.length() < campfire_space or _near_painted(p, 12.0) or _blocked(p, 6.0):
			continue
		var r: Node2D = scene.instantiate()
		r.position = p
		holder.add_child(r)
		placed += 1


## True if p (with radius r) overlaps a generated trunk/rock/log.
func _blocked(p: Vector2, r: float) -> bool:
	var b := Vector2i((p / 64.0).floor())
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for o in _solid.get(b + Vector2i(dx, dy), []):
				if p.distance_to(o[0]) < r + o[1]:
					return true
	return false


## Forest thickness 0..1 at p: noise patches, zero in the clearing.
func _forest(p: Vector2) -> float:
	return clampf(0.6 + _noise.get_noise_2dv(p) * 0.9, 0.15, 1.0) \
			* smoothstep(clearing, clearing + clearing_fade, p.length())


func _random_point(area: Rect2) -> Vector2:
	return Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))


## Painted props (World/Placed) -> [position, radius] areas to keep clear.
## The radius is half the prop's widest possible size (its art x max_scale).
func _painted_keepouts(placed: TileMapLayer) -> Array:
	var out := []
	if placed == null or placed.tile_set == null:
		return out
	var sizes := {}           # scene path -> radius (instantiate each prop type once)
	for cell in placed.get_used_cells():
		var src := placed.get_cell_source_id(cell)
		var coll := placed.tile_set.get_source(src) as TileSetScenesCollectionSource
		if coll == null:
			continue
		var scene := coll.get_scene_tile_scene(placed.get_cell_alternative_tile(cell))
		if scene == null:
			continue
		if not sizes.has(scene.resource_path):
			var inst := scene.instantiate()
			var r := 8.0
			var sprite := inst.get_node_or_null("Sprite") as Sprite2D
			if sprite and sprite.texture:
				var sc := maxf(float(inst.get("max_scale") if inst.get("max_scale") != null else 1.0), 1.0)
				r = sprite.texture.get_width() * 0.5 * sc
			inst.free()
			sizes[scene.resource_path] = r
		out.append([placed.to_global(placed.map_to_local(cell)), sizes[scene.resource_path]])
	return out


## Scenes dragged straight into World (not painted) -> [position, radius] areas.
func _node_keepouts(nodes: Array) -> Array:
	var out := []
	for n in nodes:
		if not (n is Node2D):
			continue
		var r := 8.0
		var sprite: Sprite2D = n.get_node_or_null("Sprite") as Sprite2D
		if sprite == null:
			for c in n.get_children():
				if c is Sprite2D:
					sprite = c
					break
		if sprite and sprite.texture:
			var sc := maxf(float(n.get("max_scale")) if n.get("max_scale") != null else absf(n.scale.x), absf(n.scale.x))
			r = sprite.texture.get_width() * 0.5 * maxf(sc, 0.01)
		out.append([n.global_position, r])
	return out


func _remember_owners(n: Node, owners: Dictionary) -> void:
	if n.owner:
		owners[n] = n.owner
	for c in n.get_children():
		_remember_owners(c, owners)


## True if p (with this extra radius) is too close to a painted prop.
func _near_painted(p: Vector2, extra: float) -> bool:
	for k in _keepouts:
		var d: Vector2 = p - k[0]
		# Flatter in y (3/4 view): a prop is wider on screen than it is deep.
		if Vector2(d.x, d.y * 1.6).length() < k[1] + extra:
			return true
	return false


## True if a tree at p would stand in front of (below) a painted prop and its
## canopy would cover it on screen.
func _hides_painted(kind: String, p: Vector2) -> bool:
	if not keep_painted_visible or not _tree_size.has(kind):
		return false
	var size: Vector2 = _tree_size[kind]
	for k in _keepouts:
		var q: Vector2 = k[0]
		var r: float = k[1]
		if p.y <= q.y:
			continue                                  # behind the prop: drawn behind it
		if p.y - size.y > q.y:
			continue                                  # far enough in front: canopy ends below it
		if absf(p.x - q.x) < size.x * 0.4 + r + 8.0:  # canopy is a bit narrower than the sprite
			return true
	return false


## Places a tree only if its trunk can't visibly touch another tree's trunk:
## two trees overlap when they are closer sideways than their root widths (+ gap)
## AND the back one's base lies within the front one's visible trunk height.
## Uses each tree's largest possible size, so it holds whatever size they roll.
func _put_tree(kind: String, p: Vector2) -> bool:
	if not _ids.has(kind) or not TREE_SHAPE.has(kind):
		return false
	p = _props.map_to_local(_props.local_to_map(p))     # where it will actually stand
	var sc: float = _tree_scale.get(kind, 2.6)
	if _near_painted(p, painted_tree_clearance) or _hides_painted(kind, p):
		return false
	var hw: float = TREE_SHAPE[kind][0] * sc
	var th: float = TREE_SHAPE[kind][1] * sc
	var col := int(floor(p.x / 128.0))
	for c in range(col - 1, col + 2):
		for o in _trees.get(c, []):
			var q: Vector2 = o[0]
			if absf(p.x - q.x) >= hw + o[1] + trunk_gap:
				continue
			var front_h: float = th if p.y >= q.y else o[2]
			if absf(p.y - q.y) < front_h + trunk_gap:
				return false
	# Also keeps rocks/logs/stumps off the root flare (they check _solid).
	if not _put(kind, p, hw):
		return false
	_trees.get_or_add(col, []).append([p, hw, th])
	return true


## Places a prop if its cell is free, it's outside the campfire space and (for
## solid props, radius > 0) it doesn't overlap a trunk/rock/log.
func _put(prop: String, p: Vector2, radius: float) -> bool:
	if not _ids.has(prop) or p.length() < campfire_space + radius:
		return false
	if _near_painted(p, radius + painted_clearance):
		return false
	var cell := _props.local_to_map(p)
	if _taken.has(cell):
		return false
	if radius > 0.0:
		var b := Vector2i((p / 64.0).floor())
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for o in _solid.get(b + Vector2i(dx, dy), []):
					if p.distance_to(o[0]) < radius + o[1] + 4.0:
						return false
		_solid.get_or_add(b, []).append([p, radius])
	_taken[cell] = true
	_props.set_cell(cell, _source, Vector2i.ZERO, _ids[prop])
	_counts[prop] = _counts.get(prop, 0) + 1
	return true


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
