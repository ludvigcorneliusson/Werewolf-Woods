extends Control
## Settings panel, opened from the main menu (Settings) and from the Esc menu
## (Settings). General tab: display, difficulty, volume. Then game-world tuning:
## map/forest, weather, day & night, fog & vision, werewolf AI and wind. In a
## round the game keeps running behind it.
##
## The controls are built from the settings themselves: each entry in SECTIONS
## names a property on Main (scripts/main.gd) or on the WorldBuilder node, and
## its type and range come from that property's @export hint - so the panel
## uses the same limits as the Inspector. Add a property name to a list below
## to show it here.
##
## Changes apply immediately (Main's setters push them to the game), except
## map/forest settings, which take effect when you press Regenerate (restarts
## the round with a new forest; from the main menu the forest is rebuilt when
## you leave Settings). Everything is saved (game_settings.gd,
## "advanced" section) and re-applied every round; Reset puts back the values
## from main.tscn.

signal back

const StartMenu := preload("res://scripts/start_menu.gd")
const GameSettings := preload("res://scripts/game_settings.gd")

## [tab title, target ("main" or "builder"), [property names]]
const SECTIONS := [
	["Map", "builder", [
		"clearing", "clearing_fade", "tree_spacing", "tree_jitter", "forest_fill", "patch_frequency",
		"tall_pines", "dark_pines", "dead_tree_share", "trunk_gap",
		"stumps", "logs", "boulders", "mossy_rocks", "ferns", "grass_tufts", "small_bushes", "big_bushes",
		"fallen_trees", "stump_logs", "mushroom_clusters", "pebbles", "sticks", "sticks_near_trees", "stick_tree_distance", "ore_nodes", "small_ore_nodes", "small_ore_in_stone", "ore_near_boulders", "stone_clusters", "stone_cluster_size", "stone_cluster_radius", "stone_cluster_pebbles", "campfire_space",
		"painted_tree_clearance", "painted_clearance", "keep_painted_visible", "rabbits"]],
	["Weather", "main", [
		"weather_enabled", "rain_chance", "clear_spell", "rain_spell", "rain_fade",
		"rain_drops", "rain_splashes", "rain_color", "rain_speed", "rain_slant", "rain_volume",
		"rain_tint", "rain_wind_boost", "rain_footprint_life", "rain_hearing"]],
	["Day & Night", "main", [
		"day_length", "dusk_length", "day_tint", "dusk_tint", "campfire_day_glow",
		"night_eyes", "eyes_glow", "eyes_close_distance"]],
	["Fog & Vision", "main", [
		"fog_enabled", "fog_color", "fog_darkness", "vision_radius", "fog_start", "fog_density",
		"vision_brightness", "vision_tint", "vision_squash", "trunk_shade", "canopy_shade",
		"prop_shade", "prop_side_shade", "prop_back_shade", "cell_softness"]],
	["Experience", "main", [
		"xp_first_level", "xp_curve", "xp_tall_pine", "xp_small_pine", "xp_dead_tree",
		"upgrade_choices", "chop_speed_per_level", "run_speed_per_level", "hits_saved_per_level",
		"rare_chance", "epic_chance", "rare_power", "epic_power", "xp_stump", "stump_hits", "xp_ore", "xp_small_ore", "xp_stone"]],
	["Werewolf & Wind", "main", [
		"ai_werewolf", "werewolf_spawns_at", "werewolf_spawn_distance", "werewolf_sense", "werewolf_lose",
		"werewolf_walk_speed", "werewolf_sprint_speed",
		"wind_enabled", "wind_strength", "wind_speed", "wind_lean", "wave_length",
		"tree_hits", "dead_tree_hits", "chop_speed", "ore_hits", "small_ore_hits", "stone_hits", "mine_speed",
		"max_health", "werewolf_damage", "werewolf_bite_interval", "health_regen", "regen_delay", "drop_lifetime", "build_reach"]],
]

