class_name ContractsPanel
extends PanelContainer
## Contracts (C): the job board of one market, with Accept for a player ship
## docked there, and the player's running jobs with Abandon (express jobs
## show their early-delivery bonus; jobs of other ships than the current one
## are greyed, and "Go" sends a job's ship to its destination at once and
## closes the panel). It
## stays in the middle of the screen
## and scrolls when the lists would run off it. The game is paused while it
## is open and runs on at its old speed when it closes. Place names are links: they close the
## panel and show the system on the map. Opened from the system card or
## with C; Esc closes.

signal closed
signal system_requested(system_index: int)

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
## What the grids were built for, and the cells that change without a
## rebuild (the rows and their buttons stay put while the game runs, so
## they can be clicked).
var _offers_key: Variant = null
var _offer_cells: Array = []  # per offer: [trip label, deliver-by label]
var _jobs_key: Variant = null
var _scroll := ScrollContainer.new()
var _body: VBoxContainer
var _job_cells: Array = []  # per job: [deliver-by label, reward label, go button]
## The game speed to go back to on closing (0 = it was paused already).
var _resume_speed := 0

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
	# The offers and jobs scroll when they would run off the screen.
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in [_offers, _none, HSeparator.new(), _jobs_title, _jobs]:
		body.add_child(c)
	_body = body
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(body)
	for c in [head, _ship_line, _scroll]:
		box.add_child(c)
	add_child(box)
	# However the panel goes away (Esc, a link, another panel), the game
	# runs on.
	visibility_changed.connect(func():
		if not visible and _resume_speed > 0:
			if Sim.speed == 0:
				Sim.set_speed(_resume_speed)
			_resume_speed = 0)
	Events.contracts_changed.connect(_refresh)
	Events.fleet_changed.connect(_refresh)
	Events.day_passed.connect(func(_d): _refresh())

func open(system_index: int, selected_ship: int) -> void:
	_offers_key = null  # a fresh build on opening
	_jobs_key = null
	system = system_index
	ship_id = selected_ship
	_pause()
	visible = true
	Motion.pop_in(self)
	_refresh()

## Stops the clock, remembering its speed for when the panel closes.
func _pause() -> void:
	if Sim.speed > 0:
		_resume_speed = Sim.speed
		Sim.set_speed(0)

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
	_fill_jobs(w, ship.id if ship else ship_id)
	Fit.fit_screen.call_deferred(self, _scroll, _body)

func _fill_offers(w: World, ship: Ship) -> void:
	var offers := Contracts.offers_at(w, system)
	offers.sort_custom(func(a, b): return a.reward > b.reward)
	_none.visible = offers.is_empty()
	_none.text = "The board is empty. New jobs are posted every week."
	var known := Sim.player().known
	# Per offer: [contract, trip text, trip colour, note (what the button says)].
	var rows := []
	for c in offers:
		var trip := "—"
		var trip_color := MUTED
		var note := ""
		if known[c.destination] != 1:
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
		rows.append([c, trip, trip_color, note])
	var key := [ship.id if ship else -1, rows.map(func(r): return [r[0].id, r[3]])]
	if key == _offers_key:
		for k in rows.size():
			_offer_cells[k][0].text = rows[k][1]
			_offer_cells[k][0].add_theme_color_override("font_color", rows[k][2])
			_offer_cells[k][1].text = _date_left(w, rows[k][0].deadline)
		return
	_offers_key = key
	_offer_cells.clear()
	for c in _offers.get_children():
		_offers.remove_child(c)  # now, so the panel can shrink this frame
		c.queue_free()
	if offers.is_empty():
		return
	for h in ["Job", "Load", "To", "Trip", "Deliver by", "Reward", "Penalty", ""]:
		_offers.add_child(_cell(h, MUTED, 12))
	for r in rows:
		var c: Contract = r[0]
		var note: String = r[3]
		var trip := _cell(r[1], r[2], 14, true)
		var deliver := _cell(_date_left(w, c.deadline), TEXT, 14, true)
		_offer_cells.append([trip, deliver])
		_offers.add_child(_kind_cell(w, c))
		_offers.add_child(_cell(_load(c), TEXT, 14))
		_offers.add_child(_link(c.destination) if note != "uncharted" else _cell("uncharted system", MUTED, 14))
		_offers.add_child(trip)
		_offers.add_child(deliver)
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

