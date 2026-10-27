extends CanvasLayer
## The furnace's panel (E at a furnace, scripts/furnace.gd). Shows beside the
## backpack (which it opens): an Ore slot, a Fuel slot (logs or twigs), the
## Ingots slot, a smelting bar, a fuel bar and an On/Off button.
## Drag ore or fuel from the backpack onto its slot to put it in (hud.gd asks
## this panel through hud.drop_target); click a slot to take everything in it
## back into the backpack. Closes with E, Esc, or when you walk away.
## Created by main.gd (group "furnace_ui").

const Hud := preload("res://scripts/hud.gd")
const Items := preload("res://scripts/items.gd")
const Furnace := preload("res://scripts/furnace.gd")
const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const FIRE_COLOR := Color(1.0, 0.6, 0.25)
const CLOSE_DISTANCE := 110.0
const SLOT := 52

var hud: CanvasLayer                 # scripts/hud.gd
var inventory: Node
var player: Node2D

var furnace: Node2D
var _panel: PanelContainer
var _state: Label
var _slots := {}                     # "ore" / "fuel" / "output" -> Button
var _smelt_bar: ProgressBar
var _fuel_bar: ProgressBar
var _switch: Button
var _opened_backpack := false


func _ready() -> void:
	layer = 3
	add_to_group("furnace_ui")
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Hud._box(Color(0.08, 0.10, 0.09, 0.92), Hud.BORDER, 10))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP      # clicks here never swing a tool
	_panel.visible = false
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("Furnace", 16, TITLE_COLOR))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_state = _label("", 13, TEXT_COLOR.darkened(0.2))
	head.add_child(_state)

	# Ore -> [smelting] -> Ingots
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_slot_box("ore", "Ore"))
	var mid := VBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_label("Smelting", 12, TEXT_COLOR.darkened(0.3)))
	_smelt_bar = _bar(Color(0.85, 0.5, 0.25))
	mid.add_child(_smelt_bar)
	row.add_child(mid)
	row.add_child(_slot_box("output", "Ingots"))

	# Fuel [burn left] On/Off
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	col.add_child(row2)
	row2.add_child(_slot_box("fuel", "Fuel"))
	var mid2 := VBoxContainer.new()
	mid2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid2.add_child(_label("Fire", 12, TEXT_COLOR.darkened(0.3)))
	_fuel_bar = _bar(FIRE_COLOR)
	mid2.add_child(_fuel_bar)
	row2.add_child(mid2)
	_switch = Button.new()
	_switch.custom_minimum_size = Vector2(SLOT, 30)
	_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_switch.focus_mode = Control.FOCUS_NONE
	_switch.add_theme_font_size_override("font_size", 14)
	_switch.pressed.connect(_on_switch)
	row2.add_child(_switch)

	var hint := _label("Drag ore / logs / twigs here  -  click a slot to take it out", 11, TEXT_COLOR.darkened(0.35))
	col.add_child(hint)


func is_open() -> bool:
	return _panel.visible


## E at a furnace: open it (or close it if it's the one already open).
func open_furnace(f: Node2D) -> void:
	if is_open() and f == furnace:
		close()
		return
	close()
	furnace = f
	furnace.changed.connect(_refresh)
	_panel.visible = true
	if hud and not hud.is_inventory_open():
		hud.toggle_inventory()                   # so you can drag ore and fuel in
		_opened_backpack = true
	if hud:
		hud.drop_target = _accept_drop
	_refresh()


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	if is_instance_valid(furnace) and furnace.changed.is_connected(_refresh):
		furnace.changed.disconnect(_refresh)
	furnace = null
	if hud:
		hud.drop_target = Callable()
		if _opened_backpack and hud.is_inventory_open():
			hud.toggle_inventory()
	_opened_backpack = false


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_open():
		return
	if not is_instance_valid(furnace) or not is_instance_valid(player) \
			or player.global_position.distance_to(furnace.global_position) > CLOSE_DISTANCE:
		close()
		return
	_smelt_bar.value = furnace.progress / Furnace.SMELT_TIME
	var per: float = float(Furnace.FUEL.get(furnace.fuel_id, 30.0)) if furnace.fuel_id != "" else 30.0
	_fuel_bar.value = clampf(furnace.burn_left / per, 0.0, 1.0)
	_place()


## Drop from the backpack (hud.gd): how many of id the slot under `pos` takes.
func _accept_drop(id: String, count: int, pos: Vector2) -> int:
	if not is_open() or not is_instance_valid(furnace):
		return 0
	for key in ["ore", "fuel"]:
		if (_slots[key] as Control).get_global_rect().has_point(pos):
			var took: int = furnace.add_item(id, count)
			if took == 0 and hud:
				var why := "Iron or silver ore only" if key == "ore" else "Logs or twigs only"
				if key == "ore" and Furnace.SMELTS.has(id):
					why = "One kind of ore at a time"
				if key == "fuel" and Furnace.FUEL.has(id):
					why = "One kind of fuel at a time"
				hud.note(why, furnace.global_position + Vector2(0, -70), Color(1.0, 0.6, 0.5))
			return took
	return 0


