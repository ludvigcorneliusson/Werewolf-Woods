extends CanvasLayer
## Start menu shown over the (paused, dimmed) forest when the game launches.
## Screen 1: title + Start / Settings / Quit. Screen 2: play as Human or
## Werewolf. Settings screen: map size, seed, display, difficulty, volume
## (stored in scripts/game_settings.gd). Emits `chosen(role)` and removes itself;
## emits `map_changed` when the map size or seed was changed (main.gd then
## restarts with the new forest).

signal chosen(role: String)
signal map_changed

const GameSettings := preload("res://scripts/game_settings.gd")

const TITLE_COLOR := Color(0.93, 0.86, 0.68)
const TEXT_COLOR := Color(0.88, 0.86, 0.80)
const ACCENT := Color(0.85, 0.42, 0.2)

var _title_screen: Control
var _role_screen: Control
var _settings_screen: Control
var _map_before := []              # [size, seed] when the settings screen opened
var _seed_box: SpinBox


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

	_build_settings()
	_show_title()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_role_screen.visible or _settings_screen.visible):
		if _settings_screen.visible:
			_close_settings()
		else:
			_show_title()
		get_viewport().set_input_as_handled()


func _show_title() -> void:
	_title_screen.visible = true
	_role_screen.visible = false
	_settings_screen.visible = false
	_title_screen.get_child(3).grab_focus.call_deferred()     # Start button: Enter/gamepad work


func _show_roles() -> void:
	_title_screen.visible = false
	_role_screen.visible = true
	_role_screen.get_child(2).grab_focus.call_deferred()      # Human button


func _choose(role: String) -> void:
	chosen.emit(role)
	queue_free()


# --- settings -----------------------------------------------------------------

func _build_settings() -> void:
	_settings_screen = _screen()
	_settings_screen.get_parent().theme = _theme()
	_settings_screen.add_child(_label("Settings", 40, TITLE_COLOR))
	_settings_screen.add_child(_gap(16))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_screen.add_child(grid)

	# Map size
	var size_opt := _options(GameSettings.MAP_SIZES.keys(), GameSettings.map_size)
	for i in size_opt.item_count:
		var n: String = size_opt.get_item_text(i)
		size_opt.set_item_tooltip(i, "%d x %d tiles" % [GameSettings.MAP_SIZES[n], GameSettings.MAP_SIZES[n]])
	size_opt.item_selected.connect(func(i): GameSettings.map_size = size_opt.get_item_text(i))
	_row(grid, "Map size", size_opt)

	# Seed + randomize
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 999999
	_seed_box.step = 1
	_seed_box.rounded = true
	_seed_box.custom_minimum_size = Vector2(150, 0)
	_seed_box.value = GameSettings.map_seed
	_seed_box.tooltip_text = "Same seed + same map size = same forest (share it with friends)."
	_seed_box.value_changed.connect(func(v): GameSettings.map_seed = int(v))
	seed_row.add_child(_seed_box)
	var dice := _button("Randomize", true)
	dice.custom_minimum_size = Vector2(140, 40)
	dice.pressed.connect(func():
		GameSettings.randomize_seed()
		_seed_box.value = GameSettings.map_seed)
	seed_row.add_child(dice)
	_row(grid, "Map seed", seed_row)

	var every := CheckBox.new()
	every.text = "New random seed every round"
	every.button_pressed = GameSettings.random_seed
	every.toggled.connect(func(on): GameSettings.random_seed = on)
	_row(grid, "", every)

	# Display
	var disp := _options(["Fullscreen", "Windowed"], "Fullscreen" if GameSettings.fullscreen else "Windowed")
	disp.item_selected.connect(func(i):
		GameSettings.fullscreen = i == 0
		GameSettings.apply_display(get_window()))
	_row(grid, "Display", disp)

	# Difficulty
	var diff := _options(GameSettings.DIFFICULTIES.keys(), GameSettings.difficulty)
	for i in diff.item_count:
		var n: String = diff.get_item_text(i)
		diff.set_item_tooltip(i, "Werewolf speed x%.2f" % GameSettings.DIFFICULTIES[n])
	diff.tooltip_text = "How fast the AI werewolf is."
	diff.item_selected.connect(func(i): GameSettings.difficulty = diff.get_item_text(i))
	_row(grid, "Difficulty", diff)

	# Volume
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 100
	vol.step = 1
	vol.value = round(GameSettings.volume * 100.0)
	vol.custom_minimum_size = Vector2(300, 28)
	vol.value_changed.connect(func(v):
		GameSettings.volume = v / 100.0
		GameSettings.apply_volume())
	_row(grid, "Volume", vol)

	_settings_screen.add_child(_gap(20))
	var back := _button("Back", true)
	back.pressed.connect(_close_settings)
	_settings_screen.add_child(back)


func _show_settings() -> void:
	_map_before = [GameSettings.map_size, GameSettings.map_seed]
	_seed_box.value = GameSettings.map_seed                  # may have been rolled for this round
	_title_screen.visible = false
	_settings_screen.visible = true
	_settings_screen.get_child(2).get_child(1).grab_focus.call_deferred()   # map size


func _close_settings() -> void:
	if _seed_box.get_line_edit().has_focus():
		_seed_box.apply()                                    # take a seed still being typed
	GameSettings.save_settings()
	if _map_before != [GameSettings.map_size, GameSettings.map_seed]:
		map_changed.emit()                                   # main.gd rebuilds the forest
		return
	_show_title()


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := _label(text, 22, TEXT_COLOR)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(150, 0)
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _options(items: Array, selected: String) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(300, 40)
	for it in items:
		o.add_item(it)
		if it == selected:
			o.select(o.item_count - 1)
	return o


## Look of the settings controls, matching the menu buttons.
func _theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_color("font_color", type, TEXT_COLOR)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
	for type in ["OptionButton"]:
		t.set_stylebox("normal", type, _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
		t.set_stylebox("hover", type, _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
		t.set_stylebox("focus", type, _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
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
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.45))
	b.add_theme_stylebox_override("normal", _box(Color(0.10, 0.13, 0.11, 0.92), Color(0.32, 0.36, 0.30)))
	b.add_theme_stylebox_override("hover", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
	b.add_theme_stylebox_override("focus", _box(Color(0.16, 0.20, 0.15, 0.95), ACCENT))
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
