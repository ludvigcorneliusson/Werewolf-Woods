extends SceneTree
## Builds the art-based world. Run headless from the project folder:
##   godot --headless --path . -s res://tools/build_world.gd
## It (re)creates:
##   - assets/props/*.tscn      one scene per prop in PROPS (sprite, collision, vision blocker, fade)
##     To add a prop: drop <name>.png in assets/props/, add a line to PROPS, run this,
##     then give it a density in world_builder.gd if it should be placed automatically.
##   - assets/props/props_tileset.tres   scene tiles, so props can be painted with the TileMap brush
##   - assets/tiles/ground_tileset.tres  the grass tile
##   - the World node in main.tscn, using the settings on the WorldBuilder node
## (campfire.tscn itself is made once by tools/build_campfire.gd.)
## Re-running it OVERWRITES the World in main.tscn (and anything you painted there).
##
## To only change the map size / forest: no need for this - select WorldBuilder
## in main.tscn and click "Rebuild World" in the Inspector.

# One scene per prop. All share scripts/varied_prop.gd (size/colour/flip per
# instance) and the fade + colour-variation material.
#   foot:   px above the image bottom where the prop touches the ground (= origin, y-sort line)
#   solid:  collision footprint - {"circle": r}, {"ellipse": Vector2(rx, ry)},
#           {"capsule": Vector2(radius, length)} (lying along x), or {} = walk through
#   vision: blocks line of sight with an ellipse (rx, ry), or Vector2.ZERO
#   big:    true = always visible as a silhouette (like trees); false = small ground
#           cover that hides in line-of-sight shadow like the ground does
#   vary:   per-prop overrides for varied_prop.gd (saved on the scene root)
# All trees share one scale range so their pixels are the same size on screen.
# sway = how much wind bends it (0-1); bend = how much walking through pushes it.
const TREE_VARY := {"min_scale": 2.0, "max_scale": 2.6, "hue_variance": 0.03, "saturation_variance": 0.2, "brightness_variance": 0.15, "sway": 1.0}
const DEAD_VARY := {"min_scale": 2.0, "max_scale": 2.6, "hue_variance": 0.015, "saturation_variance": 0.15, "brightness_variance": 0.12, "sway": 0.35}
const PROPS := [
	{"name": "pine_tall", "foot": 4, "solid": {"circle": 8.0}, "vision": Vector2(11, 6), "big": true, "vary": TREE_VARY},
	{"name": "pine_dark", "foot": 3, "solid": {"circle": 4.5}, "vision": Vector2(7, 4), "big": true, "vary": TREE_VARY},
	{"name": "dead_pine", "foot": 4, "solid": {"circle": 7.0}, "vision": Vector2(10, 6), "big": true, "vary": DEAD_VARY},
	{"name": "dead_tree", "foot": 4, "solid": {"circle": 7.0}, "vision": Vector2(10, 6), "big": true, "vary": DEAD_VARY},
	{"name": "stump", "foot": 3, "solid": {"ellipse": Vector2(12, 5)}, "vision": Vector2.ZERO, "big": true},
	{"name": "log", "foot": 4, "solid": {"capsule": Vector2(6, 52)}, "vision": Vector2.ZERO, "big": true},
	{"name": "boulder", "foot": 3, "solid": {"ellipse": Vector2(17, 7)}, "vision": Vector2(15, 6), "big": true},
	{"name": "mossy_rock", "foot": 2, "solid": {"ellipse": Vector2(10, 4)}, "vision": Vector2.ZERO, "big": true},
	{"name": "fern_a", "foot": 2, "solid": {}, "vision": Vector2.ZERO, "big": false, "vary": {"sway": 0.6, "bend": 1.0}},
	{"name": "fern_b", "foot": 2, "solid": {}, "vision": Vector2.ZERO, "big": false, "vary": {"sway": 0.6, "bend": 1.0}},
	{"name": "grass_tuft", "foot": 1, "solid": {}, "vision": Vector2.ZERO, "big": false, "vary": {"sway": 0.8, "bend": 1.3}},
	{"name": "mushroom", "foot": 1, "solid": {}, "vision": Vector2.ZERO, "big": false, "vary": {"bend": 0.3}},
	{"name": "mushroom_brown", "foot": 1, "solid": {}, "vision": Vector2.ZERO, "big": false, "vary": {"bend": 0.3}},
	{"name": "pebble", "foot": 1, "solid": {}, "vision": Vector2.ZERO, "big": false},
	{"name": "stick", "foot": 2, "solid": {}, "vision": Vector2.ZERO, "big": false},
]
const PROP_CELL := 8          # grid used when painting props (fine, so small props don't look gridded)


