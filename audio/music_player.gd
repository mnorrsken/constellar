class_name MusicPlayer
extends Node
## Background music: a looping theme per government (and "space" for empty
## systems and the open map), from assets/audio/music/<id>.wav (made by
## tools/make_audio.py). play_theme() crossfades to another theme. Without
## the generated files the game simply stays quiet.

const DIR := "res://assets/audio/music/"
const DEFAULT := "space"
const FADE_SECONDS := 2.5
const SILENT_DB := -50.0

## Theme playing now ("" = none).
var theme := ""

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tween: Tween

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)

## Crossfades to a theme; unknown ids play the default.
func play_theme(id: String) -> void:
	if not ResourceLoader.exists(DIR + id + ".wav"):
		id = DEFAULT
	if id == theme or not ResourceLoader.exists(DIR + id + ".wav"):
		return
	# No sound card (headless runs): its dummy driver never lets go of a
	# playing stream, so don't start one.
	if AudioServer.get_driver_name() == "Dummy":
		theme = id
		return
	theme = id
	var old := _players[_active]
	_active = 1 - _active
	var new := _players[_active]
	new.stream = load(DIR + id + ".wav")
	new.volume_db = SILENT_DB
	new.play()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(new, "volume_db", 0.0, FADE_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(old, "volume_db", SILENT_DB, FADE_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_callback(old.stop)
