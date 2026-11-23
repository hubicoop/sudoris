extends Node
## Short sound effects. They play on the Sound bus, which the Settings toggle mutes.
## The files in res://sounds are CC0 (see sounds/CREDITS.md).

const SudorisSettings := preload("res://settings.gd")

const PICK := "pick"
const PLACE := "place"
const JOKER := "joker"
const LEVEL_COMPLETE := "level_complete"
const LOSE := "lose"
const TICK := "tick"

const STREAMS := {
	PICK: preload("res://sounds/pick.ogg"),
	PLACE: preload("res://sounds/place.ogg"),
	JOKER: preload("res://sounds/joker.ogg"),
	LEVEL_COMPLETE: preload("res://sounds/level_complete.ogg"),
	LOSE: preload("res://sounds/lose.ogg"),
	TICK: preload("res://sounds/tick.ogg"),
}

## Loudness of each sound in dB, to balance them by ear.
const VOLUME_DB := {
	PICK: -6.0,
	PLACE: -3.0,
	JOKER: -3.0,
	LEVEL_COMPLETE: 0.0,
	LOSE: -2.0,
	TICK: -4.0,
}

## A few players, so quick sounds can overlap instead of cutting each other off.
const VOICES := 4

var players: Array[AudioStreamPlayer] = []
var next_voice := 0
## The last sound asked for, for the tests.
var last_sound := ""

func _ready() -> void:
	SudorisSettings.bus_index(SudorisSettings.SOUND_BUS)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = SudorisSettings.SOUND_BUS
		add_child(player)
		players.append(player)

func play(sound: String) -> void:
	if not STREAMS.has(sound):
		push_warning("Unknown sound: %s" % sound)
		return
	last_sound = sound
	if players.is_empty():
		return
	var player := players[next_voice]
	next_voice = (next_voice + 1) % players.size()
	player.stream = STREAMS[sound]
	player.volume_db = VOLUME_DB.get(sound, 0.0)
	player.play()