func _initialize() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/props/prop_fade.gdshader")
	ResourceSaver.save(material, "res://assets/props/prop_material.tres")
	material = load("res://assets/props/prop_material.tres")
	# All props: same fade plus per-instance colour variation (scripts/varied_prop.gd),
	# and a slightly bigger fade circle because the pines are huge.
	var varied := ShaderMaterial.new()
	varied.shader = material.shader
	varied.set_shader_parameter("color_variance", true)
	varied.set_shader_parameter("fade_radius", 38.0)
	ResourceSaver.save(varied, "res://assets/props/varied_material.tres")
	varied = load("res://assets/props/varied_material.tres")

	# --- prop scenes -------------------------------------------------------
	var scene_paths := []
	for p in PROPS:
		var path := "res://assets/props/%s.tscn" % p.name
		ResourceSaver.save(_make_prop(p, varied), path)
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
	print("props placed: ", builder.rebuild(main))

	var packed := PackedScene.new()
	packed.pack(main)
	print("saved main.tscn: ", ResourceSaver.save(packed, "res://main.tscn"))
	quit()


func _make_prop(p: Dictionary, material: Material) -> PackedScene:
	var root := Node2D.new()
	root.name = String(p.name).to_pascal_case()
	root.set_script(load("res://scripts/varied_prop.gd"))
	for key in p.get("vary", {}):
		root.set(key, p.vary[key])

	var tex := load("res://assets/props/%s.png" % p.name) as Texture2D
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.centered = false
	# Origin = where the object touches the ground.
	sprite.offset = Vector2(-tex.get_width() / 2, -tex.get_height() + p.foot)
	sprite.material = material
	# 2 = lit by vision but never hidden by its shadows; 1 = hides in shadow like the ground
	sprite.light_mask = 2 if p.big else 1
	_add(root, root, sprite)

	var solid: Dictionary = p.solid
	if not solid.is_empty():
		var body := StaticBody2D.new()
		body.name = "Body"
		_add(root, root, body)
		if solid.has("circle"):
			var shape := CircleShape2D.new()
			shape.radius = solid.circle
			var cs := CollisionShape2D.new()
			cs.shape = shape
			_add(root, body, cs)
		elif solid.has("capsule"):
			var shape := CapsuleShape2D.new()
			shape.radius = solid.capsule.x
			shape.height = solid.capsule.y
			var cs := CollisionShape2D.new()
			cs.shape = shape
			cs.rotation = PI / 2.0          # lying along x
			_add(root, body, cs)
		elif solid.has("ellipse"):
			var cp := CollisionPolygon2D.new()
			cp.polygon = _ellipse(solid.ellipse)
			_add(root, body, cp)

	var occ_size: Vector2 = p.vision
	if occ_size != Vector2.ZERO:
		var op := OccluderPolygon2D.new()
		op.polygon = _ellipse(occ_size)
		var occ := LightOccluder2D.new()
		occ.name = "VisionBlocker"
		occ.occluder = op
		_add(root, root, occ)

	var packed := PackedScene.new()
	packed.pack(root)
	return packed


func _ellipse(r: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		poly.append(Vector2(cos(a) * r.x, sin(a) * r.y))
	return poly


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
