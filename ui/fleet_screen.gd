class_name FleetScreen
extends PanelContainer
## The fleet screen (V): every ship with what it is doing and why it is idle,
## waiting or losing money; its age, condition and reliability; last
## month's result and a year of monthly results as a sparkline. Buttons
## select a ship, open its route orders, or service it at a shipyard.

signal closed
signal ship_selected(ship_id: int)
signal orders_requested(ship_id: int)

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const AMBER := Color(0.98, 0.72, 0.3)

var _title := Label.new()
var _grid := GridContainer.new()

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(_button("✕  Esc", close_panel))
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 6)
	for c in [head, _grid]:
		box.add_child(c)
	add_child(box)
	Events.fleet_changed.connect(_refresh)
	Events.day_passed.connect(func(_d): _refresh())
	Events.company_changed.connect(func(_c): _refresh())

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
	var p: Company = Sim.player()
	var ships := w.ships_of(Sim.PLAYER)
	_title.text = "Fleet  ·  %d ship%s" % [ships.size(), "" if ships.size() == 1 else "s"]
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for h in ["Ship", "Doing", "Why", "Age", "Condition", "Reliability", "Last month", "12 months", ""]:
		_grid.add_child(_cell(h, MUTED, 12))
	var now := w.month()
	for s in ships:
		var name_box := VBoxContainer.new()
		name_box.add_theme_constant_override("separation", 0)
		name_box.add_child(_cell(s.name, TEXT, 15))
		name_box.add_child(_cell(w.fleet.hull_def(s).name, MUTED, 12))
		_grid.add_child(name_box)
		var doing := _cell(FleetPanel.status_text(w, s), TEXT, 14)
		doing.custom_minimum_size = Vector2(230, 0)
		doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(doing)
		var why := _cell(FleetPanel.note_text(w, s), AMBER, 13)
		why.custom_minimum_size = Vector2(260, 0)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_grid.add_child(why)
		_grid.add_child(_cell("%d yr" % floori(Aging.age_years(w, s)), TEXT, 14, true))
		_grid.add_child(_condition_bar(s.condition))
		_grid.add_child(_cell("%d%%" % roundi(Aging.reliability(w, s) * 100.0), TEXT, 14, true))
		var last := p.profit(now - 1, s.id)
		_grid.add_child(_cell(Format.thousands(roundi(last)) if absf(last) >= 0.5 else "—",
			GREEN if last > 0.0 else (RED if last < 0.0 else MUTED), 14, true))
		var spark := Sparkline.new()
		spark.high_is_good = true
		var year := PackedFloat32Array()
		for m in range(now - 11, now + 1):
			year.append(p.profit(m, s.id))
		spark.set_data(year, 0.0)
		_grid.add_child(spark)
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		buttons.add_child(_button("Show", func():
			close_panel()
			ship_selected.emit(s.id)))
		buttons.add_child(_button("Orders", func():
			close_panel()
			orders_requested.emit(s.id)))
		var service := _button("Service", func(): Sim.service_ship(s.id))
		var q := Aging.service_quote(w, s)
		service.disabled = s.status != Ship.Status.DOCKED or not w.fleet.is_shipyard(s.system) or q.cost < 1.0
		service.tooltip_text = "At a shipyard: %s cr, %d days, back to %d%%" % [
			Format.thousands(roundi(q.cost)), q.days, roundi(q.condition * 100.0)] if q.cost >= 1.0 \
			else "In as good a state as its age allows"
		buttons.add_child(service)
		_grid.add_child(buttons)
	(func(): reset_size()).call_deferred()

## Condition as a small bar: green, amber when worn, red when poor.
func _condition_bar(x: float) -> Control:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = x
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = GREEN if x > 0.7 else (AMBER if x > 0.45 else RED)
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	bar.tooltip_text = "Condition %d%%" % roundi(x * 100.0)
	return bar

func _cell(text: String, color: Color, font_size: int, mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if mono:
		l.add_theme_font_override("font", Fonts.MONO)
	return l

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	return b
