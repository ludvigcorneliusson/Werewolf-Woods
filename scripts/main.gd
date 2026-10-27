extends Node2D
## Entry point. Builds the night darkness, the player, the map and a small HUD.
## Everything is created in code so the project has no binary/scene assets yet.

const MapGenerator := preload("res://scripts/map_generator.gd")
const Player := preload("res://scripts/player.gd")
const Darkness := preload("res://scripts/darkness.gd")
const StartMenu := preload("res://scripts/start_menu.gd")
const Werewolf := preload("res://scripts/werewolf.gd")
const Footprints := preload("res://scripts/footprints.gd")
const CHARACTER_MATERIAL := preload("res://assets/characters/character_material.tres")
const PlantPush := preload("res://scripts/plant_push.gd")
const DayNight := preload("res://scripts/day_night.gd")
const GameSettings := preload("res://scripts/game_settings.gd")
const EscapeMenu := preload("res://scripts/escape_menu.gd")
const Weather := preload("res://scripts/weather.gd")
const Rain := preload("res://scripts/rain.gd")
const AdvancedSettings := preload("res://scripts/advanced_settings.gd")
const MusicPlayer := preload("res://scripts/music.gd")
const TreeChopping := preload("res://scripts/tree_chopping.gd")
const Inventory := preload("res://scripts/inventory.gd")
const GameHud := preload("res://scripts/hud.gd")
const Pickups := preload("res://scripts/pickups.gd")
const Experience := preload("res://scripts/experience.gd")
const LevelUp := preload("res://scripts/level_up.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
## Shared by every prop scene; we feed it the player position so trees fade
## when the player walks behind them.
const PROP_MATERIAL := preload("res://assets/props/prop_material.tres")
## Same fade, plus per-prop colour variation (see scripts/varied_prop.gd).
const VARIED_MATERIAL := preload("res://assets/props/varied_material.tres")

## false = use the hand-painted World node in main.tscn (default).
## true  = use the old procedural generator (R makes a new random map).
@export var use_generated_map := false
## Show the start menu (Start -> Human/Werewolf) when the game launches.
@export var show_start_menu := true
## The side the player chose in the start menu ("human" for now).
var player_role := "human"

# --- Camera -------------------------------------------------------------------
@export_group("Camera")
## How close the camera is. 1 = far (1 world px per screen px at 1280x720), 3 = close.
## Whole numbers keep pixel art perfectly even.
@export_range(0.25, 6.0, 0.05) var camera_zoom := 1.0:
	set(v):
		camera_zoom = v
		if player and player.camera:
			player.camera.zoom = Vector2(v, v)
## Allow zooming with the mouse wheel (handy for testing; off for normal play).
## God mode (F) always allows it.
@export var scroll_zoom := false

# --- Footprints ---------------------------------------------------------------
# The villager leaves faint footprints that fade over time.
@export_group("Footprints")
## Leave footprints.
@export var footprints_enabled := true:
	set(v):
		footprints_enabled = v
		_apply_footprints()
## How dark a fresh footprint is (0 = invisible, 1 = solid).
@export_range(0.0, 1.0, 0.01) var footprint_opacity := 0.22:
	set(v):
		footprint_opacity = v
		_apply_footprints()
## Colour of the footprints (darkened soil).
@export var footprint_color := Color(0.12, 0.08, 0.04):
	set(v):
		footprint_color = v
		_apply_footprints()
## Seconds until a footprint has completely faded.
@export_range(1.0, 600.0, 1.0, "suffix:s") var footprint_lifetime := 25.0:
	set(v):
		footprint_lifetime = v
		_apply_footprints()
## When the fading starts, as a fraction of the lifetime (0 = fades from the start).
@export_range(0.0, 0.99, 0.01) var footprint_fade_start := 0.4:
	set(v):
		footprint_fade_start = v
		_apply_footprints()
## Distance between footprints while walking (world px).
@export_range(4.0, 60.0, 0.5, "suffix:px") var footprint_step := 13.0:
	set(v):
		footprint_step = v
		_apply_footprints()
## Longer strides when sprinting (x step distance).
@export_range(1.0, 3.0, 0.05) var footprint_sprint_stride := 1.4:
	set(v):
		footprint_sprint_stride = v
		_apply_footprints()
## Half-size of one footprint (world px).
@export var footprint_size := Vector2(2.5, 1.6):
	set(v):
		footprint_size = v
		_apply_footprints()
## Sideways distance of each foot from the walking line (world px).
@export_range(0.0, 10.0, 0.5, "suffix:px") var footprint_spacing := 2.5:
	set(v):
		footprint_spacing = v
		_apply_footprints()
## Maximum footprints kept at once (oldest disappear first).
@export_range(10, 5000, 10) var footprint_max := 600:
	set(v):
		footprint_max = v
		_apply_footprints()
@export_group("")

var _footprints: Node2D

# --- See-through ----------------------------------------------------------------
# When you stand behind a tree/prop, the part of it covering you turns see-through.
@export_group("See-through")
## Size of the see-through area x your character's body size. 1 = hugs the body.
@export_range(0.5, 4.0, 0.05) var see_through_scale := 1.0
## Soft edge of the see-through area (world px).
@export_range(0.0, 30.0, 0.5, "suffix:px") var see_through_softness := 5.0
## How transparent the covering part gets (0 = invisible, 1 = not see-through).
@export_range(0.0, 1.0, 0.01) var see_through_alpha := 0.35
@export_group("")

# --- Werewolf -----------------------------------------------------------------
@export_group("Werewolf")
## When you play the human: an AI werewolf hunts you.
@export var ai_werewolf := true
## When the AI werewolf appears (see Day & Night for the timing).
@export_enum("Dusk starts", "Night falls") var werewolf_spawns_at := "Dusk starts"
## It spawns at least this far from you.
@export_range(200.0, 5000.0, 10.0, "suffix:px") var werewolf_spawn_distance := 1400.0
## Distance at which it notices you and starts chasing.
@export_range(50.0, 1500.0, 5.0, "suffix:px") var werewolf_sense := 320.0:
	set(v):
		werewolf_sense = v
		_apply_werewolf()
## Distance at which it loses you.
@export_range(100.0, 3000.0, 10.0, "suffix:px") var werewolf_lose := 560.0:
	set(v):
		werewolf_lose = v
		_apply_werewolf()
## Werewolf speeds on Normal (the human walks 120, sprints 200). The menu Difficulty scales the AI werewolf.
@export_range(20.0, 600.0, 5.0) var werewolf_walk_speed := 140.0:
	set(v):
		werewolf_walk_speed = v
		_apply_werewolf()
## Played when the werewolf appears, from the spot where it spawns (so you can
## tell roughly which way it is). When you play the werewolf: at dusk.
@export var werewolf_howl: AudioStream = preload("res://assets/sounds/werewolf_howl.mp3")
## Howl volume.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var howl_volume := 0.0
@export_range(20.0, 800.0, 5.0) var werewolf_sprint_speed := 215.0:
	set(v):
		werewolf_sprint_speed = v
		_apply_werewolf()
@export_group("")

var werewolf: CharacterBody2D

# --- Day & Night --------------------------------------------------------------
# Each round starts in daylight, fades through dusk and stays night. The night
# look itself (darkness, vision, night tint) is set in the Fog group.
@export_group("Day & Night")
## Seconds of daylight at the start of a round (time to scatter and pick a spot).
@export_range(0.0, 600.0, 1.0, "suffix:s") var day_length := 45.0:
	set(v):
		day_length = v
		if _day_night:
			_day_night.day_length = v
## Seconds for the light to fade from day into full night.
@export_range(0.0, 300.0, 1.0, "suffix:s") var dusk_length := 20.0:
	set(v):
		dusk_length = v
		if _day_night:
			_day_night.dusk_length = v
## Colour of the world in daylight (white = unchanged art).
@export var day_tint := Color(1.0, 0.98, 0.94)
## Colour halfway through dusk (the sunset).
@export var dusk_tint := Color(1.0, 0.7, 0.52)
## How bright campfires glow in daylight (1 = full night glow).
@export_range(0.0, 1.0, 0.01) var campfire_day_glow := 0.1
## Debug: start the round at this point (0 = morning; day_length = dusk starts).
@export_range(0.0, 900.0, 1.0, "suffix:s") var start_time := 0.0
@export_group("")

var _day_night: Node

# --- Weather ------------------------------------------------------------------
# Clear and rainy spells for each round, picked from the map seed (the same for
# every player). T toggles rain (debug).
@export_group("Weather")
## Weather changes during the round. Off = always clear.
@export var weather_enabled := true:
	set(v):
		weather_enabled = v
		_apply_weather()
## Chance that each weather spell is rain (0 = never rains, 1 = always).
@export_range(0.0, 1.0, 0.01) var rain_chance := 0.5:
	set(v):
		rain_chance = v
		_apply_weather(true)
## Length of a clear spell, random between min (x) and max (y) seconds.
@export var clear_spell := Vector2(60.0, 180.0):
	set(v):
		clear_spell = v
		_apply_weather(true)
## Length of a rain spell, random between min (x) and max (y) seconds.
@export var rain_spell := Vector2(45.0, 120.0):
	set(v):
		rain_spell = v
		_apply_weather(true)
## Seconds for rain to fade in or out.
@export_range(0.5, 60.0, 0.5, "suffix:s") var rain_fade := 10.0:
	set(v):
		rain_fade = v
		_apply_weather()
## Rain streaks on screen at full rain.
@export_range(50, 4000, 10) var rain_drops := 900:
	set(v):
		rain_drops = v
		_apply_weather()
## Splashes on the ground at full rain.
@export_range(0, 1000, 5) var rain_splashes := 140:
	set(v):
		rain_splashes = v
		_apply_weather()
## Colour and transparency of the rain streaks and splashes.
@export var rain_color := Color(0.8, 0.87, 1.0, 0.7):
	set(v):
		rain_color = v
		_apply_weather()
## How fast drops fall (world px per second).
@export_range(100.0, 2000.0, 10.0) var rain_speed := 650.0:
	set(v):
		rain_speed = v
		_apply_weather()
## Sideways drift of the drops (+ = to the right).
@export_range(-1.0, 1.0, 0.01) var rain_slant := 0.18:
	set(v):
		rain_slant = v
		_apply_weather()
## Rain sound (loops). Any .wav/.ogg/.mp3; the default is a generated placeholder.
@export var rain_sound: AudioStream = preload("res://assets/sounds/weather/rain_loop.wav"):
	set(v):
		rain_sound = v
		_apply_weather()
## Rain sound volume at full rain.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var rain_volume := -8.0:
	set(v):
		rain_volume = v
		_apply_weather()
## Colour the world takes on in full rain (multiplies the day/night tint).
@export var rain_tint := Color(0.66, 0.7, 0.78)
## Extra wind in the trees during rain (1 = double the wind strength).
@export_range(0.0, 5.0, 0.05) var rain_wind_boost := 1.2
## Footprints last this fraction of their normal time in full rain.
@export_range(0.05, 1.0, 0.01) var rain_footprint_life := 0.3
## The AI werewolf's steps carry this fraction of their normal distance in full rain.
@export_range(0.1, 1.0, 0.01) var rain_hearing := 0.6
@export_group("")

var _weather: Node
var _rain: Node2D

# --- Music --------------------------------------------------------------------
# Shuffled ambient playlists (scripts/music.gd): the day list until dusk starts,
# then the night list. Keeps playing across rounds and in the menu. The player's
# own Music volume is in the main menu Settings.
@export_group("Music")
## Play background music.
@export var music_enabled := true:
	set(v):
		music_enabled = v
		_apply_music()
## Tracks for daylight (shuffled). Drag tracks in/out or between the lists.
@export var day_music: Array[AudioStream] = [
	preload("res://assets/music/ambient_07.mp3"), preload("res://assets/music/ambient_01.mp3"),
	preload("res://assets/music/ambient_02.mp3"), preload("res://assets/music/ambient_08.mp3"),
	preload("res://assets/music/ambient_05.mp3")]:
	set(v):
		day_music = v
		_apply_music()
## Tracks from dusk on (shuffled).
@export var night_music: Array[AudioStream] = [
	preload("res://assets/music/ambient_06.mp3"), preload("res://assets/music/ambient_09.mp3"),
	preload("res://assets/music/ambient_03.mp3"), preload("res://assets/music/ambient_04.mp3"),
	preload("res://assets/music/ambient_10.mp3")]:
	set(v):
		night_music = v
		_apply_music()
## Overall music level, under the sound effects (the player's Music slider comes on top).
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_level := -6.0:
	set(v):
		music_level = v
		_apply_music()
## Quiet seconds between tracks, random between min (x) and max (y).
@export var music_gap := Vector2(4.0, 14.0):
	set(v):
		music_gap = v
		_apply_music()
## Seconds for a new track to fade in.
@export_range(0.0, 20.0, 0.5, "suffix:s") var music_fade_in := 4.0:
	set(v):
		music_fade_in = v
		_apply_music()
## Seconds for the day music to fade out when dusk starts.
@export_range(0.5, 30.0, 0.5, "suffix:s") var music_dusk_fade := 6.0:
	set(v):
		music_dusk_fade = v
		_apply_music()
@export_group("")

var _music: Node
var _escape_menu: CanvasLayer
var _advanced_defaults := {}          # "main.prop"/"builder.prop" -> value from main.tscn (for Reset)
var _round_started := false
var _round_label: Label

# --- God mode -----------------------------------------------------------------
# F toggles god mode: no fog, mouse-wheel zoom, walk through everything, fast.
@export_group("God Mode")
## Movement speed multiplier in god mode (Shift still sprints on top).
@export_range(1.0, 20.0, 0.5) var god_speed := 4.0
## Let the camera leave the map edges in god mode.
@export var god_free_camera := true
@export_group("")

# --- Fog of war ---------------------------------------------------------------
# Select the Main node to tweak these in the Inspector. They also update live
# while the game runs (Remote scene tree -> Main), so you can tune by eye.
@export_group("Fog")
## Start with the fog on (F toggles it in game).
@export var fog_enabled := true:
	set(v):
		fog_enabled = v
		_apply_fog()
## Colour of total darkness outside your vision.
@export var fog_color := Color.BLACK:
	set(v):
		fog_color = v
		_apply_fog()
## How dark the fog gets at its thickest. 1 = completely fog_color (black), 0 = no darkness.
@export_range(0.0, 1.0, 0.01) var fog_darkness := 1.0:
	set(v):
		fog_darkness = v
		_apply_fog()
## How far you can see, in world px (the settler is 43 px tall). Beyond this it is fully dark.
@export_range(40.0, 1500.0, 1.0, "suffix:px") var vision_radius := 380.0:
	set(v):
		vision_radius = v
		_apply_fog()
## Where the fade to black begins, as a fraction of vision_radius. 0 = darkens right from your feet, 0.9 = clear until a hard edge.
@export_range(0.0, 0.95, 0.01) var fog_start := 0.3:
	set(v):
		fog_start = v
		_apply_fog()
## Fog thickness: how quickly it goes dark once it starts. 1 = even fade, higher = thicker (darkens sooner), lower = thinner.
@export_range(0.2, 6.0, 0.05) var fog_density := 1.5:
	set(v):
		fog_density = v
		_apply_fog()
## Brightness of what you can see (1 = normal).
@export_range(0.0, 2.0, 0.05) var vision_brightness := 1.0:
	set(v):
		vision_brightness = v
		_apply_fog()
## Tint of your vision (slightly cold moonlight by default).
@export var vision_tint := Color(0.9, 0.95, 1.0):
	set(v):
		vision_tint = v
		_apply_fog()
## Height / width of the vision area. Below 1 makes it look round on the tilted 3/4 ground.
@export_range(0.3, 1.0, 0.01) var vision_squash := 0.78:
	set(v):
		vision_squash = v
		_apply_fog()
## Size of the light cells (world px). Smaller = finer light (recalculation costs more).
@export_range(6, 48, 1, "suffix:px") var light_cell_size := 16:
	set(v):
		light_cell_size = v
		_rebuild_darkness()
## How much tree trunks block light (casts shadows behind them). 0 = not at all.
@export_range(0.0, 1.5, 0.01) var trunk_shade := 1.0:
	set(v):
		trunk_shade = v
		_rebuild_darkness()
## How much tree canopies dim the light passing under them (darker forest). 0 = not at all.
@export_range(0.0, 3.0, 0.01) var canopy_shade := 1.0:
	set(v):
		canopy_shade = v
		_rebuild_darkness()
## How much bushes, rocks and logs block light. 0 = not at all.
@export_range(0.0, 3.0, 0.01) var prop_shade := 1.0:
	set(v):
		prop_shade = v
		_rebuild_darkness()
## How dark the side of a tree/prop facing away from your light gets. 0 = off.
@export_range(0.0, 0.9, 0.01) var prop_side_shade := 0.55:
	set(v):
		prop_side_shade = v
		_apply_fog()
## How much darker a tree/prop looks when you stand behind it (lit from the back). 0 = off.
@export_range(0.0, 0.9, 0.01) var prop_back_shade := 0.3:
	set(v):
		prop_back_shade = v
		_apply_fog()
## How much the square cells are blended. 1 = visible squares, 2-4 = soft.
@export_range(1, 4, 1) var cell_softness := 2:
	set(v):
		cell_softness = v
		_apply_fog()

# --- Wind ---------------------------------------------------------------------
# Trees and plants bend like a hinge at their base on a plain sine wave. Each
# prop scene has its own "Sway" (0 = rigid) on its root, e.g. assets/props/pine_tall.tscn.
@export_group("Wind")
## Turn all swaying on/off.
@export var wind_enabled := true:
	set(v):
		wind_enabled = v
		_apply_wind()
## How far the top of a tree swings to each side (world px; the settler is 43 px tall).
@export_range(0.0, 30.0, 0.1, "suffix:px") var wind_strength := 3.0:
	set(v):
		wind_strength = v
		_apply_wind()
## Swings per second.
@export_range(0.0, 3.0, 0.01, "suffix:Hz") var wind_speed := 0.4:
	set(v):
		wind_speed = v
		_apply_wind()
## Constant lean in the wind direction (world px at the top). 0 = swings evenly both ways.
@export_range(0.0, 30.0, 0.1, "suffix:px") var wind_lean := 1.0:
	set(v):
		wind_lean = v
		_apply_wind()
## Distance between trees that swing in sync. Smaller = neighbours more out of step;
## very large = the whole forest moves together.
@export_range(50.0, 20000.0, 10.0, "suffix:px") var wave_length := 500.0:
	set(v):
		wave_length = v
		_apply_wind()
## Direction the wind blows (screen space; x > 0 = to the right).
@export var wind_direction := Vector2(1.0, 0.25):
	set(v):
		wind_direction = v
		_apply_wind()

# --- Chopping -----------------------------------------------------------------
# Left click swings the axe (sideways: right, or left when you last faced left).
# Hits on a tree trunk wear it down; it falls and leaves a stump.
@export_group("Chopping")
## Hits to fell a living pine.
@export_range(1, 20, 1) var tree_hits := 7:
	set(v):
		tree_hits = v
		_apply_chopping()
## Hits to fell a dead tree.
@export_range(1, 20, 1) var dead_tree_hits := 2:
	set(v):
		dead_tree_hits = v
		_apply_chopping()
## Hits to chop out a stump (it drops a log and twigs).
@export_range(1, 20, 1) var stump_hits := 3:
	set(v):
		stump_hits = v
		_apply_chopping()
## Swing speed (1 = normal, 1.5 = faster).
@export_range(0.3, 3.0, 0.05) var chop_speed := 1.0:
	set(v):
		chop_speed = v
		_apply_chopping()
## Chop and falling-tree volume (dB).
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var chop_volume := -4.0:
	set(v):
		chop_volume = v
		_apply_chopping()
@export_group("")

var _chopping: Node

# --- Survival -------------------------------------------------------------------
# Health (werewolf bites take it off; at 0 the round is lost), the backpack and
# picking things up (E). The HUD shows health, the tools bar (1-4) and the
# backpack (Tab / I).
@export_group("Survival")
## Full health.
@export_range(1.0, 1000.0, 1.0) var max_health := 100.0
## Health one werewolf bite takes.
@export_range(0.0, 1000.0, 1.0) var werewolf_damage := 34.0
## Seconds between werewolf bites while it's on you.
@export_range(0.2, 10.0, 0.05, "suffix:s") var werewolf_bite_interval := 1.2
## How hard a bite knocks you away (world px/s).
@export_range(0.0, 2000.0, 10.0) var bite_knockback := 420.0
## Health back per second once you haven't been hurt for a while (0 = none).
@export_range(0.0, 50.0, 0.1) var health_regen := 0.5
## Seconds without being hurt before health starts coming back.
@export_range(0.0, 120.0, 0.5, "suffix:s") var regen_delay := 8.0
## Backpack slots.
@export_range(1, 30, 1) var inventory_slots := 6
## Seconds a dropped item (logs and twigs from trees) stays on the ground before
## it disappears. 0 = never. Stones and sticks of the map never vanish.
@export_range(0.0, 600.0, 1.0, "suffix:s") var drop_lifetime := 30.0
## How close you must be to pick something up (world px).
@export_range(8.0, 120.0, 1.0, "suffix:px") var pickup_reach := 30.0
@export_group("")

# --- Experience -------------------------------------------------------------------
# Tasks give XP; a full bar = level up: the game pauses and you pick one of
# three upgrades. XP needed for level n -> n+1 = First Level XP x n ^ XP Curve:
#   curve 1 = linear (10, 20, 30, 40 ...), 0 = flat (10, 10, 10 ...),
#   0.5 = flattening (10, 14, 17, 20 ...), 2 = steep (10, 40, 90, 160 ...).
@export_group("Experience")
## XP needed for the first level-up (level 1 -> 2).
@export_range(1, 1000, 1) var xp_first_level := 10:
	set(v):
		xp_first_level = v
		_apply_experience()
## How the requirement grows per level: 1 = linear, below 1 flatter, above 1 steeper (0 = same every level).
@export_range(0.0, 3.0, 0.05) var xp_curve := 1.3:
	set(v):
		xp_curve = v
		_apply_experience()
## XP for felling a big pine.
@export_range(0, 100, 1) var xp_tall_pine := 4
## XP for felling a small dark pine.
@export_range(0, 100, 1) var xp_small_pine := 2
## XP for felling a dead tree.
@export_range(0, 100, 1) var xp_dead_tree := 3
## Upgrades offered per level-up.
@export_range(1, 3, 1) var upgrade_choices := 3
## Swift Axe: chopping speed per level (0.1 = +10%).
@export_range(0.0, 2.0, 0.01) var chop_speed_per_level := 0.1
## Light Boots: walk and sprint speed per level (0.05 = +5%).
@export_range(0.0, 1.0, 0.01) var run_speed_per_level := 0.05
## Heavy Blade: hits fewer to fell a tree (and chop out a stump) per level. Never below 1 hit.
@export_range(0, 5, 1) var hits_saved_per_level := 1
## Chance that an offered card is Rare (blue).
@export_range(0.0, 1.0, 0.01) var rare_chance := 0.25
## Chance that an offered card is Epic (purple).
@export_range(0.0, 1.0, 0.01) var epic_chance := 0.05
## A Rare card counts as this many normal levels of its upgrade.
@export_range(1.0, 10.0, 0.1) var rare_power := 2.0
## An Epic card counts as this many normal levels of its upgrade.
@export_range(1.0, 10.0, 0.1) var epic_power := 3.0
## XP for chopping out a stump.
@export_range(0, 100, 1) var xp_stump := 1
@export_group("")

var _xp: Node
var _level_up: CanvasLayer
var upgrade_levels := {}            # upgrade id -> cards taken (counts towards its max level)
var upgrade_power := {}             # upgrade id -> summed effect (common 1, rare 2, epic 3 ...)
var _offered := {}                  # upgrade id -> rarity of the card on screen
var _pending_levels := 0

var health := 100.0
var _since_hurt := 999.0
var _inventory: Node
var _game_hud: CanvasLayer
var _pickups: Node
var _dead := false

# --- Idle ---------------------------------------------------------------------
# The settler breathes and sways slightly while standing still.
@export_group("Idle")
## Breathing/sway while standing still.
@export var idle_breathing := true:
	set(v):
		idle_breathing = v
		_apply_idle()
## How far the top of his head rises per breath (world px; he is 43 px tall).
@export_range(0.0, 6.0, 0.1, "suffix:px") var breath_amount := 1.0:
	set(v):
		breath_amount = v
		_apply_idle()
## Breaths per second.
@export_range(0.05, 2.0, 0.01, "suffix:Hz") var breath_speed := 0.35:
	set(v):
		breath_speed = v
		_apply_idle()
## Slight sideways drift of his upper body (world px at the top of his head). 0 = none.
@export_range(0.0, 4.0, 0.1, "suffix:px") var idle_sway := 0.4:
	set(v):
		idle_sway = v
		_apply_idle()
## Sideways drift cycles per second.
@export_range(0.02, 1.0, 0.01, "suffix:Hz") var idle_sway_speed := 0.18:
	set(v):
		idle_sway_speed = v
		_apply_idle()

# --- Footsteps ----------------------------------------------------------------
# One grass footstep sound, synced to the run animations: it plays more often
# when sprinting, but always at the same pitch.
@export_group("Footsteps")
## Play footstep sounds.
@export var footsteps_enabled := true:
	set(v):
		footsteps_enabled = v
		_apply_footsteps()
## The settler's footstep sound (drag any .wav/.ogg/.mp3 here). Empty = default grass step.
##@export var settler_step_sound: AudioStream = preload("res://assets/sounds/footsteps/grass_step.wav"):
##	set(v):
##		settler_step_sound = v
		_apply_footsteps()
## The werewolf's footstep sound. Empty = default grass step.
##@export var werewolf_step_sound: AudioStream = preload("res://assets/sounds/footsteps/grass_step.wav"):
##	set(v):
##		werewolf_step_sound = v
		_apply_footsteps()
## Settler step volume.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var settler_step_volume := -6.0:
	set(v):
		settler_step_volume = v
		_apply_footsteps()
## Werewolf step volume.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var werewolf_step_volume := -3.0:
	set(v):
		werewolf_step_volume = v
		_apply_footsteps()
## How far away you can hear the AI werewolf's steps.
@export_range(100.0, 3000.0, 10.0, "suffix:px") var werewolf_hear_distance := 900.0:
	set(v):
		werewolf_hear_distance = v
		_apply_footsteps()
@export_group("")

# --- Plants -------------------------------------------------------------------
# Ferns, grass and mushrooms bend away when you walk through them. Each plant
# scene has its own "Bend" (0 = not pushed) on its root.
@export_group("Plants")
## Plants react to the settler walking through them.
@export var plants_react := true:
	set(v):
		plants_react = v
		_apply_plants()
## How far plants lean at walking speed (radians, x the plant's Bend). Sprinting pushes harder.
@export_range(0.0, 1.5, 0.01) var push_strength := 0.45:
	set(v):
		push_strength = v
		_apply_plants()
## How close (from the feet) a plant has to be to get pushed.
@export_range(4.0, 80.0, 1.0, "suffix:px") var push_radius := 20.0:
	set(v):
		push_radius = v
		_apply_plants()
## How hard plants spring back upright. Higher = snappier.
@export_range(10.0, 600.0, 1.0) var spring_back := 140.0:
	set(v):
		spring_back = v
		_apply_plants()
## Higher = less wobble after you pass.
@export_range(0.0, 40.0, 0.5) var wobble_damping := 7.0:
	set(v):
		wobble_damping = v
		_apply_plants()
@export_group("")

var map: Node2D
var world: Node2D
var player: CharacterBody2D
var darkness: CanvasModulate     # only tints the scene now (vision colour/brightness)
var _dark: Node2D             # the organic darkness overlay
var seed_value := 0

var _hud_label: Label
var _god_label: Label
var god_mode := false
var _saved_fog := true
var _saved_limits := []
var _plant_push: Node


func _ready() -> void:
	_setup_input()
	GameSettings.load_settings()
	GameSettings.apply_display(get_window())
	GameSettings.apply_volume()
	_apply_advanced_overrides()
	_setup_music()

	# Night: an organic darkness overlay with holes around the player and fires.
	darkness = CanvasModulate.new()
	add_child(darkness)
	_dark = Darkness.new()
	add_child(_dark)

	_day_night = DayNight.new()
	_day_night.day_length = day_length
	_day_night.dusk_length = dusk_length
	_day_night.time = start_time
	_day_night.dusk_started.connect(_on_dusk)
	_day_night.night_fell.connect(_on_night)
	add_child(_day_night)
	_weather = Weather.new()
	add_child(_weather)

	player = Player.new()
	add_child(player)
	_dark.player = player
	_dark.camera = player.camera
	_apply_fog()

	_build_hud()
	_generate_world()
	_rain = Rain.new()
	add_child(_rain)
	_apply_weather(true)
	world = get_node_or_null("World")
	if use_generated_map or world == null:
		if world:
			world.queue_free()
		_new_map(MapGenerator.DEFAULT_SEED)
	else:
		_setup_painted_world()
	_apply_wind()
	_apply_idle()
	_apply_footsteps()
	_chopping = TreeChopping.new()
	_chopping.player = player
	add_child(_chopping)
	if player.has_signal("chop_hit"):
		player.connect("chop_hit", _chopping.on_chop_hit)
	_chopping.tree_felled.connect(_on_tree_felled)
	_apply_chopping()
	_setup_survival()
	_footprints = Footprints.new()
	add_child(_footprints)
	_footprints.walker = player
	_apply_footprints()
	_rebuild_darkness.call_deferred()
	if GameSettings.restart_role != "":
		# Restarted from "Regenerate map": straight back into the round.
		var role := GameSettings.restart_role
		GameSettings.restart_role = ""
		_on_role_chosen.call_deferred(role)
	elif show_start_menu:
		var menu := StartMenu.new()
		add_child(menu)
		menu.chosen.connect(_on_role_chosen)
		menu.map_changed.connect(_on_map_settings_changed)
		get_tree().paused = true                # the forest shows behind the menu, frozen
	else:
		_day_night.start()
		_weather.start()
		_round_started = true
	_plant_push = PlantPush.new()
	_plant_push.player = player
	_plant_push.props = world.get_node_or_null("Props") if is_instance_valid(world) else null
	_plant_push.placed = world.get_node_or_null("Placed") if is_instance_valid(world) else null
	_plant_push.walk_speed = Player.WALK_SPEED
	add_child(_plant_push)
	_apply_plants()


func _process(_delta: float) -> void:
	if _music and _day_night:
		# Night music from the moment dusk starts (when the werewolf comes out).
		_music.set_mood("day" if _day_night.phase == DayNight.Phase.DAY else "night")
	_apply_sky()
	_apply_rain_effects()
	_update_health(_delta)
	if map:
		map.set_player_position(player.global_position)
	else:
		PROP_MATERIAL.set_shader_parameter("player_pos", player.global_position)
		VARIED_MATERIAL.set_shader_parameter("player_pos", player.global_position)
		VARIED_MATERIAL.set_shader_parameter("fade_size", player.see_through_size * see_through_scale)
		VARIED_MATERIAL.set_shader_parameter("fade_softness", see_through_softness)
		VARIED_MATERIAL.set_shader_parameter("faded_alpha", see_through_alpha)
		CHARACTER_MATERIAL.set_shader_parameter("player_pos", player.global_position)


## Pushes the Wind settings to the shared prop shader.
func _apply_wind() -> void:
	var m := VARIED_MATERIAL
	m.set_shader_parameter("wind_strength", wind_strength if wind_enabled else 0.0)
	m.set_shader_parameter("wind_lean", wind_lean if wind_enabled else 0.0)
	m.set_shader_parameter("wind_speed", wind_speed)
	m.set_shader_parameter("wave_spread", 1.0 / maxf(wave_length, 1.0))
	m.set_shader_parameter("wind_dir", wind_direction if wind_direction != Vector2.ZERO else Vector2.RIGHT)


func _apply_footprints() -> void:
	if _footprints == null:
		return
	_footprints.enabled = footprints_enabled
	_footprints.opacity = footprint_opacity
	_footprints.color = footprint_color
	_footprints.lifetime = footprint_lifetime
	_footprints.fade_start = footprint_fade_start
	_footprints.step_distance = footprint_step
	_footprints.sprint_step_scale = footprint_sprint_stride
	_footprints.foot_size = footprint_size
	_footprints.foot_spacing = footprint_spacing
	_footprints.max_prints = footprint_max
	_footprints.apply()


func _apply_idle() -> void:
	if player == null:
		return
	player.idle_enabled = idle_breathing
	player.breath_amount = breath_amount
	player.breath_speed = breath_speed
	player.idle_sway = idle_sway
	player.idle_sway_speed = idle_sway_speed


func _apply_footsteps() -> void:
	for c in [player, werewolf]:
		if not is_instance_valid(c):
			continue
		var wolf: bool = c.get_script() == Werewolf
		c.footsteps_enabled = footsteps_enabled
		c.step_volume_db = werewolf_step_volume if wolf else settler_step_volume
##		c.set_step_sound(werewolf_step_sound if wolf else settler_step_sound)
		if wolf:
			c.step_hear_distance = werewolf_hear_distance
		c.apply_footsteps()


func _apply_plants() -> void:
	if _plant_push == null:
		return
	_plant_push.set_physics_process(plants_react)
	_plant_push.push_strength = push_strength
	_plant_push.push_radius = push_radius
	_plant_push.spring = spring_back
	_plant_push.damping = wobble_damping


## Pushes the Fog settings to the darkness overlay.
func _apply_fog() -> void:
	if darkness == null or player == null or _dark == null:
		return
	# Scene tint inside the light (the old vision colour/brightness).
	_apply_sky()
	darkness.visible = true
	if player.light:
		player.light.enabled = false            # darkness is drawn by the overlay now
	_dark.visible = fog_enabled
	_dark.vision_radius = vision_radius
	_dark.squash = vision_squash
	_dark.start = fog_start
	_dark.density = fog_density
	_dark.dark_color = fog_color
	_dark.darkness = fog_darkness
	_dark.cell = light_cell_size
	_dark.trunk_absorption = trunk_shade
	_dark.canopy_absorption = canopy_shade
	_dark.prop_absorption = prop_shade
	_dark.smoothness = cell_softness
	_dark.side_shade = prop_side_shade
	_dark.back_shade = prop_back_shade
	_dark.apply(true)


## Day & night look: tint, how dark the night overlay is, campfire glow.
## Cheap; runs every frame (only the darkness amount changes, no relighting).
func _apply_sky() -> void:
	if darkness == null or _dark == null or _day_night == null:
		return
	var n: float = _day_night.night
	var night_tint := vision_tint * vision_brightness
	var tint := day_tint.lerp(dusk_tint, n * 2.0) if n < 0.5 else dusk_tint.lerp(night_tint, (n - 0.5) * 2.0)
	if _weather:
		tint = tint.lerp(tint * rain_tint, _weather.rain)            # greyer, darker in rain
	darkness.color = tint if fog_enabled else Color.WHITE
	# Darkness creeps in after the sunset has started; full at nightfall.
	_dark.set_night(smoothstep(0.15, 1.0, n))
	for f in get_tree().get_nodes_in_group("light_sources"):
		if f.get("glow_scale") != null:
			f.glow_scale = lerpf(campfire_day_glow, 1.0, smoothstep(0.0, 0.7, n))


## Pushes the Weather settings to the weather clock and the rain effect
## (reschedule = the spell settings changed, so rebuild this round's schedule).
func _apply_weather(reschedule := false) -> void:
	if _weather == null:
		return
	_weather.enabled = weather_enabled
	_weather.fade_time = rain_fade
	_weather.rain_chance = rain_chance
	_weather.clear_spell = clear_spell
	_weather.rain_spell = rain_spell
	if reschedule:
		_weather.setup(GameSettings.map_seed)
	if _rain:
		_rain.drops = rain_drops
		_rain.splashes = rain_splashes
		_rain.color = rain_color
		_rain.fall_speed = rain_speed
		_rain.slant = rain_slant
		_rain.sound = rain_sound
		_rain.volume_db = rain_volume
		_rain.apply()


## Every frame: rain strength -> rain effect, wind, footprints, hearing.
func _apply_rain_effects() -> void:
	if _weather == null or _rain == null:
		return
	var r: float = _weather.rain
	_rain.camera = player.camera if is_instance_valid(player) else null
	_rain.intensity = r
	var w := (wind_strength if wind_enabled else 0.0) * (1.0 + rain_wind_boost * r)
	VARIED_MATERIAL.set_shader_parameter("wind_strength", w)
	if _footprints:
		_footprints.lifetime = footprint_lifetime * lerpf(1.0, rain_footprint_life, r)
	if is_instance_valid(werewolf) and werewolf != player:
		werewolf.step_hear_distance = werewolf_hear_distance * lerpf(1.0, rain_hearing, r)
		werewolf.apply_footsteps()


func _on_dusk() -> void:
	if werewolf_spawns_at == "Dusk starts" and player_role == "human" and ai_werewolf:
		_spawn_ai_werewolf()            # shows its own message
	else:
		if player_role == "werewolf":
			_howl(player.global_position)   # you are the werewolf: your own howl at dusk
		_flash("Dusk is falling...", 3.0)


## The werewolf's howl, heard from where it is (gently panned, a bit quieter
## the further away it is, but always audible).
func _howl(at: Vector2) -> void:
	if werewolf_howl == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = werewolf_howl
	p.volume_db = howl_volume
	p.max_distance = 8000.0
	p.attenuation = 0.6
	p.panning_strength = 0.4
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _on_night() -> void:
	if werewolf_spawns_at == "Night falls" and player_role == "human" and ai_werewolf:
		_spawn_ai_werewolf()
	else:
		_flash("Night has fallen.", 3.0)


## Rebuilds which cells hold tree trunks (from the props) and the campfire light.
func _setup_survival() -> void:
	health = max_health
	_inventory = Inventory.new(inventory_slots)
	add_child(_inventory)
	_game_hud = GameHud.new()
	_game_hud.inventory = _inventory
	add_child(_game_hud)
	_game_hud.tool_selected.connect(func(id: String): if is_instance_valid(player): player.set("held_tool", id))
	_game_hud.set_health(health, max_health)
	_pickups = Pickups.new()
	_pickups.player = player
	_pickups.world = world
	_pickups.inventory = _inventory
	_pickups.hud = _game_hud
	_pickups.reach = pickup_reach
	_pickups.lifetime = drop_lifetime
	add_child(_pickups)
	if _chopping:
		_chopping.pickups = _pickups
		_chopping.tree_cut.connect(_on_tree_cut)
		_chopping.stump_cleared.connect(_on_stump_cleared)
	_xp = Experience.new()
	add_child(_xp)
	_apply_experience()
	_xp.xp_changed.connect(func(x: int, n: int, lvl: int): _game_hud.set_xp(x, n, lvl))
	_xp.leveled_up.connect(_on_level_up)
	_game_hud.set_xp(0, _xp.needed(), 1)
	_level_up = LevelUp.new()
	add_child(_level_up)
	_level_up.chosen.connect(_on_upgrade_chosen)


func _apply_experience() -> void:
	if _xp == null:
		return
	_xp.first_level_xp = xp_first_level
	_xp.curve = xp_curve
	if _game_hud:
		_game_hud.set_xp(_xp.xp, _xp.needed(), _xp.level)


## A tree came down under your axe: experience by tree type.
func _on_tree_cut(tree: Node2D, image: String) -> void:
	var amount := xp_tall_pine
	if image == "pine_dark.png":
		amount = xp_small_pine
	elif image.begins_with("dead"):
		amount = xp_dead_tree
	if amount <= 0 or _xp == null:
		return
	_game_hud.note("+%d XP" % amount, tree.global_position + Vector2(0, -60), Color(0.82, 0.62, 1.0))
	_xp.add_xp(amount, "tree")


## A stump chopped out: a little XP, and light reaches the spot.
func _on_stump_cleared(stump: Node2D) -> void:
	if xp_stump > 0 and _xp:
		_game_hud.note("+%d XP" % xp_stump, stump.global_position + Vector2(0, -30), Color(0.82, 0.62, 1.0))
		_xp.add_xp(xp_stump, "stump")
	_on_tree_felled(stump)


func _on_level_up(_level: int) -> void:
	_pending_levels += 1
	if not _level_up.is_open() and _pending_levels == 1:
		# A short beat so you see the bar fill, then the choice.
		get_tree().create_timer(0.35, false).timeout.connect(_show_level_up)


func _show_level_up() -> void:
	if _pending_levels <= 0 or _dead:
		return
	# Heavy Blade is done once a big pine already falls in one hit.
	var levels := upgrade_levels.duplicate()
	if tree_hits - _hits_saved(float(upgrade_power.get("axe_damage", 0.0))) <= 1:
		levels["axe_damage"] = 999
	var ids := Upgrades.pick(levels, upgrade_choices)
	if ids.is_empty():
		_pending_levels = 0                 # everything maxed: nothing to choose
		return
	var cards := []
	_offered.clear()
	for id in ids:
		var lvl := int(upgrade_levels.get(id, 0))
		var u: Dictionary = Upgrades.ALL[id]
		var rarity := Upgrades.roll_rarity(rare_chance, epic_chance)
		_offered[id] = rarity
		var r: Dictionary = Upgrades.RARITIES[rarity]
		cards.append({"id": id, "name": u.name, "icon": u.icon, "level": lvl,
				"desc": _upgrade_desc(id, _rarity_power(rarity)),
				"rarity": r.name, "color": r.color})
	get_tree().paused = true
	if is_instance_valid(player):
		player.set("_chop_queued", false)
		player.set("_chop_held", false)
	_level_up.show_choices(_xp.level - _pending_levels + 1, cards)


## Hits Heavy Blade takes off, for a summed upgrade power (common 1, rare 2, epic 3).
func _hits_saved(power: float) -> int:
	return roundi(power) * hits_saved_per_level


func _rarity_power(rarity: String) -> float:
	return {"rare": rare_power, "epic": epic_power}.get(rarity, 1.0)


## Card text: what taking this card (worth `power` normal levels) gives.
func _upgrade_desc(id: String, power: float) -> String:
	var u: Dictionary = Upgrades.ALL[id]
	var have := float(upgrade_power.get(id, 0.0))
	match id:
		"chop_speed":
			return u.desc % roundi(chop_speed_per_level * power * 100.0)
		"run_speed":
			return u.desc % roundi(run_speed_per_level * power * 100.0)
		"axe_damage":
			var now := maxi(tree_hits - _hits_saved(have), 1)
			var after := maxi(tree_hits - _hits_saved(have + power), 1)
			return u.desc % ("in %d hits instead of %d" % [after, now])
	return ""


func _on_upgrade_chosen(id: String) -> void:
	upgrade_levels[id] = int(upgrade_levels.get(id, 0)) + 1
	upgrade_power[id] = float(upgrade_power.get(id, 0.0)) + _rarity_power(_offered.get(id, "common"))
	_apply_upgrades()
	_pending_levels -= 1
	if _pending_levels > 0:
		_show_level_up()
	else:
		get_tree().paused = false


## Upgrade effects on top of the base settings.
func _apply_upgrades() -> void:
	var chop_l := float(upgrade_power.get("chop_speed", 0.0))
	var run_l := float(upgrade_power.get("run_speed", 0.0))
	var saved := _hits_saved(float(upgrade_power.get("axe_damage", 0.0)))
	if is_instance_valid(player) and player_role == "human":
		player.set("chop_speed", chop_speed * (1.0 + chop_speed_per_level * chop_l))
		player.set("walk_speed", Player.WALK_SPEED * (1.0 + run_speed_per_level * run_l))
		player.set("sprint_speed", Player.SPRINT_SPEED * (1.0 + run_speed_per_level * run_l))
	if _chopping:
		_chopping.damage = 1.0
		_chopping.hits_saved = saved


## Health back after a while without being hurt.
func _update_health(delta: float) -> void:
	_since_hurt += delta
	if _dead or health >= max_health or health_regen <= 0.0 or _since_hurt < regen_delay:
		return
	var before := ceili(health)
	health = minf(health + health_regen * delta, max_health)
	if ceili(health) != before and _game_hud:
		_game_hud.set_health(health, max_health)


func _apply_chopping() -> void:
	if _chopping:
		_chopping.hits_to_fell = tree_hits
		_chopping.dead_hits_to_fell = dead_tree_hits
		_chopping.stump_hits = stump_hits
		_chopping.volume_db = chop_volume
	if player and "chop_speed" in player:
		player.set("chop_speed", chop_speed)
	_apply_upgrades()


## A tree came down: light now reaches where it stood (once the stump is in).
func _on_tree_felled(_tree: Node2D) -> void:
	get_tree().create_timer(0.15, false).timeout.connect(_rebuild_darkness)


func _rebuild_darkness() -> void:
	if _dark == null or not is_instance_valid(world):
		return
	_apply_fog()
	var props := world.get_node_or_null("Props")
	if props:
		# Generated props, painted props and scenes dragged straight into World.
		_dark.build([props, world.get_node_or_null("Placed"), world], _map_rect())


## Map area = the painted ground.
func _map_rect() -> Rect2:
	var ground := world.get_node_or_null("Ground") as TileMapLayer
	if ground == null or ground.get_used_rect().size == Vector2i.ZERO:
		return Rect2(-2000, -2000, 4000, 4000)
	var c := Vector2(ground.tile_set.tile_size)
	var r := ground.get_used_rect()
	return Rect2(ground.to_global(Vector2(r.position) * c), Vector2(r.size) * c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _round_started:
		_toggle_escape_menu()
		get_viewport().set_input_as_handled()
	elif _escape_menu and _escape_menu.is_open():
		return                              # no game hotkeys while the menu is open
	elif event.is_action_pressed("pickup") and _pickups:
		_pickups.try_pick()
	elif event.is_action_pressed("inventory") and _game_hud and _game_hud.visible:
		_game_hud.toggle_inventory()
	elif _game_hud and _game_hud.visible and _tool_key(event) >= 0:
		_game_hud.select_tool(_tool_key(event))
	elif event.is_action_pressed("regenerate") and map:
		_new_map(randi())
	elif event.is_action_pressed("skip_time"):
		_day_night.skip()
	elif event.is_action_pressed("toggle_rain"):
		_weather.toggle()
	elif event.is_action_pressed("god_mode"):
		_set_god_mode(not god_mode)
	elif event.is_action_pressed("toggle_fullscreen"):
		var w := get_window()
		GameSettings.fullscreen = not (w.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN])
		GameSettings.apply_display(w)
		GameSettings.save_settings()
	elif (scroll_zoom or god_mode) and event is InputEventMouseButton and event.pressed:
		var cam: Camera2D = player.camera
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = (cam.zoom * 1.15).clamp(Vector2(0.12, 0.12), Vector2(6, 6))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = (cam.zoom / 1.15).clamp(Vector2(0.12, 0.12), Vector2(6, 6))


## 0-3 when one of the tool keys (1-4) was pressed, else -1.
func _tool_key(event: InputEvent) -> int:
	for i in 4:
		if event.is_action_pressed("tool_%d" % (i + 1)):
			return i
	return -1


## God mode: no fog, mouse-wheel zoom, no collisions, fast movement, free camera.
## Turning it off restores fog, camera zoom and limits.
# --- Advanced settings (Esc menu) ----------------------------------------------

## Remembers the main.tscn values of every Advanced setting (for Reset), then
## applies the saved changes on top. Runs first in _ready, so everything built
## afterwards uses them.
func _apply_advanced_overrides() -> void:
	var builder := get_node_or_null("WorldBuilder")
	for sec in AdvancedSettings.SECTIONS:
		var target: Object = self if sec[1] == "main" else builder
		if target == null:
			continue
		for prop: String in sec[2]:
			var key: String = sec[1] + "." + prop
			_advanced_defaults[key] = target.get(prop)
			if GameSettings.advanced.has(key):
				target.set(prop, GameSettings.advanced[key])


## Advanced settings > Reset to defaults.
func reset_advanced_settings() -> void:
	var builder := get_node_or_null("WorldBuilder")
	for key: String in _advanced_defaults:
		var parts := key.split(".")
		var target: Object = self if parts[0] == "main" else builder
		if target:
			target.set(parts[1], _advanced_defaults[key])
	GameSettings.advanced.clear()
	GameSettings.save_settings()


## Advanced settings > Regenerate map: new forest, same side, round restarts.
func regenerate_map() -> void:
	GameSettings.save_settings()
	GameSettings.keep_seed_for_next_round()
	GameSettings.restart_role = player_role
	get_tree().reload_current_scene()


## Advanced settings > Rain now / Clear now.
func force_rain(on: bool) -> void:
	if _weather:
		_weather.force(on)


## Advanced settings > Jump to day / dusk / night.
func jump_time(which: String) -> void:
	if _day_night:
		_day_night.jump_to(which)


## Werewolf settings changed: update the AI werewolf that is already out.
func _apply_werewolf() -> void:
	if not is_instance_valid(werewolf) or werewolf == player:
		return
	werewolf.walk_speed = werewolf_walk_speed * GameSettings.werewolf_speed_scale()
	werewolf.sprint_speed = werewolf_sprint_speed * GameSettings.werewolf_speed_scale()
	werewolf.sense_radius = werewolf_sense
	werewolf.lose_radius = werewolf_lose


## The music player lives under the tree root so it survives round restarts:
## reuse it if it's already there, otherwise make it.
func _setup_music() -> void:
	_music = get_tree().root.get_node_or_null("Music")
	if _music == null:
		_music = MusicPlayer.new()
		get_tree().root.add_child.call_deferred(_music)
	_apply_music()


func _apply_music() -> void:
	if _music == null:
		return
	_music.enabled = music_enabled
	_music.day_tracks = day_music
	_music.night_tracks = night_music
	_music.volume_db = music_level
	_music.gap = music_gap
	_music.fade_in = music_fade_in
	_music.mood_fade = music_dusk_fade


## Esc menu: the game keeps running (no pause); your character stands still.
func _toggle_escape_menu() -> void:
	if _escape_menu == null:
		_escape_menu = EscapeMenu.new()
		_escape_menu.main = self
		add_child(_escape_menu)
		_escape_menu.closed.connect(func():
			if is_instance_valid(player):
				player.input_enabled = true)
	if _escape_menu.is_open():
		_escape_menu.close()
	else:
		_escape_menu.open()
		player.input_enabled = false


func _on_role_chosen(role: String) -> void:
	player_role = role
	_round_started = true
	if role == "werewolf":
		_become_werewolf()
	get_tree().paused = false
	_day_night.start()                  # werewolf spawns from _on_dusk / _on_night
	_weather.start()


## Play as the werewolf: swap the settler for a werewolf you control.
func _become_werewolf() -> void:
	var old := player
	var wolf := Werewolf.new()
	wolf.walk_speed = werewolf_walk_speed
	wolf.sprint_speed = werewolf_sprint_speed
	world.add_child(wolf)
	wolf.global_position = old.global_position
	wolf.reset_physics_interpolation()
	var cam: Camera2D = old.camera
	wolf.camera.zoom = cam.zoom
	wolf.camera.limit_left = cam.limit_left
	wolf.camera.limit_top = cam.limit_top
	wolf.camera.limit_right = cam.limit_right
	wolf.camera.limit_bottom = cam.limit_bottom
	wolf.camera.make_current()
	wolf.camera.reset_smoothing()
	old.queue_free()
	player = wolf
	wolf.held_tool = ""                       # no axe for the werewolf
	if _game_hud:
		_game_hud.visible = false          # health, tools and backpack are the settler's
	if _pickups:
		_pickups.enabled = false
	if _chopping:
		_chopping.player = wolf
	if _footprints:
		_footprints.walker = null          # only the villager leaves footprints
	_dark.player = wolf
	_dark.camera = wolf.camera
	_dark.apply()
	if _plant_push:
		_plant_push.player = wolf
	_apply_fog()
	_apply_idle()
	_apply_footsteps()


## AI werewolf when you play the human: appears far away and hunts you.
func _spawn_ai_werewolf() -> void:
	if is_instance_valid(werewolf) or player_role != "human":
		return
	var rect := _map_rect()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pos := Vector2.ZERO
	for i in 60:
		pos = Vector2(rng.randf_range(rect.position.x + 150, rect.end.x - 150), rng.randf_range(rect.position.y + 150, rect.end.y - 150))
		if pos.distance_to(player.global_position) >= werewolf_spawn_distance:
			break
	var wolf := Werewolf.new()
	wolf.is_local = false
	wolf.ai_controlled = true
	wolf.walk_speed = werewolf_walk_speed * GameSettings.werewolf_speed_scale()     # menu Difficulty
	wolf.sprint_speed = werewolf_sprint_speed * GameSettings.werewolf_speed_scale()
	wolf.target = player
	wolf.map_rect = rect
	wolf.sense_radius = werewolf_sense
	wolf.lose_radius = werewolf_lose
	world.add_child(wolf)
	wolf.global_position = pos
	wolf.reset_physics_interpolation()
	wolf.caught.connect(_on_caught)
	werewolf = wolf
	_apply_footsteps()
	_howl(pos)
	_flash("The werewolf is awake...", 3.0)


## A werewolf bite: lose health and get knocked away; at 0 the round is lost.
func _on_caught(_who: Node2D) -> void:
	if _dead:
		return
	health = maxf(health - werewolf_damage, 0.0)
	_since_hurt = 0.0
	if _game_hud:
		_game_hud.set_health(health, max_health, true)
	if is_instance_valid(werewolf) and is_instance_valid(player):
		werewolf.set("attack_interval", werewolf_bite_interval)
		var away: Vector2 = (player.global_position - werewolf.global_position).normalized()
		player.set("knockback", away * bite_knockback)
	if health > 0.0:
		return
	_dead = true
	if is_instance_valid(werewolf):
		werewolf.set("_caught", true)            # stops hunting
	_flash("You were killed!", 0.0)
	player.set_physics_process(false)
	get_tree().create_timer(3.0).timeout.connect(func(): get_tree().reload_current_scene())


## Big centred message (seconds = 0: stays).
func _flash(text: String, seconds: float) -> void:
	if _round_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 3
		add_child(layer)
		_round_label = Label.new()
		_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_round_label.position = Vector2(-400, 120)
		_round_label.size = Vector2(800, 60)
		_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_round_label.add_theme_font_size_override("font_size", 36)
		_round_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.7))
		_round_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_round_label.add_theme_constant_override("outline_size", 6)
		layer.add_child(_round_label)
	_round_label.text = text
	_round_label.visible = true
	if seconds > 0.0:
		get_tree().create_timer(seconds).timeout.connect(func(): if _round_label.text == text: _round_label.visible = false)