## Click a slot: everything in it back into the backpack (what doesn't fit stays).
func _take(key: String) -> void:
	if not is_instance_valid(furnace) or inventory == null:
		return
	var got: Array = furnace.take_all(key)
	if got[0] == "" or got[1] <= 0:
		return
	var left: int = inventory.add(got[0], got[1])
	furnace.give_back(key, got[0], left)
	if left > 0 and hud:
		hud.note("Backpack full", furnace.global_position + Vector2(0, -70), Color(1.0, 0.6, 0.5))


func _on_switch() -> void:
	if is_instance_valid(furnace) and not furnace.toggle() and hud:
		hud.note("Needs fuel", furnace.global_position + Vector2(0, -70), Color(1.0, 0.6, 0.5))


func _refresh() -> void:
	if not is_instance_valid(furnace):
		return
	_fill("ore", furnace.ore_id, furnace.ore)
	_fill("fuel", furnace.fuel_id, furnace.fuel_count)
	_fill("output", furnace.output_id, furnace.ingots)
	_switch.text = "On" if furnace.burning else "Off"
	_switch.add_theme_color_override("font_color", FIRE_COLOR if furnace.burning else TEXT_COLOR)
	_switch.add_theme_stylebox_override("normal", Hud._box(Color(0.22, 0.13, 0.07, 0.95) if furnace.burning
			else Color(0.12, 0.14, 0.12, 0.95), FIRE_COLOR if furnace.burning else Hud.BORDER, 4))
	_switch.add_theme_stylebox_override("hover", Hud._box(Color(0.26, 0.17, 0.09, 0.98), Hud.ACCENT, 4))
	_switch.add_theme_stylebox_override("pressed", Hud._box(Color(0.3, 0.18, 0.08, 0.98), Hud.ACCENT, 4))
	_state.text = "Burning" if furnace.burning else ("Ready" if furnace.fuel_count > 0 or furnace.burn_left > 0.0 else "No fuel")
	if furnace.ore > 0 and not furnace.can_smelt():
		_state.text = "Take the ingots out"
	_state.add_theme_color_override("font_color", FIRE_COLOR if furnace.burning and furnace.can_smelt() else TEXT_COLOR.darkened(0.2))


func _fill(key: String, id: String, count: int) -> void:
	var b: Button = _slots[key]
	var icon := b.get_node("Icon") as TextureRect
	var item := Items.get_item(id) if count > 0 else {}
	icon.texture = item.get("icon") if not item.is_empty() else null
	if icon.texture:
		var ts := icon.texture.get_size()
		var k := maxf(floorf(minf((SLOT - 12) / ts.x, (SLOT - 12) / ts.y)), 1.0)
		if ts.x * k > SLOT - 8:
			k = (SLOT - 8) / ts.x
		icon.size = ts * k
		icon.position = ((Vector2(SLOT, SLOT) - icon.size) / 2.0).round()
	(b.get_node("Count") as Label).text = str(count) if count > 1 else ""
	b.tooltip_text = Items.display_name(id) if count > 0 else ""


## Beside the backpack (right of it, bottoms lined up), so the furnace and
## you stay in view; above it if the screen is too narrow.
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_panel.reset_size()
	var pos := Vector2(roundf((view.x - _panel.size.x) / 2.0), view.y - 330.0)
	if hud and hud.is_inventory_open():
		var inv: Rect2 = hud._inv_panel.get_global_rect()
		if inv.end.x + 10.0 + _panel.size.x <= view.x - 8.0:
			pos = Vector2(inv.end.x + 10.0, inv.end.y - _panel.size.y)
		else:
			pos.y = inv.position.y - _panel.size.y - 10.0
	_panel.position = pos.round()


# --- building blocks -------------------------------------------------------------

func _slot_box(key: String, caption: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Hud._box(Color(0.04, 0.05, 0.05, 0.7), Hud.BORDER, 0, 1))
	b.add_theme_stylebox_override("hover", Hud._box(Color(0.10, 0.12, 0.10, 0.85), Hud.ACCENT, 0, 2))
	b.add_theme_stylebox_override("pressed", Hud._box(Color(0.14, 0.12, 0.08, 0.9), Hud.ACCENT, 0, 2))
	b.pressed.connect(_take.bind(key))
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.position = Vector2(0, SLOT - 22)
	count.size = Vector2(SLOT - 4, 20)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(count)
	v.add_child(b)
	var c := _label(caption, 12, TEXT_COLOR.darkened(0.25))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	_slots[key] = b
	return v


func _bar(color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.show_percentage = false
	p.custom_minimum_size = Vector2(110, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.03, 0.9)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(2)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
