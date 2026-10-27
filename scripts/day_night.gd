extends Node
## Day -> dusk -> night clock for one round.
##
## The round starts in daylight (settlers scatter and pick a spot). After
## day_length seconds dusk begins and the light fades over dusk_length seconds
## into full night, which then lasts for the rest of the round.
## main.gd creates this, starts it when the round begins, reads `night` every
## frame to drive the look (tint, darkness, campfire) and listens to the
## signals (e.g. the werewolf spawns at dusk).

signal dusk_started
signal night_fell

enum Phase { DAY, DUSK, NIGHT }

var day_length := 45.0             # seconds of daylight at the start
var dusk_length := 20.0            # seconds for the light to fade into night

var running := false
var time := 0.0                    # seconds since the round started
var phase := Phase.DAY
## 0 = full daylight, 1 = full night (0..1 during dusk).
var night := 0.0


func start() -> void:
	running = true
	_update()


## Debug: jump to the start of the next phase.
func skip() -> void:
	match phase:
		Phase.DAY:
			time = day_length
		Phase.DUSK:
			time = day_length + dusk_length
	_update()


func _process(delta: float) -> void:
	if not running:
		return
	time += delta
	_update()


func _update() -> void:
	night = clampf((time - day_length) / maxf(dusk_length, 0.01), 0.0, 1.0)
	var p := Phase.DAY
	if time >= day_length + dusk_length:
		p = Phase.NIGHT
	elif time >= day_length:
		p = Phase.DUSK
	# Step through the phases in order so no signal is missed (e.g. skipping).
	while phase < p:
		phase = phase + 1 as Phase
		if phase == Phase.DUSK:
			dusk_started.emit()
		elif phase == Phase.NIGHT:
			night_fell.emit()


func phase_name() -> String:
	return ["Day", "Dusk", "Night"][phase]
