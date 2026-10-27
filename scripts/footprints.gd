extends Node2D
## Footprints: the villager leaves faint marks on the ground every stride
## (alternating left/right foot, turned in the walking direction). Each print
## stays at full strength for a while, then fades away. Drawn just above the
## ground and below props, characters and the night darkness.
## Created by main.gd, which sets the Footprints settings.

var walker: Node2D                 # who leaves the prints (the villager)
var enabled := true
var step_distance := 13.0          # world px between prints when walking
var sprint_step_scale := 1.4       # longer strides when sprinting
var opacity := 0.22                # how dark a fresh print is (0..1)
var color := Color(0.12, 0.08, 0.04)
var foot_size := Vector2(2.5, 1.6) # half-size of one print (world px)
var foot_spacing := 2.5            # sideways distance of each foot from the walk line
var lifetime := 25.0               # seconds until a print is gone
var fade_start := 0.4              # fraction of the lifetime before fading begins
var max_prints := 600

var _prints := []                  # [position, angle, age]
var _last := Vector2.INF
var _left := true


func _ready() -> void:
	z_index = -9                   # above the ground (-10), below darkness (-5) and props (0)


func _process(delta: float) -> void:
	# Age and drop old prints.
	var keep := []
	for p in _prints:
		p[2] += delta
		if p[2] < lifetime:
			keep.append(p)
	_prints = keep

	if enabled and is_instance_valid(walker):
		var pos := walker.global_position
		if _last == Vector2.INF:
			_last = pos
		var moved := pos - _last
		var sprinting: bool = walker.get("_speed") != null and walker.get("sprint_speed") != null \
				and walker._speed >= walker.sprint_speed - 1.0
		var step := step_distance * (sprint_step_scale if sprinting else 1.0)
		if moved.length() >= step:
			var dir := moved.normalized()
			var side := Vector2(-dir.y, dir.x) * (foot_spacing if _left else -foot_spacing)
			_prints.append([pos + side, dir.angle(), 0.0])
			_left = not _left
			_last = pos
			if _prints.size() > max_prints:
				_prints.pop_front()
		elif moved.length() > step * 4.0:
			_last = pos                # teleported: don't draw a print across the gap
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var fade_from := lifetime * clampf(fade_start, 0.0, 0.99)
	for p in _prints:
		var age: float = p[2]
		var a := opacity
		if age > fade_from:
			a *= 1.0 - smoothstep(fade_from, lifetime, age)
		if a <= 0.003:
			continue
		draw_set_transform(p[0], p[1], Vector2.ONE)
		draw_colored_polygon(_oval, Color(color, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _oval := PackedVector2Array()


## Rebuilds the print shape (call after changing foot_size).
func apply() -> void:
	_oval = PackedVector2Array()
	for i in 8:
		var t := TAU * i / 8.0
		_oval.append(Vector2(cos(t) * foot_size.x, sin(t) * foot_size.y))


func clear() -> void:
	_prints.clear()
	_last = Vector2.INF
