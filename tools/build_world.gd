extends SceneTree
## Builds the art-based world. Run headless from the project folder:
##   godot --headless --path . -s res://tools/build_world.gd
## It (re)creates:
##   - assets/props/*.tscn      one scene per prop (sprite, collision, vision blocker, fade)
##   - assets/props/props_tileset.tres   scene tiles, so props can be painted with the TileMap brush
##   - assets/tiles/ground_tileset.tres  the grass tile
##   - the World node in main.tscn with ground filled, a pine forest and the campfire
## (campfire.tscn itself is made once by tools/build_campfire.gd.)
## Re-running it OVERWRITES the World in main.tscn (and anything you painted there).

const PROPS := [
	# name,        foot_from_bottom, collision radius, vision blocker (rx, ry) or zero
	["tree_light", 3, 6.0, Vector2(9, 5)],
	["tree_dark",  3, 6.0, Vector2(9, 5)],
	["pine",       3, 5.0, Vector2(8, 5)],
	["bush",       6, 14.0, Vector2(18, 9)],
	["stump",      4, 9.0, Vector2.ZERO],
	["rock",       4, 9.0, Vector2.ZERO],
]
const GROUND_TILES := 30      # tiles per side
const PROP_CELL := 16         # grid used when painting props
const CLEARING := 380.0       # px radius of the open area around the campfire
# Pine forest. Pines are ~300-430 px tall (see scripts/pine.gd), settler 43 px.
const TREE_SPACING := 92.0    # px between candidate tree spots (lower = denser)
const TREE_JITTER := 34.0     # px random offset per spot (breaks up the grid)
const FOREST_FILL := 0.72     # 0..1 chance a spot gets a tree where the forest is thickest
const SPAWN_OFFSET := Vector2(0, 70)   # settler starts just south of the fire


func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/props/prop_fade.gdshader")
	ResourceSaver.save(material, "res://assets/props/prop_material.tres")
	material = load("res://assets/props/prop_material.tres")
	# Pines: same fade plus per-tree colour variation (scripts/pine.gd), and a
	# slightly bigger fade circle because the trees are huge.
	var pine_material := ShaderMaterial.new()
	pine_material.shader = material.shader
	pine_material.set_shader_parameter("color_variance", true)
	pine_material.set_shader_parameter("fade_radius", 38.0)
	ResourceSaver.save(pine_material, "res://assets/props/pine_material.tres")
	pine_material = load("res://assets/props/pine_material.tres")

	# --- prop scenes -------------------------------------------------------
	var scene_paths := []
	for p in PROPS:
		var path := "res://assets/props/%s.tscn" % p[0]
		ResourceSaver.save(_make_prop(p, pine_material if p[0] == "pine" else material), path)
		scene_paths.append(path)

	# --- props tileset (scene collection) ---------------------------------
	var pts := TileSet.new()
	pts.tile_size = Vector2i(PROP_CELL, PROP_CELL)
	var coll := TileSetScenesCollectionSource.new()
	var props_source := pts.add_source(coll)
	var scene_ids := []
	for path in scene_paths:
		scene_ids.append(coll.create_scene_tile(load(path)))
	ResourceSaver.save(pts, "res://assets/props/props_tileset.tres")
	pts = load("res://assets/props/props_tileset.tres")

	# --- ground tileset ----------------------------------------------------
	var tex := load("res://assets/tiles/grass.png") as Texture2D
	var gts := TileSet.new()
	gts.tile_size = Vector2i(tex.get_width(), tex.get_height())
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = gts.tile_size
	atlas.create_tile(Vector2i.ZERO)
	var ground_source := gts.add_source(atlas)
	ResourceSaver.save(gts, "res://assets/tiles/ground_tileset.tres")
	gts = load("res://assets/tiles/ground_tileset.tres")

	# --- world in main.tscn -----------------------------------------------
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var old := main.get_node_or_null("World")
	if old:
		main.remove_child(old)
		old.free()

	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	_add(main, main, world)

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = gts
	ground.z_index = -10
	_add(main, world, ground)
	var half := GROUND_TILES / 2
	for y in range(-half, half):
		for x in range(-half, half):
			ground.set_cell(Vector2i(x, y), ground_source, Vector2i.ZERO)

	var props := TileMapLayer.new()
	props.name = "Props"
	props.tile_set = pts
	props.y_sort_enabled = true
	_add(main, world, props)
	_place_starter_forest(props, props_source, scene_ids, ground)

	# Campfire in the middle of the clearing (instanced, so tweaks in campfire.tscn stay).
	var campfire: Node2D = (load("res://assets/props/campfire.tscn") as PackedScene).instantiate()
	campfire.name = "Campfire"
	_add(main, world, campfire)

	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	spawn.position = SPAWN_OFFSET
	_add(main, world, spawn)

	var packed := PackedScene.new()
	packed.pack(main)
	print("saved main.tscn: ", ResourceSaver.save(packed, "res://main.tscn"))
	quit()


