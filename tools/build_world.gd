extends SceneTree
## Builds the art-based world. Run headless from the project folder:
##   godot --headless --path . -s res://tools/build_world.gd
## It (re)creates:
##   - assets/props/*.tscn      one scene per prop (sprite, collision, vision blocker, fade)
##   - assets/props/props_tileset.tres   scene tiles, so props can be painted with the TileMap brush
##   - assets/tiles/ground_tileset.tres  the grass tile
##   - the World node in main.tscn with ground filled and a starter forest
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
const CLEARING := 420.0       # px radius of the open area around spawn


func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/props/prop_fade.gdshader")
	ResourceSaver.save(material, "res://assets/props/prop_material.tres")
	material = load("res://assets/props/prop_material.tres")

	# --- prop scenes -------------------------------------------------------
	var scene_paths := []
	for p in PROPS:
		var path := "res://assets/props/%s.tscn" % p[0]
		ResourceSaver.save(_make_prop(p, material), path)
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

	var spawn := Marker2D.new()
	spawn.name = "Spawn"
	_add(main, world, spawn)

	var packed := PackedScene.new()
	packed.pack(main)
	print("saved main.tscn: ", ResourceSaver.save(packed, "res://main.tscn"))
	quit()


func _make_prop(p: Array, material: Material) -> PackedScene:
	var root := Node2D.new()
	root.name = String(p[0]).to_pascal_case()

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
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var noise := FastNoiseLite.new()
	noise.seed = 777
	noise.frequency = 0.004
	var rect := ground.get_used_rect()
	var size := Vector2(rect.size) * Vector2(ground.tile_set.tile_size)
	var top_left := Vector2(rect.position) * Vector2(ground.tile_set.tile_size)
	var taken := {}
	var step := 40.0
	var y := top_left.y + 60.0
	while y < top_left.y + size.y - 40.0:
		var x := top_left.x + 40.0
		while x < top_left.x + size.x - 40.0:
			var p := Vector2(x + rng.randf_range(-14, 14), y + rng.randf_range(-14, 14))
			var d := p.length()
			var density := clampf(0.45 + noise.get_noise_2dv(p) * 0.9, 0.0, 1.0) * smoothstep(CLEARING, CLEARING + 250.0, d)
			if rng.randf() < density * 0.75:
				var roll := rng.randf()
				var idx := 0
				if roll < 0.33: idx = 0          # tree_light
				elif roll < 0.62: idx = 1        # tree_dark
				elif roll < 0.80: idx = 2        # pine
				elif roll < 0.90: idx = 3        # bush
				elif roll < 0.95: idx = 4        # stump
				else: idx = 5                    # rock
				var cell := props.local_to_map(p)
				if not taken.has(cell):
					taken[cell] = true
					props.set_cell(cell, source, Vector2i.ZERO, ids[idx])
			elif d < CLEARING and rng.randf() < 0.012:
				var cell := props.local_to_map(p)
				props.set_cell(cell, source, Vector2i.ZERO, ids[[3, 4, 5][rng.randi() % 3]])
			x += step
		y += step


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
