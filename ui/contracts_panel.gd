class_name ContractsPanel
extends PanelContainer
## Contracts (C): the job board of one market, with Accept for a player ship
## docked there, and the player's running jobs with Abandon. Opened from the
## system card or with C; Esc closes.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const GREEN := Color(0.45, 0.85, 0.55)
const AMBER := Color(0.98, 0.72, 0.3)
const RED := Color(1.0, 0.45, 0.4)
const KIND_NAMES := {"freight": "Freight", "passengers": "Passengers", "mail": "Mail"}

## The selected ship (takes jobs when docked here), or -1.
var ship_id := -1
var system := -1

var _title := Label.new()
var _ship_line := Label.new()
var _offers := GridContainer.new()
var _none := Label.new()
var _jobs_title := Label.new()
var _jobs := GridContainer.new()

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
	head.add_theme_constant_override("separation", 12)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := _button("✕  Esc", close_panel)
	head.add_child(_title)
	head.add_child(close)
	_ship_line.add_theme_font_size_override("font_size", 14)
	_none.add_theme_font_size_override("font_size", 14)
	_none.add_theme_color_override("font_color", MUTED)
	_offers.columns = 8
	_jobs.columns = 7
	for g in [_offers, _jobs]:
		g.add_theme_constant_override("h_separation", 18)
		g.add_theme_constant_override("v_separation", 4)
	_jobs_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_jobs_title.add_theme_font_size_override("font_size", 18)
	for c in [head, _ship_line, _offers, _none, HSeparator.new(), _jobs_title, _jobs]:
		box.add_child(c)
	add_child(box)
	Events.contracts_changed.connect(_refresh)
	Events.fleet_changed.connect(_refresh)
	Events.day_passed.connect(func(_d): _refresh())

func open(system_index: int, selected_ship: int) -> void:
	system = system_index
	ship_id = selected_ship
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not visible:
		return
	var w: World = Sim.world
	var s: StarSystem = w.galaxy.systems[system]
	_title.text = "Contracts  ·  %s  (%s)" % [s.settlement.name, s.name]
	var ship := _docked_ship()
	if ship:
		_ship_line.text = "%s is docked here  ·  free: %s" % [ship.name, _room_text(w, ship)]
		_ship_line.add_theme_color_override("font_color", GREEN)
	else:
		_ship_line.text = "None of your ships is docked here: dock one to take a job."
		_ship_line.add_theme_color_override("font_color", MUTED)
	_fill_offers(w, ship)
	_fill_jobs(w)
	(func(): reset_size()).call_deferred()

func _fill_offers(w: World, ship: Ship) -> void:
	for c in _offers.get_children():
		_offers.remove_child(c)  # now, so the panel can shrink this frame
		c.queue_free()
	var offers := Contracts.offers_at(w, system)
	offers.sort_custom(func(a, b): return a.reward > b.reward)
	_none.visible = offers.is_empty()
	_none.text = "The board is empty. New jobs are posted every week."
	if offers.is_empty():
		return
	for h in ["Job", "Load", "To", "Trip", "Deliver by", "Reward", "Penalty", ""]:
		_offers.add_child(_cell(h, MUTED, 12))
	var known := Sim.player().known
	for c in offers:
		var to: StarSystem = w.galaxy.systems[c.destination]
		var charted: bool = known[c.destination] == 1
		var trip := "—"
		var trip_color := MUTED
		var note := ""
		if not charted:
			note = "uncharted"
		elif ship:
			var plan := Sim.plan_route(ship.id, c.destination)
			if plan.ok:
				trip = "%d d" % plan.days
				var late: bool = w.day + int(plan.days) > c.deadline
				trip_color = RED if late else TEXT
				if late:
					note = "too slow"
			else:
				note = "out of range"
			if note == "" and not Contracts.fits(w, ship, c):
				note = "no room"
		_offers.add_child(_cell(KIND_NAMES.get(c.kind, c.kind), TEXT, 14))
		_offers.add_child(_cell(_load(c), TEXT, 14))
		_offers.add_child(_cell(to.name if charted else "uncharted system", TEXT if charted else MUTED, 14))
		_offers.add_child(_cell(trip, trip_color, 14, true))
		_offers.add_child(_cell(_date_left(w, c.deadline), TEXT, 14, true))
		_offers.add_child(_money(c.reward, GREEN))
		_offers.add_child(_money(c.penalty, RED))
		var accept := _button("Accept" if note == "" or note == "too slow" else note,
			func(): Sim.accept_contract(c.id, ship.id))
		accept.disabled = ship == null or (note != "" and note != "too slow")
		# Never hide grid cells (the columns would shift): no ship, no button.
		accept.modulate.a = 0.0 if ship == null else 1.0
		accept.mouse_filter = Control.MOUSE_FILTER_IGNORE if ship == null else Control.MOUSE_FILTER_STOP
		if note == "too slow":
			accept.tooltip_text = "This ship cannot make the deadline: the penalty would be charged"
		_offers.add_child(accept)

