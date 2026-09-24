class_name NewsTicker
extends PanelContainer
## "The Rim Courier" strip at the bottom right: the latest headlines about
## charted space, one at a time, turning every few seconds. A new headline
## shows at once. Click it to select its system; N opens the news log.

signal system_requested(system_index: int)
signal log_requested

const TURN_SECONDS := 6.0
const SHOWN := 5
const AMBER := Color(0.98, 0.72, 0.3)

var _masthead := Label.new()
var _date := Label.new()
var _headline := Button.new()
var _items: Array[Dictionary] = []
var _index := 0
var _clock := 0.0

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_right = -28
	offset_bottom = -64
	offset_top = -64
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_masthead.text = "THE RIM COURIER"
	_masthead.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700, 3))
	_masthead.add_theme_font_size_override("font_size", 12)
	_masthead.add_theme_color_override("font_color", AMBER)
	_date.add_theme_font_override("font", Fonts.MONO)
	_date.add_theme_font_size_override("font_size", 12)
	_date.add_theme_color_override("font_color", Color(0.55, 0.62, 0.74))
	_headline.flat = true
	_headline.focus_mode = Control.FOCUS_NONE
	_headline.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_headline.add_theme_font_size_override("font_size", 15)
	_headline.custom_minimum_size = Vector2(520, 0)
	_headline.clip_text = true
	_headline.pressed.connect(_clicked)
	var more := Button.new()
	more.text = "News  N"
	more.focus_mode = Control.FOCUS_NONE
	more.add_theme_font_size_override("font_size", 12)
	more.pressed.connect(func(): log_requested.emit())
	for c in [_masthead, _date, _headline, more]:
		row.add_child(c)
	add_child(row)
	Events.news_posted.connect(_on_news)
	Events.charted.connect(func(_c): _reload())
	_reload()

func _process(delta: float) -> void:
	if _items.size() < 2:
		return
	_clock += delta
	if _clock >= TURN_SECONDS:
		_clock = 0.0
		_index = (_index + 1) % _items.size()
		_show()

## Latest headlines the player can place (they touch a charted system).
func _reload() -> void:
	_items.clear()
	for item in Sim.world.news:
		if _visible(item):
			_items.append(item)
	_items = _items.slice(maxi(_items.size() - SHOWN, 0))
	_items.reverse()
	_index = 0
	_show()

func _on_news(item: Dictionary) -> void:
	if not _visible(item):
		return
	_items.push_front(item)
	_items = _items.slice(0, SHOWN)
	_index = 0
	_clock = 0.0
	_show()
	modulate = Color(1.4, 1.3, 1.1)
	create_tween().tween_property(self, "modulate", Color.WHITE, 1.2)

func _show() -> void:
	if _items.is_empty():
		_date.text = ""
		_headline.text = "Quiet times on the rim."
		return
	var item: Dictionary = _items[_index]
	_date.text = Calendar.format(item.day, Sim.world.start_year)
	_headline.text = item.text
	_headline.tooltip_text = item.text

func _clicked() -> void:
	if not _items.is_empty() and not _items[_index].systems.is_empty():
		system_requested.emit(_items[_index].systems[0])

## Headlines about charted systems, and galaxy-wide ones (no system).
static func _visible(item: Dictionary) -> bool:
	if item.systems.is_empty():
		return true
	for i in item.systems:
		if Sim.player().is_known(i):
			return true
	return false
