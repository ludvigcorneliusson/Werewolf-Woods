extends Node
## Experience and levels. Tasks hand out XP with add_xp(amount, source); when
## the bar fills you level up (leveled_up fires once per level, so several
## level-ups in a row each get their own upgrade choice).
##
## XP needed to go from level n to n+1:
##     first_level_xp * n ^ curve        (rounded, at least 1)
## curve = 1 -> straight line   10, 20, 30, 40 ...   (with first_level_xp = 10)
## curve = 0 -> flat            10, 10, 10, 10 ...
## curve = 0.5 -> flattening    10, 14, 17, 20 ...
## curve = 1.5 -> steepening    10, 28, 52, 80 ...
## curve = 2 -> steep           10, 40, 90, 160 ...
## main.gd sets both from its Experience settings.

signal xp_changed(xp: int, needed: int, level: int)
signal xp_gained(amount: int, source: String)
signal leveled_up(level: int)

var first_level_xp := 10
var curve := 1.0

var level := 1
var xp := 0                     # XP collected towards the next level


func _init() -> void:
	name = "Experience"


## XP needed to go from `lvl` to lvl + 1.
func needed_for(lvl: int) -> int:
	return maxi(1, roundi(first_level_xp * pow(float(lvl), curve)))


func needed() -> int:
	return needed_for(level)


func add_xp(amount: int, source := "") -> void:
	if amount <= 0:
		return
	xp += amount
	xp_gained.emit(amount, source)
	while xp >= needed():
		xp -= needed()
		level += 1
		leveled_up.emit(level)
	xp_changed.emit(xp, needed(), level)


## The first few requirements, e.g. for a settings tooltip: "10, 20, 30, 40, 50".
func preview(count := 6) -> String:
	var parts: Array[String] = []
	for i in count:
		parts.append(str(needed_for(i + 1)))
	return ", ".join(parts)
