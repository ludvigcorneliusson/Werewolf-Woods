extends CanvasLayer
## In-game menu (Esc). The game is NOT paused (it will be multiplayer): the
## world, the night and the werewolf keep going while it is open, and your
## character stands still because main.gd turns its movement input off.
##   Resume            - close the menu (Esc does the same)
##   Advanced settings - world tuning while you play (scripts/advanced_settings.gd)
##   Quit to main menu - leave the round
##   Quit game         - close the game
## main.gd creates it once and toggles it with open() / close().

signal closed

const StartMenu := preload("res://scripts/start_menu.gd")
const AdvancedSettings := preload("res://scripts/advanced_settings.gd")

const VIGNETTE := """
shader_type canvas_item;
uniform vec4 edge : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform float centre_dim = 0.3;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.8);
	float v = smoothstep(0.15, 0.75, length(d));
	COLOR = vec4(edge.rgb * v, mix(centre_dim, edge.a, v));
}
"""

var main: Node                      # set by main.gd before adding
var _resume: Button
var _menu_box: Control
var _advanced: Control


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Dark vignette; the game stays visible (and running) behind it.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE
	mat.shader = sh
	dim.material = mat
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_menu_box = center

	box.add_child(StartMenu._label("Menu", 40, StartMenu.TITLE_COLOR))
	box.add_child(StartMenu._gap(16))
	_resume = StartMenu._button("Resume", true)
	_resume.pressed.connect(close)
	box.add_child(_resume)
	var adv := StartMenu._button("Advanced settings", true)
	adv.tooltip_text = "Weather, day & night, map/forest, fog, werewolf and wind."
	adv.pressed.connect(_open_advanced)
	box.add_child(adv)
	var leave := StartMenu._button("Quit to main menu", true)
	leave.tooltip_text = "Leave the round and return to the main menu."
	leave.pressed.connect(_on_leave)
	box.add_child(leave)
	var quit := StartMenu._button("Quit game", true)
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	_advanced = AdvancedSettings.new()
	_advanced.setup(main)
	_advanced.visible = false
	_advanced.back.connect(func():
		_menu_box.visible = true
		_resume.grab_focus.call_deferred())
	add_child(_advanced)
	for b in [_resume, adv, leave, quit]:
		b.custom_minimum_size.x = 280


func _open_advanced() -> void:
	_menu_box.visible = false
	_advanced.open()


func open() -> void:
	visible = true
	_menu_box.visible = true
	_advanced.visible = false
	_resume.grab_focus.call_deferred()          # Enter = Resume, never an accidental quit


func close() -> void:
	if not visible:
		return
	if _advanced.visible:
		_advanced.close()
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _on_leave() -> void:
	# Back to the main menu: the scene restarts and shows the start menu.
	get_tree().paused = false
	get_tree().reload_current_scene()
