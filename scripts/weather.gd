extends Node
## Weather for one round. For now: clear or rain.
##
## The round is split into "spells" of clear weather and rain with random
## lengths. The spells come from the map seed, so every player in a multiplayer
## match gets the same weather at the same time (only the seed and the round
## time need to be shared). Rain fades in and out over fade_time seconds.
## main.gd creates this, starts it with the round and reads `rain` (0..1) every
## frame to drive the rain effect (scripts/rain.gd), the tint, wind, footprints
## and how far the werewolf's steps carry.

signal rain_started
signal rain_stopped

var enabled := true
var rain_chance := 0.5                     # chance that each spell is rain
var clear_spell := Vector2(60.0, 180.0)    # seconds (min, max) of a clear spell
var rain_spell := Vector2(45.0, 120.0)     # seconds (min, max) of a rain spell
var fade_time := 10.0                      # seconds for rain to fade fully in/out

var running := false
var time := 0.0
## Current rain strength, faded: 0 = dry .. 1 = full rain.
var rain := 0.0
## Whether it is raining right now (the target the fade moves towards).
var raining := false

var _spells := []                          # [[start_time, is_rain], ...]
var _override := -1                        # debug toggle: -1 none, 0 dry, 1 rain (until the next spell)
var _spell_index := -1


## Builds the weather schedule for this round from the map seed.
func setup(map_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_seed * 7919 + 13)
	_spells.clear()
	var t := 0.0
	while t < 4.0 * 3600.0:                # plenty for any round
		var wet := rng.randf() < rain_chance
		_spells.append([t, wet])
		var r: Vector2 = rain_spell if wet else clear_spell
		t += rng.randf_range(r.x, maxf(r.y, r.x))
	_spell_index = -1


func start() -> void:
	running = true


## Debug: flip rain on/off now (lasts until the next scheduled change).
func toggle() -> void:
	_override = 0 if raining else 1


## Force rain on (true) or off (false) now, until the next scheduled change.
func force(rain_on: bool) -> void:
	_override = 1 if rain_on else 0


func _process(delta: float) -> void:
	if running:
		time += delta
	var idx := _spell_at(time)
	if idx != _spell_index:
		_spell_index = idx
		_override = -1
	var want := false
	if enabled and running:
		want = _spells[idx][1] if idx >= 0 else false
		if _override >= 0:
			want = _override == 1
	if want != raining:
		raining = want
		if raining:
			rain_started.emit()
		else:
			rain_stopped.emit()
	rain = move_toward(rain, 1.0 if raining else 0.0, delta / maxf(fade_time, 0.01))


func _spell_at(t: float) -> int:
	var idx := -1
	for i in _spells.size():
		if _spells[i][0] <= t:
			idx = i
		else:
			break
	return idx
