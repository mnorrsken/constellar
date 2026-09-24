class_name FleetPanel
extends PanelContainer
## Bottom-left list of the player's ships: name, what each is doing and,
## under it, why it is idle, waiting or losing money. Click a row to select
## that ship; V (or the title button) opens the full fleet screen.

signal ship_selected(ship_id: int)
signal orders_requested(ship_id: int)
signal screen_requested

const MUTED := Color(0.55, 0.62, 0.74)

var selected := -1

var _title := Button.new()
var _rows := VBoxContainer.new()

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
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 18)
	_title.flat = true
	_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.focus_mode = Control.FOCUS_NONE
	_title.tooltip_text = "Open the fleet screen (V)"
	_title.pressed.connect(func(): screen_requested.emit())
	_rows.add_theme_constant_override("separation", 2)
	box.add_child(_title)
	box.add_child(_rows)
	add_child(box)
	Events.fleet_changed.connect(refresh)
	Events.day_passed.connect(func(_d): refresh())
	refresh()

func select(ship_id: int) -> void:
	selected = ship_id
	refresh()

func refresh() -> void:
	var world: World = Sim.world
	var ships := world.ships_of(Sim.PLAYER)
	_title.text = "Fleet  ·  %d ship%s   ▸ V" % [ships.size(), "" if ships.size() == 1 else "s"]
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for s in ships:
		var b := Button.new()
		b.flat = s.id != selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var cargo := s.cargo_tonnes()
		var jobs := Contracts.active_for(world, s).size()
		b.text = "%s   ·   %s%s%s" % [s.name, status_text(world, s),
			"   ·   %s t aboard" % Format.thousands(roundi(cargo)) if cargo >= 1.0 else "",
			"   ·   %d contract%s" % [jobs, "" if jobs == 1 else "s"] if jobs > 0 else ""]
		b.tooltip_text = "%s  ·  %s t cargo  ·  %.2f ly/day  ·  %.0f ly jump" % [
			world.fleet.hull_def(s).name, Format.thousands(roundi(world.fleet.total_capacity(s))),
			world.fleet.speed(s), world.fleet.jump_range(s)]
		if s.insured or s.safe_routing:
			b.tooltip_text += "\n%s" % "  ·  ".join(PackedStringArray(
				(["insured"] if s.insured else []) + (["safest routes"] if s.safe_routing else [])))
		b.add_theme_font_size_override("font_size", 15)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): ship_selected.emit(s.id))
		var orders := Button.new()
		orders.text = "Route ▸" if s.orders_active else "Orders"
		orders.focus_mode = Control.FOCUS_NONE
		orders.add_theme_font_size_override("font_size", 13)
		orders.pressed.connect(func(): orders_requested.emit(s.id))
		var row := HBoxContainer.new()
		row.add_child(b)
		row.add_child(orders)
		_rows.add_child(row)
		var why := note_text(world, s)
		if why != "":
			var l := Label.new()
			l.text = "      " + why
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color(0.98, 0.72, 0.3, 0.9))
			_rows.add_child(l)
	(func(): offset_top = offset_bottom).call_deferred()

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