func _make_prop(p: Array, material: Material) -> PackedScene:
	var root := Node2D.new()
	root.name = String(p[0]).to_pascal_case()
	if p[0] == "pine":
		root.set_script(load("res://scripts/pine.gd"))   # per-tree size/colour variance

	var tex := load("res://assets/props/%s.png" % p[0]) as Texture2D
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.centered = false
	# Origin = where the object touches the ground.
	sprite.offset = Vector2(-tex.get_width() / 2, -tex.get_height() + p[1])
	sprite.material = material
	sprite.light_mask = 2          # lit by vision light, never hidden by its shadows
	_add(root, root, sprite)

	var body := StaticBody2D.new()
	body.name = "Body"
	_add(root, root, body)
	var shape := CircleShape2D.new()
	shape.radius = p[2]
	var cs := CollisionShape2D.new()
	cs.shape = shape
	_add(root, body, cs)

	var occ_size: Vector2 = p[3]
	if occ_size != Vector2.ZERO:
		var poly := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			poly.append(Vector2(cos(a) * occ_size.x, sin(a) * occ_size.y))
		var op := OccluderPolygon2D.new()
		op.polygon = poly
		var occ := LightOccluder2D.new()
		occ.name = "VisionBlocker"
		occ.occluder = op
		_add(root, root, occ)

	var packed := PackedScene.new()
	packed.pack(root)
	return packed


func _place_starter_forest(props: TileMapLayer, source: int, ids: Array, ground: TileMapLayer) -> void:
	# Pines only. Density follows noise so there are thick stands and thinner
	# patches, and ramps up from the clearing edge.
	var pine: int = ids[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var noise := FastNoiseLite.new()
	noise.seed = 777
	noise.frequency = 0.0025
	var rect := ground.get_used_rect()
	var size := Vector2(rect.size) * Vector2(ground.tile_set.tile_size)
	var top_left := Vector2(rect.position) * Vector2(ground.tile_set.tile_size)
	var taken := {}
	var y := top_left.y + 40.0
	while y < top_left.y + size.y - 20.0:
		var x := top_left.x + 30.0
		while x < top_left.x + size.x - 30.0:
			var p := Vector2(x + rng.randf_range(-TREE_JITTER, TREE_JITTER), y + rng.randf_range(-TREE_JITTER, TREE_JITTER))
			var d := p.length()
			var density := clampf(0.6 + noise.get_noise_2dv(p) * 0.9, 0.15, 1.0) * smoothstep(CLEARING, CLEARING + 220.0, d)
			if rng.randf() < density * FOREST_FILL:
				var cell := props.local_to_map(p)
				if not taken.has(cell):
					taken[cell] = true
					props.set_cell(cell, source, Vector2i.ZERO, pine)
			x += TREE_SPACING
		y += TREE_SPACING * 0.8      # rows a bit closer: the 3/4 view squashes depth


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
