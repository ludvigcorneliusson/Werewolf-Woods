extends CanvasLayer
## Game HUD: health bar with the XP bar under it (bottom left), tools bar (bottom centre, keys 1-4), the
## backpack inventory (Tab / I, opens above the tools bar), the "E" pick-up
## prompt over the nearest item and small "+1 Twig" notes.
## Created by main.gd; drawn above the night darkness.

signal tool_selected(id: String)

const Items := preload("res://scripts/items.gd")
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const ACCENT := Color(0.85, 0.42, 0.2)
const PANEL := Color(0.08, 0.10, 0.09, 0.82)
const BORDER := Color(0.32, 0.36, 0.30)
const SLOT := 52                     # slot size, screen px

var inventory: Node                  # scripts/inventory.gd
var tools: Array[String] = ["axe", "spade", "pickaxe", ""]
var selected_tool := 0

var _health_box: PanelContainer
var _health_fill: ColorRect
var _health_back: ColorRect
var _health_lag: ColorRect
var _health_label: Label
var _health_frac := 1.0
var _tool_slots: Array[Panel] = []
var _tools_box: PanelContainer
var _inv_panel: PanelContainer
var _inv_slots: Array[Panel] = []
var _drag_from := -1                 # backpack slot being dragged, -1 = none
var _drag_icon: TextureRect          # follows the mouse while dragging
var _drag_start := Vector2.ZERO
var _press_slot := -1                # slot under the mouse when the button went down
var _prompt: Label
var _hurt: ColorRect
var _notes: Control
var _xp_fill: ColorRect
var _xp_label: Label
var _level_label: Label
const XP_COLOR := Color(0.42, 0.16, 0.74)     # deep purple
const XP_WIDTH := 150.0
var _xp_frac := 0.0


func _ready() -> void:
	layer = 2
	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.color = Color(0.6, 0.0, 0.0, 0.0)
	add_child(_hurt)
	_notes = Control.new()
	_notes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notes)
	_build_health()
	_health_box.resized.connect(_place)
	_build_tools()
	_build_inventory()
	_prompt = _key_label("E")
	_prompt.visible = false
	add_child(_prompt)
	if inventory:
		inventory.changed.connect(_refresh_inventory)
	_refresh_inventory()
	_refresh_tools()
	get_viewport().size_changed.connect(_place)
	_place.call_deferred()


# --- health ----------------------------------------------------------------------

func _build_health() -> void:
	var box := PanelContainer.new()
	_health_box = box
	box.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 6))
	box.mouse_filter = Control.MOUSE_FILTER_STOP          # clicks here never swing the axe
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	box.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var heart := TextureRect.new()
	heart.texture = preload("res://assets/ui/heart.png")
	heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.custom_minimum_size = Vector2(27, 27)
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(heart)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(180, 27)
	row.add_child(bar)
	_health_back = ColorRect.new()
	_health_back.color = Color(0.05, 0.03, 0.03, 0.9)
	_health_back.position = Vector2(0, 6)
	_health_back.size = Vector2(180, 16)
	bar.add_child(_health_back)
	_health_lag = ColorRect.new()                      # shows the hit you just took, then shrinks
	_health_lag.color = Color(0.95, 0.85, 0.6)
	_health_lag.position = Vector2(2, 8)
	_health_lag.size = Vector2(176, 12)
	bar.add_child(_health_lag)
	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.77, 0.2, 0.18)
	_health_fill.position = Vector2(2, 8)
	_health_fill.size = Vector2(176, 12)
	bar.add_child(_health_fill)
	# Current level, next to the health bar.
	var sep := ColorRect.new()
	sep.color = BORDER
	sep.custom_minimum_size = Vector2(2, 27)
	row.add_child(sep)
	_level_label = Label.new()
	_level_label.custom_minimum_size = Vector2(54, 27)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 18)
	_level_label.add_theme_color_override("font_color", XP_COLOR.lightened(0.45))
	_level_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_level_label.add_theme_constant_override("outline_size", 4)
	_level_label.text = "LV 1"
	row.add_child(_level_label)
	_health_label = Label.new()
	_health_label.position = Vector2(0, 2)
	_health_label.size = Vector2(180, 24)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 14)
	_health_label.add_theme_color_override("font_color", TEXT_COLOR)
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 4)
	bar.add_child(_health_label)
	_build_xp(col)


## Shows health (hurt = flash the screen red: you just took a hit).
func set_health(value: float, max_value: float, hurt := false) -> void:
	var f := clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
	_health_fill.size.x = 176.0 * f
	_health_fill.color = Color(0.77, 0.2, 0.18) if f > 0.3 else Color(0.9, 0.12, 0.1)
	_health_label.text = "%d / %d" % [ceili(value), int(max_value)]
	if f < _health_frac:
		var t := create_tween()
		t.tween_interval(0.35)
		t.tween_property(_health_lag, "size:x", 176.0 * f, 0.4)
	else:
		_health_lag.size.x = 176.0 * f
	_health_frac = f
	if hurt:
		_hurt.color.a = 0.35
		create_tween().tween_property(_hurt, "color:a", 0.0, 0.5)


