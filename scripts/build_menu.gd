extends CanvasLayer
## Build menu (B): a list of the things you can build (scripts/buildables.gd)
## with what each costs. Costs you can't cover show in red. Click a row (or
## press its number) to start placing it. The game keeps running behind it.

signal picked(id: String)

const Buildables := preload("res://scripts/buildables.gd")
const Items := preload("res://scripts/items.gd")
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const ACCENT := Color(0.85, 0.42, 0.2)
const BORDER := Color(0.32, 0.36, 0.30)
const MISSING := Color(1.0, 0.45, 0.4)

var inventory: Node
var player: Node2D                 # recipes that need a workbench show only near one

var _panel: PanelContainer
var _list: VBoxContainer
var _ids: Array[String] = []
var _check := 0.0


func _ready() -> void:
	layer = 3
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.10, 0.09, 0.92), BORDER, 12))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP     # clicks inside the menu never swing the axe
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var title := _label("Build", 20, TITLE_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	col.add_child(_list)
	var hint := _label("Click or press 1-9 to place  -  B / Esc to close", 13, TEXT_COLOR.darkened(0.3))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	_panel.visible = false
	if inventory:
		inventory.changed.connect(func(): if is_open(): _refresh())
	get_viewport().size_changed.connect(_place)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		open()


func open() -> void:
	_refresh()
	_panel.visible = true
	_place.call_deferred()


func close() -> void:
	_panel.visible = false


## While open, walking up to (or away from) a workbench adds (or removes) its recipes.
func _process(delta: float) -> void:
	if not is_open():
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.25
		if _available() != _ids:
			_refresh()
			_place.call_deferred()


func _available() -> Array[String]:
	var pos: Vector2 = player.global_position if is_instance_valid(player) else Vector2.INF
	return Buildables.available(get_tree(), pos)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < _ids.size():
			get_viewport().set_input_as_handled()
			_choose(_ids[n])


func _choose(id: String) -> void:
	if not Buildables.can_afford(id, inventory):
		return
	close()
	picked.emit(id)


## Centred, above the tools bar.
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_panel.reset_size()
	_panel.position = Vector2(roundf((view.x - _panel.size.x) / 2.0), view.y - _panel.size.y - 100)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_ids.clear()
	var i := 0
	for id: String in _available():
		var b: Dictionary = Buildables.ALL[id]
		var ok := Buildables.can_afford(id, inventory)
		var row := Button.new()
		row.custom_minimum_size = Vector2(320, 56)
		row.focus_mode = Control.FOCUS_NONE
		row.add_theme_stylebox_override("normal", _box(Color(0.12, 0.14, 0.12, 0.95), BORDER if ok else BORDER.darkened(0.3), 0))
		row.add_theme_stylebox_override("hover", _box(Color(0.16, 0.19, 0.15, 0.98), ACCENT if ok else BORDER, 0))
		row.add_theme_stylebox_override("pressed", _box(Color(0.22, 0.15, 0.09, 0.98), ACCENT, 0))
		row.pressed.connect(_choose.bind(id))
		var h := HBoxContainer.new()
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 10
		h.offset_right = -10
		h.add_theme_constant_override("separation", 10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var key := _label(str(i + 1), 13, TEXT_COLOR.darkened(0.3))
		key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key.size_flags_vertical = Control.SIZE_FILL
		h.add_child(key)
		h.add_child(_icon(b.icon, 40))
		var name_l := _label(b.name, 18, TITLE_COLOR if ok else TEXT_COLOR.darkened(0.35))
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_vertical = Control.SIZE_FILL
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_l)
		# Cost: icon + have/need per item, red when short ("Free" in god mode).
		if Buildables.free_build:
			var free := _label("Free", 15, Color(1.0, 0.85, 0.4))
			free.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			free.size_flags_vertical = Control.SIZE_FILL
			h.add_child(free)
		for item: String in (b.cost if not Buildables.free_build else {}):
			var need := int(b.cost[item])
			var have: int = inventory.count(item) if inventory else 0
			h.add_child(_icon(Items.get_item(item).get("icon"), 24))
			var c := _label("%d/%d" % [mini(have, need), need], 15, TEXT_COLOR if have >= need else MISSING)
			c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			c.size_flags_vertical = Control.SIZE_FILL
			h.add_child(c)
		for n in h.get_children():
			if n is Control:
				n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(row)
		_ids.append(id)
		i += 1


func _icon(tex: Texture2D, size: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	return l


static func _box(bg: Color, border: Color, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(pad)
	return s