func _fill_jobs(w: World) -> void:
	for c in _jobs.get_children():
		_jobs.remove_child(c)  # now, so the panel can shrink this frame
		c.queue_free()
	var jobs := w.contracts_of(Sim.PLAYER)
	_jobs_title.text = "Your contracts  ·  %d" % jobs.size()
	_jobs.visible = not jobs.is_empty()
	if jobs.is_empty():
		return
	for h in ["Ship", "Load", "From", "To", "Deliver by", "Reward", ""]:
		_jobs.add_child(_cell(h, MUTED, 12))
	for c in jobs:
		var ship := w.fleet.get_ship(c.ship)
		var left := c.deadline - w.day
		_jobs.add_child(_cell(ship.name if ship else "—", TEXT, 14))
		_jobs.add_child(_cell(_load(c), TEXT, 14))
		_jobs.add_child(_cell(w.galaxy.systems[c.origin].name, MUTED, 14))
		_jobs.add_child(_cell(w.galaxy.systems[c.destination].name, TEXT, 14))
		_jobs.add_child(_cell(_date_left(w, c.deadline), AMBER if left <= 10 else TEXT, 14, true))
		_jobs.add_child(_money(c.reward, GREEN))
		var abandon := _button("Abandon  −%s" % Format.thousands(roundi(c.penalty)),
			func(): Sim.abandon_contract(c.id))
		abandon.tooltip_text = "Give the job up and pay the penalty"
		_jobs.add_child(abandon)

## The selected player ship if docked here, else any docked here.
func _docked_ship() -> Ship:
	var chosen: Ship = null
	for s in Sim.world.ships_of(Sim.PLAYER):
		if s.status == Ship.Status.DOCKED and s.system == system:
			if s.id == ship_id:
				return s
			if chosen == null:
				chosen = s
	return chosen

func _room_text(w: World, ship: Ship) -> String:
	var parts := PackedStringArray()
	var cap := w.fleet.capacity(ship)
	for cls in cap:
		var free: float = cap[cls] - Contracts.freight_reserved(w, ship, cls)
		for c in ship.cargo:
			if Trading.commodity_class(w, c) == cls:
				free -= ship.cargo[c]
		parts.append("%s %s t" % [cls, Format.thousands(roundi(maxf(free, 0.0)))])
	var berths := Contracts.free_berths(w, ship)
	if berths.economy > 0:
		parts.append("%d berths" % berths.economy)
	if berths.luxury > 0:
		parts.append("%d suites" % berths.luxury)
	var mail := Contracts.free_mail(w, ship)
	if mail > 0:
		parts.append("%d mail sacks" % mail)
	return "   ".join(parts) if not parts.is_empty() else "nothing"

func _load(c: Contract) -> String:
	return c.describe(Defs.commodities.get(c.commodity, {}).get("name", ""))

func _date_left(w: World, day: int) -> String:
	var left := day - w.day
	return "%s  (%d d)" % [Calendar.format(day, w.start_year), left]

func _money(v: float, color: Color) -> Label:
	var l := _cell(Format.thousands(roundi(v)), color, 14, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

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
