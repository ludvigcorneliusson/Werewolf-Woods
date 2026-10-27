extends CanvasLayer
## Start menu shown over the (paused, dimmed) forest when the game launches.
## Screen 1: title + Start. Screen 2: play as Human or Werewolf (werewolf is
## greyed out until it exists). Emits `chosen(role)` and removes itself.

signal chosen(role: String)

const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const ACCENT := Color(0.85, 0.42, 0.2)

var _title_screen: Control
var _role_screen: Control


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS      # works while the game is paused

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_title_screen = _screen()
	_title_screen.add_child(_label("WEREWOLF WOODS", 64, TITLE_COLOR))
	_title_screen.add_child(_label("Survive the night.", 20, TEXT_COLOR.darkened(0.25)))
	_title_screen.add_child(_gap(36))
	var start := _button("Start")
	start.pressed.connect(_show_roles)
	_title_screen.add_child(start)
	var quit := _button("Quit")
	quit.pressed.connect(func(): get_tree().quit())
	_title_screen.add_child(quit)

	_role_screen = _screen()
	_role_screen.add_child(_label("Choose your side", 40, TITLE_COLOR))
	_role_screen.add_child(_gap(28))
	var human := _button("Human")
	human.tooltip_text = "Hide, build and survive until dawn."
	human.pressed.connect(func(): _choose("human"))
	_role_screen.add_child(human)
	_role_screen.add_child(_label("Hide, build and survive.", 16, TEXT_COLOR.darkened(0.3)))
	_role_screen.add_child(_gap(12))
	var wolf := _button("Werewolf")
	wolf.pressed.connect(func(): _choose("werewolf"))
	_role_screen.add_child(wolf)
	_role_screen.add_child(_label("Hunt them down.", 16, TEXT_COLOR.darkened(0.3)))
	_role_screen.add_child(_gap(24))
	var back := _button("Back", true)
	back.pressed.connect(_show_title)
	_role_screen.add_child(back)

	_show_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _role_screen.visible:
		_show_title()
		get_viewport().set_input_as_handled()


func _show_title() -> void:
	_title_screen.visible = true
	_role_screen.visible = false
	_title_screen.get_child(3).grab_focus.call_deferred()     # Start button: Enter/gamepad work


func _show_roles() -> void:
	_title_screen.visible = false
	_role_screen.visible = true
	_role_screen.get_child(2).grab_focus.call_deferred()      # Human button


func _choose(role: String) -> void:
	chosen.emit(role)
	queue_free()


# --- building blocks ----------------------------------------------------------

func _screen() -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	box.visibility_changed.connect(func(): center.visible = box.visible)
	return box


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6 if size >= 30 else 3)
	return l


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String, small := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220 if small else 300, 44 if small else 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20 if small else 26)
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	b.add_theme_stylebox_override("normal", _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
	b.add_theme_stylebox_override("focus", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
	b.add_theme_stylebox_override("pressed", _box(Color(0.22, 0.14, 0.09, 0.95), ACCENT))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.08, 0.7), Color(0.22, 0.22, 0.22)))
	return b


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb
