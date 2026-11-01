extends RefCounted
## The player's choices from the Settings screen, saved in user://settings.cfg.

const SAVE_PATH := "user://settings.cfg"
# Preloaded rather than a global class_name, so the game runs even before the
# editor has rescanned the project for new classes.
const SudorisStrings := preload("res://strings.gd")
const LANGUAGES: Array[String] = ["tr", "en"]
## Audio buses the toggles mute. Sounds and music added later should play on these.
const SOUND_BUS := "Sound"
const MUSIC_BUS := "Music"

var sound := true
var music := true
var vibration := true
var language := ""

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		sound = bool(config.get_value("audio", "sound", true))
		music = bool(config.get_value("audio", "music", true))
		vibration = bool(config.get_value("haptics", "vibration", true))
		language = str(config.get_value("game", "language", ""))
	if not LANGUAGES.has(language):
		# First launch: Turkish phones get Turkish, everyone else English.
		language = "tr" if OS.get_locale_language() == "tr" else "en"

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "sound", sound)
	config.set_value("audio", "music", music)
	config.set_value("haptics", "vibration", vibration)
	config.set_value("game", "language", language)
	config.save(SAVE_PATH)

func apply() -> void:
	SudorisStrings.register()
	TranslationServer.set_locale(language)
	AudioServer.set_bus_mute(bus_index(SOUND_BUS), not sound)
	AudioServer.set_bus_mute(bus_index(MUSIC_BUS), not music)

func next_language() -> void:
	language = LANGUAGES[(LANGUAGES.find(language) + 1) % LANGUAGES.size()]

## Index of the named bus, created under Master if the project does not have it yet.
static func bus_index(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	return index
