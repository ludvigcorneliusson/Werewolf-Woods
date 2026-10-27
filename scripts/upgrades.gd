extends RefCounted
## Upgrades offered on level-up (scripts/level_up.gd shows up to three as cards).
## Each one has a name, icon, a description for its next level and a maximum
## level; how strong each level is comes from main.gd's Experience settings
## (passed in as `per_level`). Add an entry here (and its effect in main.gd's
## _apply_upgrades) to add an upgrade to the pool.

const ALL := {
	"chop_speed": {"name": "Swift Axe", "icon": preload("res://assets/ui/up_chop_speed.png"),
			"desc": "Chop %d%% faster", "max": 5},
	"run_speed": {"name": "Light Boots", "icon": preload("res://assets/ui/up_run_speed.png"),
			"desc": "Walk and sprint %d%% faster", "max": 5},
	"axe_damage": {"name": "Heavy Blade", "icon": preload("res://assets/ui/up_axe_damage.png"),
			"desc": "Trees fall %s", "max": 6},
}


## Rarity of an offered card. "power" = how many normal levels' worth of effect
## it gives (main.gd sets rare/epic power and the odds from its settings).
const RARITIES := {
	"common": {"name": "Common", "color": Color(0.45, 0.85, 0.42)},
	"rare": {"name": "Rare", "color": Color(0.36, 0.62, 0.98)},
	"epic": {"name": "Epic", "color": Color(0.74, 0.45, 0.98)},
}


## Rolls a card's rarity: epic_chance first, then rare_chance, else common.
static func roll_rarity(rare_chance: float, epic_chance: float) -> String:
	var r := randf()
	if r < epic_chance:
		return "epic"
	if r < epic_chance + rare_chance:
		return "rare"
	return "common"


## Up to `count` upgrades that aren't maxed yet, in random order.
static func pick(levels: Dictionary, count := 3) -> Array[String]:
	var pool: Array[String] = []
	for id: String in ALL:
		if int(levels.get(id, 0)) < int(ALL[id].max):
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, count)
