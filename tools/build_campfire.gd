extends SceneTree
## Builds assets/props/campfire.tscn. Run headless from the project folder:
##   godot --headless --path . -s res://tools/build_campfire.gd
## Only needed once: after that, tweak the particles in the editor.
## Re-running OVERWRITES campfire.tscn (and any tweaks you made in it).

const FOOT := 3            # campfire.png pixels below the ground point


func _initialize() -> void:
	var root := Node2D.new()
	root.name = "Campfire"
	root.set_script(load("res://scripts/campfire.gd"))

	var tex := load("res://assets/props/campfire.png") as Texture2D
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.offset = Vector2(-tex.get_width() / 2, -tex.get_height() + FOOT)
	sprite.light_mask = 2          # lit by lights, never hidden by shadows (like props)
	_add(root, root, sprite)

	# Solid stone ring: you can't walk into the fire.
	var body := StaticBody2D.new()
	body.name = "Body"
	_add(root, root, body)
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	var cs := CollisionShape2D.new()
	cs.name = "Collision"
	cs.shape = shape
	cs.position = Vector2(0, -6)
	_add(root, body, cs)

	# Glowing particles ignore the night darkness and add up like real flames.
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED

	# No texture = each particle is a crisp square pixel, scaled by scale_amount.
	var fire := _particles("Fire", 46, 0.8, Vector2(0, -8), Vector2(6, 1.5))
	fire.material = glow
	fire.spread = 10.0
	fire.gravity = Vector2(0, -55)
	fire.initial_velocity_min = 12.0
	fire.initial_velocity_max = 28.0
	fire.damping_min = 2.0
	fire.damping_max = 6.0
	fire.tangential_accel_min = -14.0
	fire.tangential_accel_max = 14.0
	fire.scale_amount_min = 2.0
	fire.scale_amount_max = 4.0
	fire.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.25)])
	fire.color_ramp = _gradient([
		[0.0, Color(1.0, 0.8, 0.4, 0.75)],
		[0.25, Color(1.0, 0.55, 0.15, 0.7)],
		[0.6, Color(0.85, 0.25, 0.05, 0.55)],
		[1.0, Color(0.4, 0.06, 0.03, 0.0)],
	])
	fire.hue_variation_min = -0.02
	fire.hue_variation_max = 0.02
	_add(root, root, fire)

	var core := _particles("Core", 12, 0.35, Vector2(0, -7), Vector2(3, 1))
	core.material = glow
	core.spread = 8.0
	core.gravity = Vector2(0, -30)
	core.initial_velocity_min = 8.0
	core.initial_velocity_max = 16.0
	core.scale_amount_min = 2.0
	core.scale_amount_max = 3.0
	core.scale_amount_curve = _curve([Vector2(0, 1), Vector2(1, 0.4)])
	core.color_ramp = _gradient([
		[0.0, Color(1.0, 0.9, 0.6, 0.5)],
		[0.5, Color(1.0, 0.75, 0.3, 0.4)],
		[1.0, Color(1.0, 0.5, 0.15, 0.0)],
	])
	_add(root, root, core)

	var embers := _particles("Embers", 10, 1.8, Vector2(0, -10), Vector2(5, 1))
	embers.material = glow
	embers.spread = 28.0
	embers.gravity = Vector2(0, -12)
	embers.initial_velocity_min = 22.0
	embers.initial_velocity_max = 42.0
	embers.damping_min = 8.0
	embers.damping_max = 14.0
	embers.tangential_accel_min = -20.0
	embers.tangential_accel_max = 20.0
	embers.scale_amount_min = 1.0
	embers.scale_amount_max = 1.0
	embers.color_ramp = _gradient([
		[0.0, Color(1.0, 0.85, 0.45, 1.0)],
		[0.6, Color(1.0, 0.45, 0.12, 0.9)],
		[1.0, Color(0.6, 0.15, 0.05, 0.0)],
	])
	_add(root, root, embers)

	# Smoke is lit normally, so it only shows where light (the fire) reaches.
	var smoke := _particles("Smoke", 16, 2.6, Vector2(0, -20), Vector2(3, 1))
	smoke.light_mask = 2
	smoke.spread = 14.0
	smoke.gravity = Vector2(0, -6)
	smoke.initial_velocity_min = 8.0
	smoke.initial_velocity_max = 14.0
	smoke.tangential_accel_min = -6.0
	smoke.tangential_accel_max = 6.0
	smoke.scale_amount_min = 3.0
	smoke.scale_amount_max = 5.0
	smoke.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 1.6)])
	smoke.color_ramp = _gradient([
		[0.0, Color(0.35, 0.3, 0.28, 0.0)],
		[0.15, Color(0.35, 0.3, 0.28, 0.35)],
		[1.0, Color(0.2, 0.2, 0.2, 0.0)],
	])
	smoke.show_behind_parent = false
	_add(root, root, smoke)

	# Warm light; trunks cast shadows from it just like from your vision.
	var light := PointLight2D.new()
	light.name = "Light"
	light.position = Vector2(0, -8)
	light.color = Color(1.0, 0.62, 0.3)
	light.energy = 1.35
	light.texture = _light_texture()
	light.texture_scale = 190.0 * 2.0 / 512.0
	light.range_item_cull_mask = 1 | 2 | 4     # 4 = characters
	light.shadow_enabled = false             # no shadows behind trees
	light.shadow_item_cull_mask = 1 | 4
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	_add(root, root, light)

	var packed := PackedScene.new()
	packed.pack(root)
	print("saved campfire.tscn: ", ResourceSaver.save(packed, "res://assets/props/campfire.tscn"))
	quit()


func _particles(node_name: String, amount: int, lifetime: float, pos: Vector2, extents: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.randomness = 0.5
	p.lifetime_randomness = 0.35
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.direction = Vector2(0, -1)
	return p


func _gradient(stops: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	g.offsets = offsets
	g.colors = colors
	return g


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	return c


func _light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in 17:
		var t := i / 16.0
		offsets.append(t)
		colors.append(Color(1, 1, 1, pow(1.0 - smoothstep(0.0, 1.0, t), 1.6)))
	g.offsets = offsets
	g.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 512
	tex.height = 400        # squashed: looks round on the 3/4 ground
	return tex


func _add(owner_node: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = owner_node
