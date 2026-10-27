extends CanvasLayer
## Level-up screen (Vampire Survivors style): the game pauses and up to three
## upgrade cards appear. Click one or press 1-3. main.gd opens it with
## show_choices() and gets the pick through `chosen`.

signal chosen(id: String)

const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const ACCENT := Color(0.85, 0.42, 0.2)
const GOLD := Color(0.98, 0.84, 0.43)

var _dim: ColorRect
var _box: VBoxContainer
var _title: Label
var _sub: Label
var _row: HBoxContainer
var _ids: Array[String] = []
var _open := false


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS          # runs while the game is paused
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.02, 0.62)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 14)
	center.add_child(_box)
	_title = _label("LEVEL UP!", 46, GOLD, 8)
	_box.add_child(_title)
	_sub = _label("", 18, TEXT_COLOR, 3)
	_box.add_child(_sub)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 18)
	_box.add_child(_row)
	var hint := _label("Click a card or press 1-3", 15, TEXT_COLOR.darkened(0.3), 3)
	_box.add_child(hint)
	visible = false


func is_open() -> bool:
	return _open


## cards = [{id, name, icon, level (current), desc}], up to three.
func show_choices(level: int, cards: Array) -> void:
	for c in _row.get_children():
		c.queue_free()
	_ids.clear()
	_sub.text = "Level %d  -  choose an upgrade" % level
	for i in cards.size():
		var card := _card(i, cards[i])
		_row.add_child(card)
		_ids.append(cards[i].id)
		# Pop in one after the other.
		card.modulate.a = 0.0
		card.scale = Vector2(0.85, 0.85)
		var t := card.create_tween().set_parallel().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(card, "modulate:a", 1.0, 0.18).set_delay(0.06 * i)
		t.tween_property(card, "scale", Vector2.ONE, 0.22).set_delay(0.06 * i) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_title.pivot_offset = _title.size / 2.0
	var tt := _title.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_title.scale = Vector2(1.3, 1.3)
	tt.tween_property(_title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	visible = true
	_open = true


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var n: int = event.physical_keycode - KEY_1
		if n >= 0 and n < _ids.size():
			get_viewport().set_input_as_handled()
			_pick(_ids[n])


func _pick(id: String) -> void:
	if not _open:
		return
	_open = false
	visible = false
	chosen.emit(id)


func _card(index: int, c: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 250)
	b.focus_mode = Control.FOCUS_NONE
	# Rarity colours the card: border, a faint tint, and a glow for rare/epic.
	var rc: Color = c.get("color", Color(0.45, 0.85, 0.42))
	var rarity: String = c.get("rarity", "Common")
	var glow := 0 if rarity == "Common" else (8 if rarity == "Rare" else 14)
	var bg := Color(0.09, 0.11, 0.10, 0.96).lerp(rc.darkened(0.75), 0.35)
	b.add_theme_stylebox_override("normal", _style(bg, rc, glow))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.06), rc.lightened(0.35), glow + 4))
	b.add_theme_stylebox_override("pressed", _style(bg.lightened(0.12), Color.WHITE, glow))
	b.pressed.connect(_pick.bind(c.id))
	b.mouse_entered.connect(func(): b.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
			.tween_property(b, "position:y", -6.0, 0.08).as_relative())
	b.mouse_exited.connect(func(): b.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
			.tween_property(b, "position:y", 6.0, 0.08).as_relative())
	b.pivot_offset = b.custom_minimum_size / 2.0
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 14
	col.offset_right = -14
	col.offset_top = 14
	col.offset_bottom = -12
	col.alignment = BoxContainer.ALIGNMENT_BEGIN        # same layout on every card
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var key := _label("%d  -  %s" % [index + 1, rarity.to_upper()], 14, rc, 3)
	col.add_child(key)
	var icon := TextureRect.new()
	icon.texture = c.icon
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	col.add_child(_label(c.name, 22, TITLE_COLOR, 4))
	var lvl: int = c.level
	col.add_child(_label("New!" if lvl == 0 else "Level %d  >  %d" % [lvl, lvl + 1], 15, GOLD if lvl == 0 else ACCENT.lightened(0.25), 3))
	var d := _label(c.desc, 16, TEXT_COLOR, 3)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(170, 0)
	col.add_child(d)
	for n in col.get_children():
		if n is Control:
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _label(text: String, size: int, color: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	return l


static func _style(bg: Color, border: Color, glow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	if glow > 0:
		s.shadow_color = Color(border, 0.45)
		s.shadow_size = glow
	return s
