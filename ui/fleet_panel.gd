class_name FleetPanel
extends PanelContainer
## Bottom left: the ship picker, however big the fleet. "Ships (n)" opens a
## scrollable list; the arrows step through the fleet; "All" (or V) opens
## the full fleet screen. Below: the selected ship's name, what it is doing
## and why it is idle, waiting or losing money, with Orders. Picking a ship
## (here or on the map) opens its full card, the ShipPanel.

signal ship_selected(ship_id: int)
signal orders_requested(ship_id: int)
signal screen_requested

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const AMBER := Color(0.98, 0.72, 0.3)
const LIST_HEIGHT := 300.0

var selected := -1

var _list_button := Button.new()
var _list_scroll := ScrollContainer.new()
## Ship ids the list buttons were built for.
var _list_key: Variant = null
var _list := VBoxContainer.new()
var _name := Label.new()
var _doing := Label.new()
var _why := Label.new()
var _orders := Button.new()

func _ready() -> void:
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 28
	offset_bottom = -64
	offset_top = -64  # zero height: grows upward to fit
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# The ship list (opens upward, above the card).
	_list_scroll.visible = false
	_list_scroll.custom_minimum_size = Vector2(0, 0)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	# Header: previous / list / next / all.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var prev := _small_button("◀", func(): _step(-1))
	prev.tooltip_text = "Previous ship"
	var next := _small_button("▶", func(): _step(1))
	next.tooltip_text = "Next ship"
	_list_button.focus_mode = Control.FOCUS_NONE
	_list_button.toggle_mode = true
	_list_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_list_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_button.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_list_button.add_theme_font_size_override("font_size", 16)
	_list_button.toggled.connect(func(on):
		_list_scroll.visible = on
		refresh())
	var all := _small_button("All  V", func(): screen_requested.emit())
	all.tooltip_text = "The fleet screen: every ship at a glance"
	for c in [prev, _list_button, next, all]:
		head.add_child(c)
	# The selected ship in a few lines.
	_name.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_name.add_theme_font_size_override("font_size", 18)
	for l in [_doing, _why]:
		l.add_theme_font_size_override("font_size", 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(400, 0)
	_doing.add_theme_color_override("font_color", TEXT)
	_why.add_theme_color_override("font_color", AMBER)
	_orders.focus_mode = Control.FOCUS_NONE
	_orders.pressed.connect(func(): if selected >= 0: orders_requested.emit(selected))
	var name_row := HBoxContainer.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name)
	name_row.add_child(_orders)
	for c in [_list_scroll, head, name_row, _doing, _why]:
		box.add_child(c)
	add_child(box)
	Events.fleet_changed.connect(refresh)
	Events.day_passed.connect(func(_d): refresh())
	refresh()

func select(ship_id: int) -> void:
	selected = ship_id
	if _list_button.button_pressed:
		_list_button.button_pressed = false  # picked: close the list
	refresh()

func refresh() -> void:
	var world: World = Sim.world
	var ships := world.ships_of(Sim.PLAYER)
	var chosen := world.fleet.get_ship(selected) if selected >= 0 else null
	var attention := ships.filter(func(s): return note_text(world, s) != "").size()
	_list_button.text = "Ships (%d)%s  %s" % [ships.size(),
		"  ·  %d need a look" % attention if attention > 0 else "", "▴" if _list_button.button_pressed else "▾"]
	if _list_scroll.visible:
		_fill_list(world, ships)
	_orders.visible = chosen != null
	_doing.visible = chosen != null
	if chosen == null:
		_name.text = "No ship selected"
		_why.text = "Pick one from the list, or click a ship on the map."
		_why.visible = true
		(func(): offset_top = offset_bottom).call_deferred()
		return
	_name.text = chosen.name
	_name.tooltip_text = world.fleet.hull_def(chosen).name
	_orders.text = "Route ▸" if chosen.orders_active else "Orders  O"
	_doing.text = "%s  ·  %s" % [world.fleet.hull_def(chosen).name, status_text(world, chosen)]
	var why := note_text(world, chosen)
	_why.text = why
	_why.visible = why != ""
	(func(): offset_top = offset_bottom).call_deferred()

## The list: one row per ship (name, what it's doing), a mark on ships
## whose note wants a look; the selected one highlighted.
func _fill_list(world: World, ships: Array[Ship]) -> void:
	# The buttons are rebuilt only when the fleet changes (so one isn't
	# replaced under the mouse every game day); their text is updated.
	var key := ships.map(func(s): return s.id)
	if key != _list_key:
		_list_key = key
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()
		for s in ships:
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.clip_text = true
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(func(): ship_selected.emit(s.id))
			_list.add_child(b)
	for k in ships.size():
		var s := ships[k]
		var b: Button = _list.get_child(k)
		b.flat = s.id != selected
		var why := note_text(world, s)
		b.text = "%s%s   ·   %s" % ["⚠ " if why != "" else "", s.name, status_text(world, s)]
		b.tooltip_text = why if why != "" else world.fleet.hull_def(s).name
		if why != "":
			b.add_theme_color_override("font_color", AMBER)
		else:
			b.remove_theme_color_override("font_color")
	# Grow with the fleet up to LIST_HEIGHT, then scroll.
	_list_scroll.custom_minimum_size.y = minf(ships.size() * 30.0 + 4.0, LIST_HEIGHT)

## Previous / next ship in fleet order (wrapping).
func _step(by: int) -> void:
	var ships := Sim.world.ships_of(Sim.PLAYER)
	if ships.is_empty():
		return
	var at := -1
	for k in ships.size():
		if ships[k].id == selected:
			at = k
	var next: int = (at + by + ships.size()) % ships.size() if at >= 0 else 0
	ship_selected.emit(ships[next].id)

func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	return b

## Why a ship is idle, waiting or losing money, or "" when all is well.
static func note_text(world: World, s: Ship) -> String:
	if s.status == Ship.Status.TRAVELING and s.broken_until > world.day:
		return s.note if s.note != "" else "broken down"
	if s.status == Ship.Status.REFITTING:
		return ""
	if s.status == Ship.Status.DOCKED and not s.orders_active:
		if s.note.begins_with("route stopped"):
			return s.note
		return "idle: awaiting orders" if Sim.waiting.has(s.id) else "idle: no orders"
	if s.note != "":
		return s.note
	var reason := Trading.loss_reason(Sim.player(), s.id, world.month() - 1)
	if reason != "":
		return "lost money last month: " + reason
	if Aging.needs_service(world, s):
		return "worn (%d%%): service it at a shipyard" % roundi(s.condition * 100.0)
	return ""

static func status_text(world: World, s: Ship) -> String:
	match s.status:
		Ship.Status.TRAVELING:
			return "to %s, arrives %s" % [world.galaxy.systems[s.destination()].name,
				Calendar.format(s.arrival_day, world.start_year)]
		Ship.Status.REFITTING:
			return "refitting at %s until %s" % [world.galaxy.systems[s.system].name,
				Calendar.format(s.busy_until, world.start_year)]
	var here := world.galaxy.systems[s.system]
	# Only a settlement has a spaceport to dock at.
	return ("docked at %s" if here.settlement else "holding at %s") % here.name
