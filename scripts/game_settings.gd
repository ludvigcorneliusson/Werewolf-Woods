extends RefCounted
## Player settings chosen in the main menu (Settings screen).
## Static, so they survive scene reloads (every new round reloads main.tscn),
## and saved to user://settings.cfg so they are remembered between launches.
## Use via a preload: const GameSettings := preload("res://scripts/game_settings.gd")

const PATH := "user://settings.cfg"

## Map size name -> ground tiles per side (one ground tile = 105 x 107 px).
const MAP_SIZES := {"Small": 62, "Medium": 100, "Large": 150}
## Difficulty name -> AI werewolf speed multiplier (walk and sprint).
## For reference: the settler sprints at 200, the werewolf at 215 on Normal.
const DIFFICULTIES := {"Easy": 0.85, "Normal": 1.0, "Hard": 1.12, "Nightmare": 1.25}

static var map_size := "Medium"
static var map_seed := 67
static var random_seed := true      # roll a new seed every round
static var fullscreen := true
static var difficulty := "Normal"
static var volume := 0.8            # master volume 0..1
static var music_volume := 0.6      # music volume 0..1 (the "Music" bus, scripts/music.gd)

## Advanced settings (Esc menu > Advanced settings): "main.<property>" or
## "builder.<property>" -> value. Re-applied by main.gd every round.
static var advanced := {}
## Set before restarting the round from "Regenerate map": skip the start menu
## and play this side straight away.
static var restart_role := ""

static var _loaded := false
static var _keep_seed_once := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	map_size = cf.get_value("map", "size", map_size)
	map_seed = cf.get_value("map", "seed", map_seed)
	random_seed = cf.get_value("map", "random_seed", random_seed)
	fullscreen = cf.get_value("display", "fullscreen", fullscreen)
	difficulty = cf.get_value("game", "difficulty", difficulty)
	volume = cf.get_value("audio", "volume", volume)
	music_volume = cf.get_value("audio", "music_volume", music_volume)
	if cf.has_section("advanced"):
		for k in cf.get_section_keys("advanced"):
			advanced[k] = cf.get_value("advanced", k)
	if not MAP_SIZES.has(map_size):
		map_size = "Medium"
	if not DIFFICULTIES.has(difficulty):
		difficulty = "Normal"


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("map", "size", map_size)
	cf.set_value("map", "seed", map_seed)
	cf.set_value("map", "random_seed", random_seed)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("game", "difficulty", difficulty)
	cf.set_value("audio", "volume", volume)
	cf.set_value("audio", "music_volume", music_volume)
	for k in advanced:
		cf.set_value("advanced", k, advanced[k])
	cf.save(PATH)


static func map_tiles() -> int:
	return MAP_SIZES.get(map_size, 80)


static func werewolf_speed_scale() -> float:
	return DIFFICULTIES.get(difficulty, 1.0)


static func randomize_seed() -> void:
	map_seed = randi() % 1000000


## Called at the start of every round: new seed if "new seed every round" is on,
## unless the round was restarted to show a seed the player just picked.
static func next_round_seed() -> void:
	if _keep_seed_once:
		_keep_seed_once = false
	elif random_seed:
		randomize_seed()


## The next round keeps the current seed (used after changing map settings).
static func keep_seed_for_next_round() -> void:
	_keep_seed_once = true


static func apply_display(window: Window) -> void:
	var is_full := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	if fullscreen and not is_full:
		window.mode = Window.MODE_FULLSCREEN
	elif not fullscreen and is_full:
		window.mode = Window.MODE_WINDOWED
		window.size = Vector2i(1280, 720)
		window.move_to_center()


static func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	preload("res://scripts/music.gd").ensure_bus()
	var mb := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(mb, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(mb, music_volume <= 0.001)