## Short explanations shown as tooltips (the @export doc comments are not
## available in the running game).
const TIPS := {
	"xp_first_level": "XP needed for the first level-up.",
	"xp_curve": "How the XP needed grows: 1 = linear (10, 20, 30...), 0 = flat, 2 = steep (10, 40, 90...).",
	"chop_speed_per_level": "Swift Axe: chopping speed per level (0.1 = +10%).",
	"run_speed_per_level": "Light Boots: walk and sprint speed per level.",
	"hits_saved_per_level": "Heavy Blade: hits fewer to fell a tree per level (never below 1).",
	"tree_spacing": "Average distance between trees. Lower = denser forest.",
	"forest_fill": "Share of the forest area that gets trees (1 = everywhere).",
	"patch_frequency": "Size of the dense/open patches. Higher = smaller, more frequent patches.",
	"clearing": "Radius of the open clearing around the campfire.",
	"dead_tree_share": "Share of trees that are dead.",
	"trunk_gap": "Minimum gap between tree trunks.",
	"ore_nodes": "Copper ore nodes per 1000 x 1000 px of forest (a Medium map is about 110 of those).",
	"ore_near_boulders": "Share of ore nodes placed right next to a boulder.",
	"ore_hits": "Pickaxe hits to break an ore node.",
	"stone_hits": "Pickaxe hits to break a stone node.",
	"small_ore_hits": "Pickaxe hits to break a small copper deposit.",
	"small_ore_nodes": "Small copper deposits per 1000 x 1000 px of forest.",
	"small_ore_in_stone": "Share of small copper deposits placed inside stone clusters.",
	"stone_clusters": "Clusters of stone nodes per 1000 x 1000 px of forest.",
	"stone_cluster_size": "Stone nodes per cluster: min / max.",
	"stone_cluster_pebbles": "Loose pebbles around each cluster: min / max.",
	"sticks_near_trees": "Share of sticks lying near a tree (the rest anywhere on the map).",
	"stick_tree_distance": "How far from the trunk's edge those sticks lie: min / max px.",
	"painted_tree_clearance": "Generated trees stay this far from props you painted in World/Placed.",
	"painted_clearance": "Other generated props stay this far from your painted props.",
	"rabbits": "Rabbits per million square px (Medium map = about 110 million). They flee from the settler and the werewolf.",
	"keep_painted_visible": "Keep tall trees out of the spot in front of painted props, so their canopies don't hide them.",
	"rain_chance": "Chance that each weather spell is rain.",
	"clear_spell": "Length of a clear spell: min / max seconds.",
	"rain_spell": "Length of a rain spell: min / max seconds.",
	"rain_footprint_life": "Footprints last this fraction of their normal time in full rain.",
	"rain_hearing": "The werewolf's steps carry this fraction of their normal distance in full rain.",
	"rain_wind_boost": "Extra wind in the trees during rain (1 = double).",
	"night_eyes": "Tiny glowing animal eyes in a few trees at night.",
	"eyes_glow": "Glow around each eye (0 = just the eyes).",
	"eyes_close_distance": "The eyes shut when you come this close to their tree.",
	"campfire_day_glow": "Campfire glow in daylight (1 = full night glow).",
	"vision_radius": "How far you can see at night.",
	"fog_start": "Where the darkness starts fading in (share of the vision radius).",
	"fog_density": "How quickly it gets dark towards the edge of your vision.",
	"werewolf_sense": "Distance at which the werewolf notices you and starts chasing.",
	"werewolf_lose": "Distance at which it loses you.",
	"werewolf_walk_speed": "On Normal difficulty; the menu Difficulty scales it.",
	"werewolf_sprint_speed": "On Normal difficulty. You sprint at 200.",
}

var main: Node
## Opened from the main menu (no round running): map changes are applied by
## rebuilding the forest behind the menu when Settings is closed.
var in_main_menu := false
var _builder: Node
var _regen_note: Label
var _tabs: TabContainer
var _seed_box: SpinBox
var _map_dirty := false