func _set_god_mode(on: bool) -> void:
	if on == god_mode:
		return
	god_mode = on
	var cam: Camera2D = player.camera
	if on:
		_saved_fog = fog_enabled
		fog_enabled = false
		_saved_limits = [cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom]
		if god_free_camera:
			cam.limit_left = -10000000; cam.limit_top = -10000000
			cam.limit_right = 10000000; cam.limit_bottom = 10000000
	else:
		fog_enabled = _saved_fog
		cam.zoom = Vector2(camera_zoom, camera_zoom)
		if _saved_limits.size() == 4:
			cam.limit_left = _saved_limits[0]; cam.limit_top = _saved_limits[1]
			cam.limit_right = _saved_limits[2]; cam.limit_bottom = _saved_limits[3]
		cam.reset_smoothing()
	player.god_mode = on
	player.god_speed = god_speed
	if _god_label:
		_god_label.visible = on


func _new_map(new_seed: int) -> void:
	seed_value = new_seed
	if map:
		player.reparent(self)       # rescue the player before the old map is freed
		map.queue_free()
	map = MapGenerator.new()
	add_child(map)
	map.generate(seed_value)

	# The player lives in the map's y-sorted node so trees draw in front of or
	# behind them depending on who is lower on the screen.
	player.reparent(map.entities)
	player.global_position = map.get_spawn_point()
	var cam: Camera2D = player.camera
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map.map_size.x)
	cam.limit_bottom = int(map.map_size.y)
	cam.reset_smoothing()

	_hud_label.text = "Seed %d   |   WASD move · Shift sprint · R new map · F god mode · N skip time · T rain · Mouse wheel zoom" % seed_value


