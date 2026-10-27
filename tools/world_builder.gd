@tool
extends Node
## Editor helper: select the WorldBuilder node in main.tscn, change the settings
## below and click "Rebuild World". Then save the scene (Ctrl+S).
##
## It replaces the World node (ground, pine forest, campfire, spawn) - anything
## you painted by hand in World is lost. Not undoable with Ctrl+Z: if you don't
## like the result, just close main.tscn without saving.
## It does nothing in the running game.

## Click to regenerate the World with the settings below.
@export_tool_button("Rebuild World", "Reload") var rebuild_button = _on_rebuild_pressed

@export_group("Map")
## Map width/height in grass tiles (1 tile = 131 px). 30 ~= 3,900 px, 50 ~= 6,500 px.
@export_range(4, 200, 1) var ground_tiles := 80
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

@export_group("Spawn")
## Where the settler starts, relative to the campfire at the map centre.
@export var spawn_offset := Vector2(0, 70)

const GROUND_TILESET := "res://assets/tiles/ground_tileset.tres"
const PROPS_TILESET := "res://assets/props/props_tileset.tres"
const CAMPFIRE := "res://assets/props/campfire.tscn"


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()


func _on_rebuild_pressed() -> void:
	var main := owner if owner else get_parent()
	var trees := rebuild(main)
	var ei := Engine.get_singleton("EditorInterface")
	if ei:
		ei.call("mark_scene_as_unsaved")
	print("World rebuilt: %d x %d tiles, %d pines. Save the scene to keep it." % [ground_tiles, ground_tiles, trees])


## Replaces main's World node. Returns the number of trees placed.
## Also used by tools/build_world.gd from the command line.
func rebuild(main: Node) -> int:
	var old := main.get_node_or_null("World")
	var index := old.get_index() if old else 0
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
	var trees := _place_forest(props, ground)

	# Campfire in the middle of the clearing (instanced, so tweaks in campfire.tscn stay).
	var campfire: Node2D = (load(CAMPFIRE) as PackedScene).instantiate()
	campfire.name = "Campfire"
	_add(main, world, campfire)

	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = spawn_offset
	_add(main, world, spawn)
	return trees


func _place_forest(props: TileMapLayer, ground: TileMapLayer) -> int:
	# Pines only. Density follows noise so there are thick stands and thinner
	# patches, and ramps up from the clearing edge.
	var source := props.tile_set.get_source_id(0)
	var coll := props.tile_set.get_source(source) as TileSetScenesCollectionSource
	var pine := -1
	for i in coll.get_scene_tiles_count():
		var id := coll.get_scene_tile_id(i)
		if coll.get_scene_tile_scene(id).resource_path.ends_with("pine.tscn"):
			pine = id
	if pine == -1:
		push_error("WorldBuilder: no pine.tscn in props_tileset.tres")
		return 0

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var noise := FastNoiseLite.new()
	noise.seed = map_seed
	noise.frequency = patch_frequency
	var rect := ground.get_used_rect()
	var size := Vector2(rect.size) * Vector2(ground.tile_set.tile_size)
	var top_left := Vector2(rect.position) * Vector2(ground.tile_set.tile_size)
	var taken := {}
	var y := top_left.y + 40.0
	while y < top_left.y + size.y - 20.0:
		var x := top_left.x + 30.0
		while x < top_left.x + size.x - 30.0:
			var p := Vector2(x + rng.randf_range(-tree_jitter, tree_jitter), y + rng.randf_range(-tree_jitter, tree_jitter))
			var density := clampf(0.6 + noise.get_noise_2dv(p) * 0.9, 0.15, 1.0) \
					* smoothstep(clearing, clearing + clearing_fade, p.length())
			if rng.randf() < density * forest_fill:
				var cell := props.local_to_map(p)
				if not taken.has(cell):
					taken[cell] = true
					props.set_cell(cell, source, Vector2i.ZERO, pine)
			x += tree_spacing
		y += tree_spacing * 0.8      # rows a bit closer: the 3/4 view squashes depth
	return taken.size()


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
