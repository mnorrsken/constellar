class_name UiSounds
extends Node
## Interface sounds (assets/audio/ui/*.wav, made by tools/make_audio.py):
## a soft click on every button, and chimes and blips for game moments —
## refusals, sales and losses, arrivals, news, alerts, pause and resume.
## play() is also called by main.gd (selecting a star, opening panels).

const DIR := "res://assets/audio/ui/"
const NAMES := ["click", "select", "open", "close", "confirm", "error", "chime", "coin", "loss", "hail",
	"alert", "pause", "resume"]
const VOICES := 6

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _speed := -1

func _ready() -> void:
	for n in NAMES:
		if ResourceLoader.exists(DIR + n + ".wav"):
			_streams[n] = load(DIR + n + ".wav")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_players.append(p)
	# Every button in the game clicks.
	get_tree().node_added.connect(func(node: Node):
		if node is BaseButton:
			(node as BaseButton).pressed.connect(play.bind("click")))
	Events.refused.connect(func(_text): play("error"))
	Events.alert.connect(func(_text): play("alert"))
	Events.confirmed.connect(func(_kind): play("confirm"))
	Events.attention.connect(func(_ship, _system): play("hail"))
	Events.profit.connect(func(_ship, amount): play("coin" if amount >= 0.0 else "loss"))
	Events.news_posted.connect(func(item):
		if item.start and NewsTicker._visible(item):
			play("chime", -6.0))
	Events.speed_changed.connect(_on_speed)

## Plays a sound (volume offset in dB) on the next free voice.
func play(sound: String, volume_db := 0.0) -> void:
	# No sound card (headless runs): the dummy driver never lets go of a
	# playing stream, so don't start one (as MusicPlayer).
	if not _streams.has(sound) or AudioServer.get_driver_name() == "Dummy":
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.play()

func _on_speed(speed: int) -> void:
	if _speed >= 0 and (speed == 0) != (_speed == 0):
		play("pause" if speed == 0 else "resume")
	_speed = speed