func setup(p_main: Node, from_main_menu := false) -> void:
	main = p_main
	in_main_menu = from_main_menu
	_builder = main.get_node_or_null("WorldBuilder")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _theme()

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(StartMenu._label("Settings", 34, StartMenu.TITLE_COLOR))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(820, 470)
	box.add_child(_tabs)

	_general(_tab("General"))

	for sec in SECTIONS:
		var target := _target(sec[1])
		var grid := _tab(sec[0])
		match sec[0]:
			"Map":
				_map_header(grid)
			"Weather":
				_actions(grid, "Right now", [["Rain now", func(): main.force_rain(true)], ["Clear now", func(): main.force_rain(false)]])
			"Day & Night":
				_actions(grid, "Jump to", [["Day", func(): main.jump_time("day")], ["Dusk", func(): main.jump_time("dusk")], ["Night", func(): main.jump_time("night")]])
		if target == null:
			continue
		for prop: String in sec[2]:
			_add_setting(grid, sec[1], target, prop)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	var reset := StartMenu._button("Reset to defaults", true)
	reset.custom_minimum_size.x = 240
	reset.tooltip_text = "Put every world setting back to the project's values (main.tscn). General settings are kept."
	reset.pressed.connect(_reset_all)
	bottom.add_child(reset)
	var close_btn := StartMenu._button("Back", true)
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)


func open() -> void:
	visible = true
	_map_dirty = false
	if _seed_box:
		_seed_box.set_value_no_signal(GameSettings.map_seed)   # may have been rolled for this round
	_refresh()


func close() -> void:
	if not visible:
		return
	if _seed_box and _seed_box.get_line_edit().has_focus():
		_seed_box.apply()                                    # take a seed still being typed
	visible = false
	GameSettings.save_settings()
	if in_main_menu and _map_dirty and main and main.has_method("_on_map_settings_changed"):
		main._on_map_settings_changed()                      # rebuild the forest behind the menu
		return
	back.emit()


## General tab: display, difficulty and volume (the player's own settings).
func _general(grid: GridContainer) -> void:
	var disp := _choice(["Fullscreen", "Windowed"], "Fullscreen" if GameSettings.fullscreen else "Windowed")
	disp.item_selected.connect(func(i):
		GameSettings.fullscreen = i == 0
		GameSettings.apply_display(get_window()))
	_row(grid, "Display", disp, "F11 also switches.")
	_controls["general.display"] = func(): disp.select(0 if GameSettings.fullscreen else 1)

	var diff := _choice(GameSettings.DIFFICULTIES.keys(), GameSettings.difficulty)
	for i in diff.item_count:
		var n: String = diff.get_item_text(i)
		diff.set_item_tooltip(i, "Werewolf speed x%.2f" % GameSettings.DIFFICULTIES[n])
	diff.item_selected.connect(func(i):
		GameSettings.difficulty = diff.get_item_text(i)
		if main and main.has_method("_apply_werewolf"):
			main._apply_werewolf())                      # a werewolf already out speeds up/down
	_row(grid, "Difficulty", diff, "How fast the AI werewolf is.")

	var vol := _percent_slider(GameSettings.volume)
	vol.value_changed.connect(func(x):
		GameSettings.volume = x / 100.0
		GameSettings.apply_volume())
	_row(grid, "Volume", vol)
	var mus := _percent_slider(GameSettings.music_volume)
	mus.value_changed.connect(func(x):
		GameSettings.music_volume = x / 100.0
		GameSettings.apply_volume())
	_row(grid, "Music", mus, "Music volume, on top of the main volume.")