## A fresh forest every round from the menu settings (map size + seed), built by
## the WorldBuilder node (its forest/prop settings are tuned on that node).
func _generate_world() -> void:
	var builder := get_node_or_null("WorldBuilder")
	if builder == null or use_generated_map:
		return
	GameSettings.next_round_seed()
	builder.ground_tiles = GameSettings.map_tiles()
	builder.map_seed = GameSettings.map_seed
	builder.rebuild(self)


## Map size or seed changed in the menu: restart so the new forest shows.
func _on_map_settings_changed() -> void:
	GameSettings.keep_seed_for_next_round()
	get_tree().reload_current_scene()


func _setup_painted_world() -> void:
	# The player joins the World's y-sorted node so trees/props painted there
	# draw in front of or behind them correctly.
	player.reparent(world)
	var spawn := world.get_node_or_null("Spawn")
	player.global_position = spawn.global_position if spawn else Vector2.ZERO
	player.reset_physics_interpolation()
	player.camera.zoom = Vector2(camera_zoom, camera_zoom)   # Camera settings on Main
	_add_world_borders()
	player.camera.reset_smoothing()
	_hud_label.text = "Seed %d (%s)   |   WASD move · Shift sprint · Click (hold) chop · E pick up · Tab backpack · 1-4 tools · F god mode · N skip time · T rain · F11 fullscreen" % [GameSettings.map_seed, GameSettings.map_size] + (" · Mouse wheel zoom" if scroll_zoom else "")