## `current`: the ship the panel is about (docked here, else selected);
## the other ships' jobs are greyed.
func _fill_jobs(w: World, current: int) -> void:
	var jobs := w.contracts_of(Sim.PLAYER)
	_jobs_title.text = "Your contracts  ·  %d" % jobs.size()
	_jobs.visible = not jobs.is_empty()
	var key := [current, jobs.map(func(c): return c.id)]
	if key == _jobs_key:
		for k in jobs.size():
			_update_job(w, jobs[k], _job_cells[k][0], _job_cells[k][1], _job_cells[k][2])
		return
	_jobs_key = key
	_job_cells.clear()
	for c in _jobs.get_children():
		_jobs.remove_child(c)  # now, so the panel can shrink this frame
		c.queue_free()
	if jobs.is_empty():
		return
	for h in ["Ship", "Load", "From", "To", "Deliver by", "Reward", ""]:
		_jobs.add_child(_cell(h, MUTED, 12))
	for c in jobs:
		var ship := w.fleet.get_ship(c.ship)
		var to := HBoxContainer.new()
		to.add_theme_constant_override("separation", 8)
		to.add_child(_link(c.destination))
		var go := _button("Go", func():
			# Under way: the panel closes and the game runs on.
			if Sim.send_ship(c.ship, c.destination).ok:
				close_panel())
		to.add_child(go)
		var deliver := _cell("", TEXT, 14, true)
		var pay := _money(c.reward, GREEN)
		_update_job(w, c, deliver, pay, go)
		_job_cells.append([deliver, pay, go])
		var abandon := _button("Abandon  −%s" % Format.thousands(roundi(c.penalty)),
			func(): Sim.abandon_contract(c.id))
		abandon.tooltip_text = "Give the job up and pay the penalty"
		var row := [_cell(ship.name if ship else "—", TEXT, 14), _cell(_load(c), TEXT, 14), _link(c.origin), to,
			deliver, pay, abandon]
		for cell in row:
			# Another ship's job: greyed (still usable).
			if current >= 0 and c.ship != current:
				cell.modulate = Color(1, 1, 1, 0.4)
			_jobs.add_child(cell)

## The cells of a running job that change by the day, and whether its ship
## can go to the destination now.
func _update_job(w: World, c: Contract, deliver: Label, pay: Label, go: Button) -> void:
	deliver.text = _date_left(w, c.deadline)
	deliver.add_theme_color_override("font_color", AMBER if c.deadline - w.day <= 10 else TEXT)
	pay.text = Format.thousands(roundi(c.reward))
	if c.express:
		var bonus := Contracts.early_bonus(w, c, w.day)
		pay.text += "  +%s" % Format.money_short(bonus)
		pay.tooltip_text = "Express: %s cr bonus if delivered today; it shrinks toward the deadline" % Format.thousands(roundi(bonus))
		pay.mouse_filter = Control.MOUSE_FILTER_PASS
	var ship := w.fleet.get_ship(c.ship)
	var why := ""
	if ship == null:
		why = "The ship is gone"
	elif ship.status == Ship.Status.TRAVELING:
		why = "%s is under way" % ship.name
	elif ship.status != Ship.Status.DOCKED:
		why = "%s is in the yard" % ship.name
	elif ship.system == c.destination:
		why = "%s is there" % ship.name
	var plan := Sim.plan_route(ship.id, c.destination) if why == "" else {}
	if why == "" and not plan.ok:
		why = plan.error
	go.disabled = why != ""
	if why != "":
		go.tooltip_text = why
	else:
		go.tooltip_text = "Send %s there now: %d days, arrives %s%s" % [ship.name, plan.days,
			Calendar.format(w.day + int(plan.days), w.start_year),
			" (stops its route orders)" if ship.orders_active else ""]

## A system's name as a link to it on the map.
func _link(i: int) -> SystemLink:
	var l := SystemLink.make(i, Sim.world.galaxy.systems[i].name)
	l.pressed.connect(func():
		close_panel()
		system_requested.emit(i))
	return l

## "Mail · express" for express jobs (with the bonus in the tooltip).
func _kind_cell(w: World, c: Contract) -> Label:
	var l := _cell(KIND_NAMES.get(c.kind, c.kind), TEXT, 14)
	if c.express:
		l.text += "  · express"
		l.add_theme_color_override("font_color", AMBER)
		l.tooltip_text = "Up to +%d%% of the reward for early delivery: the faster, the more" % roundi(
			float(w.content.balance.get("contracts", {}).get("express_bonus", 0.0)) * 100.0)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l

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
