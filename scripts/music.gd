extends Node
## Background music: shuffled ambient playlists for day and night.
##
## Lives under the scene tree root (not in main.tscn), so it keeps playing when
## a round restarts, through the start menu and while the game is paused.
## main.gd creates it once, gives it the playlists (Main > Music) and tells it
## the mood every frame: "day" until dusk starts, then "night".
##
## - Plays a random track from the current mood's list, never the same one twice
##   in a row, and works through the whole list before repeating (shuffle bag).
## - A short quiet gap between tracks, then the next one fades in.
## - When the mood changes, the playing track fades out and one from the other
##   list fades in.
## - Each track gets a volume correction (TRACK_GAIN_DB) so they all sound
##   equally loud; the files themselves are untouched.
## - Plays on the "Music" audio bus (made here if missing), whose volume is the
##   Music slider in Settings (game_settings.gd).

const BUS := "Music"
## Per-track loudness correction in dB (measured: brings every track to about
## -18 LUFS). New tracks without an entry play unchanged.
const TRACK_GAIN_DB := {
	"ambient_01.mp3": -0.2, "ambient_02.mp3": -0.9, "ambient_03.mp3": 0.3,
	"ambient_04.mp3": -2.0, "ambient_05.mp3": 0.3, "ambient_06.mp3": -0.7,
	"ambient_07.mp3": 1.5, "ambient_08.mp3": -3.2, "ambient_09.mp3": -1.9,
	"ambient_10.mp3": -1.1,
}
const SILENT := -60.0

var enabled := true
var day_tracks: Array = []
var night_tracks: Array = []
var fade_in := 4.0                     # seconds for a new track to fade in
var mood_fade := 6.0                   # seconds to fade out when day turns to night
var gap := Vector2(4.0, 14.0)          # quiet seconds between tracks (min, max)
var volume_db := 0.0                   # overall music level (on top of the bus)

var mood := "day"
var _players: Array[AudioStreamPlayer] = []
var _active := 0                       # index into _players
var _wait := 1.0                       # seconds until the next track starts
var _bags := {"day": [], "night": []}
var _last: AudioStream
var _rng := RandomNumberGenerator.new()
var _tweens := {}                      # player -> its running fade
var _switching := false                # mood changed: next track crossfades in over the old one


func _ready() -> void:
	name = "Music"
	process_mode = Node.PROCESS_MODE_ALWAYS      # also in the paused start menu
	_rng.randomize()
	ensure_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.volume_db = SILENT
		add_child(p)
		_players.append(p)


## Makes the "Music" bus (sending to Master) if the project doesn't have one.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")


## "day" or "night". Switching fades the current track out and starts the other list.
func set_mood(m: String) -> void:
	if m == mood:
		return
	mood = m
	var cur := _players[_active]
	if cur.playing:
		_fade(cur, SILENT, mood_fade, true)       # old track fades out...
	_switching = true
	_wait = 1.5                                  # ...and the new list fades in over it


func _process(delta: float) -> void:
	var cur := _players[_active]
	if not enabled:
		for p in _players:
			if p.playing:
				p.stop()
		return
	if cur.playing and not _switching:
		return
	_wait -= delta
	if _wait <= 0.0:
		_switching = false
		_play_next()


func _play_next() -> void:
	var stream := _pick()
	if stream == null:
		_wait = 2.0
		return
	_active = 1 - _active
	var p := _players[_active]
	p.stream = stream
	p.volume_db = SILENT
	p.play()
	_fade(p, _target_db(stream), fade_in, false)
	_last = stream
	# When this track ends, wait a little before the next one.
	if not p.finished.is_connected(_on_finished):
		p.finished.connect(_on_finished)


func _on_finished() -> void:
	_wait = _rng.randf_range(gap.x, maxf(gap.y, gap.x))


## Shuffle bag: every track of the list once before any repeats, and never the
## same track twice in a row.
func _pick() -> AudioStream:
	var list: Array = (night_tracks if mood == "night" else day_tracks).filter(func(s): return s != null)
	if list.is_empty():
		return null
	var bag: Array = _bags[mood]
	bag = bag.filter(func(s): return s in list)
	if bag.is_empty():
		bag = list.duplicate()
		bag.shuffle()
		if bag.size() > 1 and bag[0] == _last:
			bag.push_back(bag.pop_front())
	var s: AudioStream = bag.pop_front()
	_bags[mood] = bag
	return s


func _target_db(stream: AudioStream) -> float:
	var file := stream.resource_path.get_file()
	return volume_db + float(TRACK_GAIN_DB.get(file, 0.0))


## Tweens a player's volume; optionally stops it at the end (fade out).
func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	var old: Tween = _tweens.get(p)
	if old and old.is_valid():
		old.kill()                             # one fade at a time per player
	var tw := create_tween()
	_tweens[p] = tw
	tw.tween_property(p, "volume_db", to_db, maxf(seconds, 0.01))
	if stop_after:
		tw.tween_callback(p.stop)
