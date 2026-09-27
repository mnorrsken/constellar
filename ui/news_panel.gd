class_name NewsPanel
extends PanelContainer
## The news log (N): what is going on now in charted space (running events
## and when they end), then the Rim Courier's headlines, newest first.
## Clicking a line closes the log and selects its system on the map.

signal closed
signal system_requested(system_index: int)

const MUTED := Color(0.55, 0.62, 0.74)
const LOG_LINES := 60
const BADGES := {
	"danger": Color(1.0, 0.4, 0.35),
	"politics": Color(0.98, 0.72, 0.3),
	"info": Color(0.45, 0.85, 1.0),
}

var _title := Label.new()
var _now := VBoxContainer.new()
var _log := VBoxContainer.new()

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(820, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	_title.text = "The Rim Courier"
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "✕  Esc"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	head.add_child(_title)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)
	for c in [head, _section("Now"), _now, HSeparator.new(), _section("Headlines"), scroll]:
		box.add_child(c)
	add_child(box)
	Events.news_posted.connect(func(_i): _refresh())
	Events.charted.connect(func(_c): _refresh())

func open() -> void:
	visible = true
	Motion.pop_in(self)
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not visible:
		return
	var w: World = Sim.world
	for c in _now.get_children() + _log.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	for ev in w.world_events:
		if not ev.systems.any(func(i): return Sim.player().is_known(i)):
			continue
		var d := WorldEvents.def_of(w, ev.kind)
		_now.add_child(_line("%s   until %s" % [ev.headline, Calendar.format(ev.end_day, w.start_year)],
			BADGES.get(d.get("badge", "info"), Color.WHITE), ev.systems[0]))
	if _now.get_child_count() == 0:
		_now.add_child(_line("Nothing unusual in charted space.", MUTED, -1))
	var shown := 0
	for k in range(w.news.size() - 1, -1, -1):
		var item: Dictionary = w.news[k]
		if not NewsTicker._visible(item):
			continue
		var text := "%s   %s" % [Calendar.format(item.day, w.start_year), item.text]
		_log.add_child(_line(text, Color(0.86, 0.9, 0.97) if item.start else MUTED,
			item.systems[0] if not item.systems.is_empty() else -1))
		shown += 1
		if shown >= LOG_LINES:
			break
	if shown == 0:
		_log.add_child(_line("No news yet.", MUTED, -1))
	Fit.center.call_deferred(self)

func _line(text: String, color: Color, system_index: int) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", color)
	b.disabled = system_index < 0
	b.add_theme_color_override("font_disabled_color", color)
	b.pressed.connect(func():
		close_panel()
		system_requested.emit(system_index))
	return b

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", MUTED)
	return l
