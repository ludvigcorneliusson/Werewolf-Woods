extends CanvasLayer
## Start menu shown over the (paused, dimmed) forest when the game launches.
## Screen 1: title + Start / Settings / Quit. Screen 2: play as Human or
## Werewolf. Settings = the same panel as in the Esc menu
## (scripts/advanced_settings.gd: general, map, weather, ...); closing it after
## a map change rebuilds the forest (main.gd restarts the scene into this menu).
## Emits `chosen(role)` and removes itself.

signal chosen(role: String)
signal map_changed

const GameSettings := preload("res://scripts/game_settings.gd")
const SettingsPanel := preload("res://scripts/advanced_settings.gd")

const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const ACCENT := Color(0.85, 0.42, 0.2)

var main: Node                     # set by main.gd before adding (the Settings panel tunes it)
var _title_screen: Control
var _role_screen: Control
var _settings: Control


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
	var settings := _button("Settings")
	settings.pressed.connect(_show_settings)
	_title_screen.add_child(settings)
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

	_settings = SettingsPanel.new()
	_settings.setup(main, true)
	_settings.visible = false
	_settings.back.connect(_show_title)
	add_child(_settings)
	_show_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_role_screen.visible or _settings.visible):
		if _settings.visible:
			_settings.close()
		else:
			_show_title()
		get_viewport().set_input_as_handled()


func _show_title() -> void:
	_title_screen.visible = true
	_role_screen.visible = false
	_settings.visible = false
	_title_screen.get_child(3).grab_focus.call_deferred()     # Start button: Enter/gamepad work


func _show_roles() -> void:
	_title_screen.visible = false
	_role_screen.visible = true
	_role_screen.get_child(2).grab_focus.call_deferred()      # Human button


func _choose(role: String) -> void:
	chosen.emit(role)
	queue_free()


# --- settings -----------------------------------------------------------------

func _show_settings() -> void:
	_title_screen.visible = false
	_settings.open()


## Look of the settings controls, matching the menu buttons.
static func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT_COLOR)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT_COLOR)            # highlight on hover only
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
	# Keyboard focus draws nothing: only the control under the mouse lights up.
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "ColorPickerButton", "MenuButton", "HSlider", "SpinBox"]:
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for type in ["OptionButton"]:
		t.set_stylebox("normal", type, _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
		t.set_stylebox("hover", type, _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
		t.set_stylebox("pressed", type, _box(Color(0.22, 0.14, 0.09, 0.95), ACCENT))
	t.set_color("font_color", "LineEdit", TEXT_COLOR)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.08, 0.10, 0.09, 0.98), Color(0.32, 0.36, 0.30)))
	t.set_color("font_color", "PopupMenu", TEXT_COLOR)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_font_size("font_size", "TooltipLabel", 16)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.32, 0.36, 0.30)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate()
	fill.bg_color = ACCENT
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t


# --- building blocks (static: also used by escape_menu.gd) -----------------------

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


static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6 if size >= 30 else 3)
	return l


static func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func _button(text: String, small := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220 if small else 300, 44 if small else 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20 if small else 26)
	b.add_theme_color_override("font_color", TEXT_COLOR)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", TEXT_COLOR)      # highlight on hover only
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	b.add_theme_stylebox_override("normal", _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", _box(Color(0.22, 0.14, 0.09, 0.95), ACCENT))
	b.add_theme_stylebox_override("disabled", _box(Color(0.08, 0.08, 0.08, 0.7), Color(0.22, 0.22, 0.22)))
	return b


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb
