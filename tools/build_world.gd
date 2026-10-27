extends SceneTree
## Builds the art-based world. Run headless from the project folder:
##   godot --headless --path . -s res://tools/build_world.gd
## It (re)creates:
##   - assets/props/*.tscn      one scene per prop (sprite, collision, vision blocker, fade)
##   - assets/props/props_tileset.tres   scene tiles, so props can be painted with the TileMap brush
##   - assets/tiles/ground_tileset.tres  the grass tile
##   - the World node in main.tscn, using the settings on the WorldBuilder node
## (campfire.tscn itself is made once by tools/build_campfire.gd.)
## Re-running it OVERWRITES the World in main.tscn (and anything you painted there).
##
## To only change the map size / forest: no need for this - select WorldBuilder
## in main.tscn and click "Rebuild World" in the Inspector.

const PROPS := [
	# name,        foot_from_bottom, collision radius, vision blocker (rx, ry) or zero
	["tree_light", 3, 6.0, Vector2(9, 5)],
	["tree_dark",  3, 6.0, Vector2(9, 5)],
	["pine",       3, 5.0, Vector2(8, 5)],
	["bush",       6, 14.0, Vector2(18, 9)],
	["stump",      4, 9.0, Vector2.ZERO],
	["rock",       4, 9.0, Vector2.ZERO],
]
const PROP_CELL := 16         # grid used when painting props

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
	pts.add_source(coll)
	for path in scene_paths:
		coll.create_scene_tile(load(path))
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
	gts.add_source(atlas)
	ResourceSaver.save(gts, "res://assets/tiles/ground_tileset.tres")
	gts = load("res://assets/tiles/ground_tileset.tres")

	# --- world in main.tscn -----------------------------------------------
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	# World (ground, forest, campfire, spawn) comes from the WorldBuilder node so
	# the command line and the editor button give the same result.
	var builder := main.get_node_or_null("WorldBuilder")
	if builder == null:
		builder = Node.new()
		builder.name = "WorldBuilder"
		builder.set_script(load("res://tools/world_builder.gd"))
		_add(main, main, builder)
	print("pines placed: ", builder.rebuild(main))

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


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
