extends CanvasLayer
## Game HUD: health bar (bottom left), tools bar (bottom centre, keys 1-4), the
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
var tools: Array[String] = ["axe", "", "", ""]
var selected_tool := 0

var _health_fill: ColorRect
var _health_back: ColorRect
var _health_lag: ColorRect
var _health_label: Label
var _health_frac := 1.0
var _tool_slots: Array[Panel] = []
var _tools_box: PanelContainer
var _inv_panel: PanelContainer
var _inv_slots: Array[Panel] = []
var _prompt: Label
var _hurt: ColorRect
var _notes: Control


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
	box.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 6))
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(16, -16 - 40)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
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
	_health_label = Label.new()
	_health_label.position = Vector2(0, 2)
	_health_label.size = Vector2(180, 24)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 14)
	_health_label.add_theme_color_override("font_color", TEXT_COLOR)
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 4)
	bar.add_child(_health_label)


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


# --- tools bar -------------------------------------------------------------------

func _build_tools() -> void:
	var box := PanelContainer.new()
	_tools_box = box
	box.add_theme_stylebox_override("panel", _box(PANEL, BORDER, 6))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Tools bar centred on the bottom edge, backpack just above it (screen px).
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_tools_box.reset_size()
	_tools_box.position = Vector2(roundf((view.x - _tools_box.size.x) / 2.0), view.y - _tools_box.size.y - 16)
	_inv_panel.reset_size()
	_inv_panel.position = Vector2(roundf((view.x - _inv_panel.size.x) / 2.0),
			_tools_box.position.y - _inv_panel.size.y - 10)


func toggle_inventory() -> void:
	_inv_panel.visible = not _inv_panel.visible
	_place.call_deferred()


func is_inventory_open() -> bool:
	return _inv_panel.visible


func _refresh_inventory() -> void:
	if inventory == null:
		return
	for i in _inv_slots.size():
		var s: Dictionary = inventory.slots[i] if i < inventory.slots.size() else {}
		_fill_slot(_inv_slots[i], s.get("id", ""), int(s.get("count", 0)), false)


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