# --- experience ------------------------------------------------------------------

## Thin purple XP bar right under the health bar, with the XP numbers to its
## right. The current level is shown next to the health bar.
func _build_xp(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var indent := Control.new()                       # line up under the health bar (heart width)
	indent.custom_minimum_size = Vector2(27, 0)
	row.add_child(indent)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(XP_WIDTH, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0.03, 0.02, 0.05, 0.9)
	back.position = Vector2(0, 3)
	back.size = Vector2(XP_WIDTH, 6)
	bar.add_child(back)
	_xp_fill = ColorRect.new()
	_xp_fill.color = XP_COLOR
	_xp_fill.position = Vector2(1, 4)
	_xp_fill.size = Vector2(0, 4)
	bar.add_child(_xp_fill)
	var shine := ColorRect.new()                      # thin highlight on top of the fill
	shine.color = Color(1, 1, 1, 0.14)
	shine.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shine.offset_bottom = 1
	_xp_fill.add_child(shine)
	_xp_label = Label.new()
	_xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 12)
	_xp_label.add_theme_color_override("font_color", XP_COLOR.lightened(0.5))
	_xp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_xp_label.add_theme_constant_override("outline_size", 3)
	row.add_child(_xp_label)
	set_xp(0, 10, 1)


## Shows XP progress towards the next level, and the level.
func set_xp(xp: int, needed: int, level: int) -> void:
	var f := clampf(float(xp) / maxf(float(needed), 1.0), 0.0, 1.0)
	_xp_label.text = "%d / %d XP" % [xp, needed]
	if _level_label:
		if _level_label.text != "LV %d" % level and level > 1:
			_level_label.pivot_offset = _level_label.size / 2.0
			_level_label.scale = Vector2(1.4, 1.4)
			create_tween().tween_property(_level_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
		_level_label.text = "LV %d" % level
	var full := XP_WIDTH - 2.0
	var t := create_tween()
	if f < _xp_frac:
		# Wrapped to a new level: fill up, then start again from empty.
		t.tween_property(_xp_fill, "size:x", full, 0.15)
		t.tween_property(_xp_fill, "size:x", 0.0, 0.0)
	t.tween_property(_xp_fill, "size:x", full * f, 0.25).set_ease(Tween.EASE_OUT)
	_xp_frac = f


# --- tools bar -------------------------------------------------------------------

func _build_tools() -> void:
	var box := PanelContainer.new()
	_tools_box = box
	box.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 6))
	box.mouse_filter = Control.MOUSE_FILTER_STOP          # clicks here never swing the axe
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for i in tools.size():
		var s := _slot(str(i + 1))
		row.add_child(s)
		_tool_slots.append(s)
	# Keep it centred on the bottom edge whatever the window size.
	box.resized.connect(_place)


func select_tool(index: int) -> void:
	if index < 0 or index >= tools.size():
		return
	selected_tool = index
	_refresh_tools()
	tool_selected.emit(tools[index])


func current_tool() -> String:
	return tools[selected_tool]


func _refresh_tools() -> void:
	for i in _tool_slots.size():
		_fill_slot(_tool_slots[i], tools[i], 0, i == selected_tool)


# --- inventory -------------------------------------------------------------------

func _build_inventory() -> void:
	_inv_panel = PanelContainer.new()
	_inv_panel.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 10))
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP     # clicks inside the backpack never swing the axe
	_inv_panel.visible = false
	add_child(_inv_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_inv_panel.add_child(col)
	var title := Label.new()
	title.text = "Backpack"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.93, 0.86, 0.68))
	col.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var n: int = inventory.slots.size() if inventory else 6
	for i in n:
		var s := _slot("")
		grid.add_child(s)
		_inv_slots.append(s)
	_inv_panel.resized.connect(_place)
	_inv_panel.gui_input.connect(_on_inv_input)
	_drag_icon = TextureRect.new()
	_drag_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_icon.visible = false
	_drag_icon.z_index = 10
	add_child(_drag_icon)


# --- dragging items in the backpack ---------------------------------------------
# Hold the left button on an item and drag it onto another slot: it moves there
# (swapping with what was there; the same item tops up that stack). Let go
# outside the backpack and nothing changes.

func _on_inv_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_slot = _slot_at(event.global_position)
			_drag_start = event.global_position
		else:
			if _drag_from >= 0:
				var to := _slot_at(event.global_position)
				if to >= 0 and inventory:
					inventory.move(_drag_from, to)
			_end_drag()
			_press_slot = -1
		_inv_panel.accept_event()
	elif event is InputEventMouseMotion:
		if _drag_from < 0 and _press_slot >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) \
				and event.global_position.distance_to(_drag_start) > 4.0:
			_begin_drag(_press_slot)
		if _drag_from >= 0:
			_drag_icon.global_position = (event.global_position - _drag_icon.size / 2.0).round()
			_highlight_target(_slot_at(event.global_position))


func _begin_drag(i: int) -> void:
	if inventory == null or i >= inventory.slots.size() or inventory.slots[i].is_empty():
		return
	_drag_from = i
	var icon := _inv_slots[i].get_node("Icon") as TextureRect
	_drag_icon.texture = icon.texture
	_drag_icon.size = icon.size
	_drag_icon.visible = true
	icon.modulate.a = 0.3                        # the item "lifts" out of its slot