func _add_world_borders() -> void:
	# Invisible walls + camera limits around whatever ground you have painted,
	# so the map edge follows your painting automatically.
	var ground := world.get_node_or_null("Ground") as TileMapLayer
	if ground == null or ground.get_used_rect().size == Vector2i.ZERO:
		return
	var cell := Vector2(ground.tile_set.tile_size)
	var r := ground.get_used_rect()
	var rect := Rect2(ground.to_global(Vector2(r.position) * cell), Vector2(r.size) * cell)
	var t := 64.0
	var body := StaticBody2D.new()
	add_child(body)
	for wall in [
		Rect2(rect.position.x - t, rect.position.y - t, rect.size.x + 2 * t, t + 12),   # top (walk a bit under the edge)
		Rect2(rect.position.x - t, rect.end.y - 4, rect.size.x + 2 * t, t),
		Rect2(rect.position.x - t, rect.position.y, t + 8, rect.size.y),
		Rect2(rect.end.x - 8, rect.position.y, t, rect.size.y),
	]:
		var shape := RectangleShape2D.new()
		shape.size = wall.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = wall.get_center()
		body.add_child(cs)
	var cam: Camera2D = player.camera
	cam.limit_left = int(rect.position.x)
	cam.limit_top = int(rect.position.y)
	cam.limit_right = int(rect.end.x)
	cam.limit_bottom = int(rect.end.y)


func _build_hud() -> void:
	# CanvasLayer is not affected by the darkness (layer 2 = above it).
	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)

	_hud_label = Label.new()
	_hud_label.position = Vector2(16, 12)
	_hud_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(_hud_label)

	_god_label = Label.new()
	_god_label.text = "GOD MODE  ·  no fog · walk through anything · fast · mouse wheel zoom  ·  F to exit"
	_god_label.position = Vector2(16, 40)
	_god_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_god_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_god_label.add_theme_constant_override("outline_size", 4)
	_god_label.visible = false
	hud.add_child(_god_label)


func _setup_input() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"regenerate": [KEY_R],
		"god_mode": [KEY_F],
		"skip_time": [KEY_N],
		"toggle_rain": [KEY_T],
		"toggle_fullscreen": [KEY_F11],
		"pickup": [KEY_E],
		"inventory": [KEY_TAB, KEY_I],
		"tool_1": [KEY_1],
		"tool_2": [KEY_2],
		"tool_3": [KEY_3],
		"tool_4": [KEY_4],
	}
	if not InputMap.has_action("chop"):
		InputMap.add_action("chop")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("chop", click)
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