func _percent_slider(value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size.y = 28
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value = round(value * 100.0)
	return slider


func _choice(items: Array, selected: String) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
		if it == selected:
			o.select(o.item_count - 1)
	return o


# --- building the tabs ----------------------------------------------------------

func _tab(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)
	return grid


func _row(grid: GridContainer, text: String, control: Control, tip := "") -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(230, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = tip
	grid.add_child(control)


func _actions(grid: GridContainer, text: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		var btn := StartMenu._button(b[0], true)
		btn.custom_minimum_size = Vector2(120, 36)
		btn.pressed.connect(b[1])
		row.add_child(btn)
	_row(grid, text, row)


## Map size + seed (shared with the main menu Settings) and Regenerate.
func _map_header(grid: GridContainer) -> void:
	var size_opt := OptionButton.new()
	for n in GameSettings.MAP_SIZES.keys():
		size_opt.add_item(n)
		size_opt.set_item_tooltip(size_opt.item_count - 1, "%d x %d tiles" % [GameSettings.MAP_SIZES[n], GameSettings.MAP_SIZES[n]])
		if n == GameSettings.map_size:
			size_opt.select(size_opt.item_count - 1)
	size_opt.item_selected.connect(func(i):
		GameSettings.map_size = size_opt.get_item_text(i)
		_needs_regen())
	_row(grid, "Map size", size_opt)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var seed_box := SpinBox.new()
	_seed_box = seed_box
	seed_box.max_value = 999999
	seed_box.rounded = true
	seed_box.value = GameSettings.map_seed
	seed_box.custom_minimum_size.x = 150
	seed_box.value_changed.connect(func(v):
		GameSettings.map_seed = int(v)
		_needs_regen())
	seed_row.add_child(seed_box)
	var dice := StartMenu._button("Randomize", true)
	dice.custom_minimum_size = Vector2(140, 36)
	dice.pressed.connect(func():
		GameSettings.randomize_seed()
		seed_box.value = GameSettings.map_seed)
	seed_row.add_child(dice)
	_row(grid, "Map seed", seed_row, "Same seed + same map size = same forest (share it with friends).")

	var every := CheckBox.new()
	every.text = "New random seed every round"
	every.button_pressed = GameSettings.random_seed
	every.toggled.connect(func(on): GameSettings.random_seed = on)
	_row(grid, "", every)

	var regen := StartMenu._button("Regenerate map", true)
	regen.custom_minimum_size = Vector2(240, 40)
	regen.tooltip_text = "Build a new forest with these settings and restart the round."
	regen.pressed.connect(func():
		GameSettings.save_settings()
		main.regenerate_map())
	_regen_note = Label.new()
	_regen_note.text = "Map changes apply when you regenerate (restarts the round)."
	_regen_note.add_theme_color_override("font_color", Color(0.75, 0.72, 0.62))
	_regen_note.add_theme_font_size_override("font_size", 15)
	var col := VBoxContainer.new()
	col.add_child(regen)
	col.add_child(_regen_note)
	_row(grid, "", col)
	if in_main_menu:
		regen.visible = false                            # nothing to restart yet
		_regen_note.text = "Map changes apply when you close Settings."


func _needs_regen() -> void:
	_map_dirty = true
	if _regen_note:
		_regen_note.text = "Changed - the new forest is built when you close Settings." if in_main_menu \
				else "Changed - press Regenerate map to build the new forest."
		_regen_note.add_theme_color_override("font_color", StartMenu.ACCENT)


# --- one setting --------------------------------------------------------------

var _controls := {}                 # "target.prop" -> Callable that refreshes the control from the value


func _add_setting(grid: GridContainer, tname: String, target: Object, prop: String) -> void:
	var info := _prop_info(target, prop)
	if info.is_empty():
		return
	var key := tname + "." + prop
	var setter := func(v):
		target.set(prop, v)
		GameSettings.advanced[key] = v
		if tname == "builder":
			_needs_regen()
	var tip: String = TIPS.get(prop, "")
	var label := prop.capitalize()
	var c: Control
	var refresh: Callable
	match info.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.toggled.connect(setter)
			refresh = func(): cb.set_pressed_no_signal(target.get(prop))
			c = cb
		TYPE_INT, TYPE_FLOAT:
			var r := _range(info)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var slider := HSlider.new()
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var spin := SpinBox.new()
			spin.custom_minimum_size.x = 120
			spin.suffix = r.suffix
			for rg in [slider, spin]:
				rg.min_value = r.min
				rg.max_value = r.max
				rg.step = r.step if info.type == TYPE_FLOAT else maxf(r.step, 1.0)
				rg.allow_greater = true
				rg.allow_lesser = true
			slider.share(spin)
			var is_int: bool = info.type == TYPE_INT
			spin.value_changed.connect(func(v): setter.call(int(v) if is_int else v))
			row.add_child(slider)
			row.add_child(spin)
			refresh = func(): spin.set_value_no_signal(target.get(prop))
			c = row
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(120, 34)
			cp.edit_alpha = true
			cp.color_changed.connect(setter)
			refresh = func(): cp.color = target.get(prop)
			c = cp
		TYPE_VECTOR2:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var xs := SpinBox.new()
			var ys := SpinBox.new()
			for s in [xs, ys]:
				s.min_value = 0
				s.max_value = 100000
				s.step = 1
				s.custom_minimum_size.x = 130
				s.value_changed.connect(func(_v): setter.call(Vector2(xs.value, ys.value)))
			xs.prefix = "min"
			ys.prefix = "max"
			row.add_child(xs)
			row.add_child(ys)
			refresh = func():
				var v: Vector2 = target.get(prop)
				xs.set_value_no_signal(v.x)
				ys.set_value_no_signal(v.y)
			c = row
		TYPE_STRING:
			var opt := OptionButton.new()
			var items: PackedStringArray = info.hint_string.split(",") if info.hint == PROPERTY_HINT_ENUM else PackedStringArray()
			for it in items:
				opt.add_item(it)
			opt.item_selected.connect(func(i): setter.call(opt.get_item_text(i)))
			refresh = func():
				for i in opt.item_count:
					if opt.get_item_text(i) == target.get(prop):
						opt.select(i)
			c = opt
		_:
			return
	_controls[key] = refresh
	refresh.call()
	_row(grid, label, c, tip)


func _refresh() -> void:
	for k in _controls:
		_controls[k].call()


func _reset_all() -> void:
	main.reset_advanced_settings()
	_refresh()
	_map_dirty = true
	if _regen_note:
		_regen_note.text = "Reset - the forest is rebuilt when you close Settings." if in_main_menu \
				else "Reset - press Regenerate map to rebuild the forest with the defaults."


func _target(tname: String) -> Object:
	return main if tname == "main" else _builder


func _prop_info(target: Object, prop: String) -> Dictionary:
	for p in target.get_property_list():
		if p.name == prop:
			return p
	return {}


## Parses an @export_range hint: "min,max,step,suffix:px" -> {min, max, step, suffix}.
func _range(info: Dictionary) -> Dictionary:
	var r := {"min": 0.0, "max": 1000.0, "step": 0.01, "suffix": ""}
	if info.hint != PROPERTY_HINT_RANGE:
		return r
	var parts: PackedStringArray = info.hint_string.split(",")
	if parts.size() >= 2:
		r.min = parts[0].to_float()
		r.max = parts[1].to_float()
	if parts.size() >= 3 and parts[2].is_valid_float():
		r.step = parts[2].to_float()
	for p in parts:
		if p.begins_with("suffix:"):
			r.suffix = p.substr(7)
	return r


# --- look ------------------------------------------------------------------------

func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.06, 0.94)
	sb.border_color = Color(0.32, 0.36, 0.30)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18)
	return sb


func _theme() -> Theme:
	var t: Theme = StartMenu._theme()
	t.default_font_size = 17
	t.set_color("font_color", "Label", StartMenu.TEXT_COLOR)
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())     # highlight on hover only
	for st in ["tab_selected", "tab_hovered", "tab_unselected"]:
		var on: bool = st != "tab_unselected"
		var sb := StartMenu._box(Color(0.16, 0.20, 0.15, 0.95) if on else Color(0.08, 0.10, 0.09, 0.92),
				StartMenu.ACCENT if st == "tab_selected" else Color(0.32, 0.36, 0.30))
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		t.set_stylebox(st, "TabContainer", sb)
	t.set_stylebox("panel", "TabContainer", StartMenu._box(Color(0.07, 0.09, 0.08, 0.9), Color(0.32, 0.36, 0.30)))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", StartMenu.TEXT_COLOR.darkened(0.2))
	t.set_color("font_hovered_color", "TabContainer", Color.WHITE)
	t.set_font_size("font_size", "TabContainer", 18)
	return t