func _end_drag() -> void:
	_drag_from = -1
	_drag_icon.visible = false
	_refresh_inventory()


func _highlight_target(to: int) -> void:
	for i in _inv_slots.size():
		var s: Dictionary = inventory.slots[i] if inventory and i < inventory.slots.size() else {}
		_fill_slot(_inv_slots[i], s.get("id", ""), int(s.get("count", 0)), i == to and i != _drag_from)
	(_inv_slots[_drag_from].get_node("Icon") as TextureRect).modulate.a = 0.3


## Backpack slot under a screen position, or -1.
func _slot_at(pos: Vector2) -> int:
	for i in _inv_slots.size():
		if _inv_slots[i].get_global_rect().has_point(pos):
			return i
	return -1


## Health box bottom left, tools bar centred on the bottom edge, backpack just
## above it (screen px).
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_health_box.reset_size()
	_health_box.position = Vector2(16, view.y - _health_box.size.y - 16)
	_tools_box.reset_size()
	_tools_box.position = Vector2(roundf((view.x - _tools_box.size.x) / 2.0), view.y - _tools_box.size.y - 16)
	_inv_panel.reset_size()
	_inv_panel.position = Vector2(roundf((view.x - _inv_panel.size.x) / 2.0),
			_tools_box.position.y - _inv_panel.size.y - 10)


func toggle_inventory() -> void:
	_inv_panel.visible = not _inv_panel.visible
	if not _inv_panel.visible and _drag_from >= 0:
		_end_drag()
	_place.call_deferred()


func is_inventory_open() -> bool:
	return _inv_panel.visible


func _refresh_inventory() -> void:
	if inventory == null:
		return
	for i in _inv_slots.size():
		var s: Dictionary = inventory.slots[i] if i < inventory.slots.size() else {}
		_fill_slot(_inv_slots[i], s.get("id", ""), int(s.get("count", 0)), false)
		(_inv_slots[i].get_node("Icon") as TextureRect).modulate.a = 1.0


# --- pick-up prompt and notes ----------------------------------------------------

## Shows the "E" key over a world position (null hides it).
func show_prompt(world_pos: Variant) -> void:
	if world_pos == null:
		_prompt.visible = false
		return
	var screen: Vector2 = get_viewport().get_canvas_transform() * (world_pos as Vector2)
	_prompt.visible = true
	_prompt.position = (screen - _prompt.size / 2.0 + Vector2(0, -6 + sin(Time.get_ticks_msec() * 0.006) * 2.0)).round()


## A short note that rises and fades over a world position ("+1 Twig").
func note(text: String, world_pos: Vector2, color := TEXT_COLOR) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	_notes.add_child(l)
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	l.position = screen + Vector2(-40, -40)
	l.size = Vector2(80, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y - 28, 0.9).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	t.chain().tween_callback(l.queue_free)


# --- building blocks -------------------------------------------------------------

func _slot(key_hint: String) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(8, 8)
	icon.size = Vector2(SLOT - 16, SLOT - 16)
	p.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.position = Vector2(0, SLOT - 22)
	count.size = Vector2(SLOT - 4, 20)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Color.WHITE)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	p.add_child(count)
	if key_hint != "":
		var k := Label.new()
		k.text = key_hint
		k.position = Vector2(4, 0)
		k.add_theme_font_size_override("font_size", 12)
		k.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.25))
		k.add_theme_color_override("font_outline_color", Color.BLACK)
		k.add_theme_constant_override("outline_size", 3)
		p.add_child(k)
	return p


func _fill_slot(p: Panel, id: String, count: int, selected: bool) -> void:
	var icon := p.get_node("Icon") as TextureRect
	var item := Items.get_item(id)
	icon.texture = item.get("icon") if not item.is_empty() else null
	# Pixel icons: the largest whole-number scale that fits the slot.
	if icon.texture:
		var ts := icon.texture.get_size()
		var k := maxf(floorf(minf((SLOT - 12) / ts.x, (SLOT - 12) / ts.y)), 1.0)
		if ts.x * k > SLOT - 8:
			k = (SLOT - 8) / ts.x                      # wide icons (a log) just fit
		icon.size = ts * k
		icon.position = ((Vector2(SLOT, SLOT) - icon.size) / 2.0).round()
	(p.get_node("Count") as Label).text = str(count) if count > 1 else ""
	p.add_theme_stylebox_override("panel", _box(Color(0.14, 0.17, 0.14, 0.9) if selected else Color(0.04, 0.05, 0.05, 0.7),
			ACCENT if selected else BORDER, 0, 2 if selected else 1))


func _key_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(22, 22)
	l.size = Vector2(22, 22)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_stylebox_override("normal", _box(Color(0.08, 0.10, 0.09, 0.9), Color(0.93, 0.86, 0.68), 0, 2))
	return l


static func _box(bg: Color, border: Color, pad: int, width := 2) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(4)
	b.set_content_margin_all(pad)
	return b
