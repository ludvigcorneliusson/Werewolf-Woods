extends CanvasLayer
## In-game menu (Esc). The game is NOT paused (it will be multiplayer): the
## world, the night and the werewolf keep going while it is open, and your
## character stands still because main.gd turns its movement input off.
##   ABANDON   - leave the round, back to the main menu
##   Resume    - close the menu (Esc does the same)
##   Quit game - close the game
## main.gd creates it once and toggles it with open() / close().

signal closed

const StartMenu := preload("res://scripts/start_menu.gd")
const CREEPY_FONT := preload("res://assets/fonts/creepster.woff2")   # Creepster, SIL OFL (see creepster_OFL.txt)
const BLOOD := Color(0.55, 0.02, 0.02)
const BLOOD_HOT := Color(0.9, 0.06, 0.04)

const VIGNETTE := """
shader_type canvas_item;
uniform vec4 edge : source_color = vec4(0.16, 0.0, 0.0, 0.9);
uniform float centre_dim = 0.3;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.8);
	float v = smoothstep(0.15, 0.75, length(d));
	COLOR = vec4(edge.rgb * v, mix(centre_dim, edge.a, v));
}
"""

var _abandon: Button
var _abandon_holder: Control
var _resume: Button
var _t := 0.0


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Dark, blood-tinged vignette; the game stays visible (and running) behind it.
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

	# ABANDON: huge red creepy letters. It sits in a plain holder so it can
	# tremble without the container snapping it back.
	_abandon = Button.new()
	_abandon.text = "ABANDON"
	_abandon.flat = true
	_abandon.focus_mode = Control.FOCUS_ALL
	_abandon.add_theme_font_override("font", CREEPY_FONT)
	_abandon.add_theme_font_size_override("font_size", 140)
	_abandon.add_theme_color_override("font_color", BLOOD)
	_abandon.add_theme_color_override("font_hover_color", BLOOD_HOT)
	_abandon.add_theme_color_override("font_focus_color", BLOOD_HOT)
	_abandon.add_theme_color_override("font_pressed_color", Color(0.35, 0.0, 0.0))
	_abandon.add_theme_color_override("font_outline_color", Color(0.02, 0.0, 0.0))
	_abandon.add_theme_constant_override("outline_size", 14)
	_abandon.tooltip_text = "Leave the round and return to the main menu."
	_abandon.pressed.connect(_on_abandon)
	_abandon_holder = Control.new()
	_abandon_holder.add_child(_abandon)
	box.add_child(_abandon_holder)

	var whisper := StartMenu._label("Leave them to the wolf...", 20, Color(0.62, 0.5, 0.48))
	box.add_child(whisper)
	box.add_child(StartMenu._gap(28))

	_resume = StartMenu._button("Resume", true)
	_resume.pressed.connect(close)
	box.add_child(_resume)
	var quit := StartMenu._button("Quit game", true)
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	_size_abandon.call_deferred()


func _size_abandon() -> void:
	var s := _abandon.get_combined_minimum_size()
	_abandon.size = s
	_abandon_holder.custom_minimum_size = s


func open() -> void:
	visible = true
	_resume.grab_focus.call_deferred()          # Enter = Resume, never an accidental abandon


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# Uneasy tremble + a faint pulse, a little stronger when hovered.
	var hot := _abandon.is_hovered() or _abandon.has_focus()
	var amp := 2.2 if hot else 1.0
	if fmod(_t, 0.06) < delta:
		_abandon.position = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	_abandon.modulate.a = 0.86 + 0.14 * sin(_t * 2.3) * sin(_t * 0.7 + 1.0)


func _on_abandon() -> void:
	# Back to the main menu: the scene restarts and shows the start menu.
	get_tree().paused = false
	get_tree().reload_current_scene()
