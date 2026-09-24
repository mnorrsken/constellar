class_name ShipPanel
extends PanelContainer
## Card on the right of the map for the selected ship (clicked on the map
## or picked in the fleet card): its 3D model, what it is doing and where
## it is going, why it is idle or losing money, the cargo aboard (what it
## cost and what it is worth now), its contracts, condition, route orders
## and results, with buttons for the ship's orders, the market, contracts
## and the yard where it is docked. Scrolls when longer than the room
## above the news ticker (bottom_limit).

signal closed
signal orders_requested(ship_id: int)
## The player wants a screen for the port the ship is docked at:
## "market", "contracts" or "yard".
signal port_requested(what: String, system_index: int)

const WIDTH := 400.0
const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const AMBER := Color(0.98, 0.72, 0.3)
const CYAN := Color(0.45, 0.78, 0.86)

var ship_id := -1
## Screen y the panel must end above (set by main.gd).
var bottom_limit := 800.0:
	set(value):
		if absf(value - bottom_limit) > 1.0:
			bottom_limit = value
			_fit.call_deferred()

var _scroll := ScrollContainer.new()
var _box := VBoxContainer.new()
var _name := Label.new()
var _hull := Label.new()
var _viewer := ShipViewer.new()
var _doing := Label.new()
var _why := Label.new()
var _cargo := GridContainer.new()
var _cargo_title: Label
var _jobs := VBoxContainer.new()
var _jobs_title: Label
var _facts := Label.new()
var _route := Label.new()
var _buttons := HFlowContainer.new()

func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -WIDTH - 28
	offset_right = -28
	offset_top = 100
	offset_bottom = 100  # zero height: grows to fit
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_theme_constant_override("separation", 6)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_name.add_theme_font_size_override("font_size", 26)
	_hull.add_theme_font_size_override("font_size", 14)
	_hull.add_theme_color_override("font_color", MUTED)
	titles.add_child(_name)
	titles.add_child(_hull)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (Esc)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_panel)
	head.add_child(titles)
	head.add_child(close)
	_viewer.custom_minimum_size = Vector2(WIDTH - 28, 150)
	for l in [_doing, _why, _facts, _route]:
		l.add_theme_font_size_override("font_size", 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(WIDTH - 40, 0)
	_doing.add_theme_color_override("font_color", TEXT)
	_why.add_theme_color_override("font_color", AMBER)
	_facts.add_theme_color_override("font_color", MUTED)
	_route.add_theme_color_override("font_color", CYAN)
	_cargo.columns = 4
	_cargo.add_theme_constant_override("h_separation", 12)
	_cargo.add_theme_constant_override("v_separation", 1)
	_buttons.add_theme_constant_override("h_separation", 6)
	_buttons.add_theme_constant_override("v_separation", 6)
	_cargo_title = _section("Cargo")
	_jobs_title = _section("Contracts")
	for c in [head, _viewer, _doing, _why, HSeparator.new(), _cargo_title, _cargo, _jobs_title, _jobs,
			HSeparator.new(), _facts, _route, _buttons]:
		_box.add_child(c)
	_scroll.add_child(_box)
	add_child(_scroll)
	Events.fleet_changed.connect(_refresh)
	Events.day_passed.connect(func(_d): _refresh())
	Events.contracts_changed.connect(_refresh)
	Events.company_changed.connect(func(_c): _refresh())

func show_ship(id: int) -> void:
	ship_id = id
	if not visible:
		Motion.fade_in(self)
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not visible:
		return
	var w: World = Sim.world
	var s := w.fleet.get_ship(ship_id)
	if s == null:
		close_panel()  # sold or lost
		return
	var hull := w.fleet.hull_def(s)
	_name.text = s.name
	_hull.text = "%s  ·  %s" % [hull.name, hull["class"]]
	_viewer.show_ship(s)
	_doing.text = FleetPanel.status_text(w, s)
	if s.status == Ship.Status.TRAVELING:
		# The stops still ahead before the destination.
		var names := PackedStringArray()
		for i in range(s.leg + 1, s.route.size() - 1):
			names.append(w.galaxy.systems[s.route[i]].name)
		if not names.is_empty():
			_doing.text += "\nvia " + " ▸ ".join(names)
	var why := FleetPanel.note_text(w, s)
	_why.text = why
	_why.visible = why != ""
	_fill_cargo(w, s)
	_fill_jobs(w, s)
	var p := Sim.player()
	var last := p.profit(w.month() - 1, s.id)
	var year := 0.0
	for m in range(w.month() - 11, w.month() + 1):
		year += p.profit(m, s.id)
	var flags := PackedStringArray()
	if s.insured:
		flags.append("insured")
	if s.safe_routing:
		flags.append("safest routes")
	_facts.text = "Condition %d%%  ·  reliability %d%%  ·  %d years old\n%.2f ly/day  ·  %.0f ly jump%s\nProfit last month %s cr  ·  last 12 months %s cr" % [
		roundi(s.condition * 100.0), roundi(Aging.reliability(w, s) * 100.0), floori(Aging.age_years(w, s)),
		w.fleet.speed(s), w.fleet.jump_range(s), ("  ·  " + "  ·  ".join(flags)) if not flags.is_empty() else "",
		Format.thousands(roundi(last)), Format.thousands(roundi(year))]
	if s.orders.size() >= 2:
		var stops := PackedStringArray()
		for k in s.orders.size():
			var name: String = w.galaxy.systems[int(s.orders[k].system)].name
			stops.append(("▶ " + name) if s.orders_active and k == s.order_index else name)
		_route.text = "Route (%s): %s" % ["running" if s.orders_active else "stopped", " ▸ ".join(stops)]
	else:
		_route.text = "No route orders"
	_fill_buttons(w, s)
	_fit.call_deferred()

## Cargo aboard: tonnes, what it cost a tonne, what it fetches a tonne here
## (docked, live price) or at the destination (last known price), and the
## gain or loss on the lot.
func _fill_cargo(w: World, s: Ship) -> void:
	_clear(_cargo)
	var cap := w.fleet.capacity(s)
	var used := {}
	for c in s.cargo:
		var cls := Trading.commodity_class(w, c)
		used[cls] = used.get(cls, 0.0) + s.cargo[c]
	var holds := PackedStringArray()
	for cls in cap:
		holds.append("%s %s/%s t" % [cls, Format.thousands(roundi(used.get(cls, 0.0)
			+ Contracts.freight_reserved(w, s, cls))), Format.thousands(roundi(cap[cls]))])
	_cargo_title.text = "CARGO  ·  " + ("   ".join(holds) if not holds.is_empty() else "no holds")
	if s.cargo.is_empty():
		_cargo.add_child(_cell("No trade goods aboard.", MUTED, 13))
		for k in 3:
			_cargo.add_child(Control.new())
		return
	var here := s.status == Ship.Status.DOCKED
	var at := s.system if here else s.destination()
	var m := w.economy.market_at(at)
	var known := w.known_prices(Sim.PLAYER, at)
	for h in ["Good", "Aboard", "Paid / t", "%s / t" % ("Here" if here else "At " + w.galaxy.systems[at].name)]:
		_cargo.add_child(_cell(h, MUTED, 12))
	for c in s.cargo:
		var t: float = s.cargo[c]
		var paid: float = s.cargo_cost.get(c, 0.0) / maxf(t, 1.0)
		_cargo.add_child(_cell(Defs.commodities[w.economy.commodity_ids[c]].name, TEXT, 13))
		_cargo.add_child(_cell("%s t" % Format.thousands(roundi(t)), TEXT, 13, true))
		_cargo.add_child(_cell(Format.thousands(roundi(paid)), MUTED, 13, true))
		var worth := -1.0
		if m and here and not m.closed:
			worth = m.quote_sell(c, t) / t * (1.0 - Trading.tariff(w, at, c))
		elif not known.is_empty():
			worth = float(known.price[c]) * (1.0 - Trading.tariff(w, at, c))
		if worth < 0.0 or Trading.is_banned(w, at, c):
			_cargo.add_child(_cell("banned" if Trading.is_banned(w, at, c) else "unknown", MUTED, 13))
		else:
			var gain := (worth - paid) * t
			_cargo.add_child(_cell("%s  (%s%s)" % [Format.thousands(roundi(worth)), "+" if gain >= 0.0 else "",
				Format.money_short(gain)], GREEN if gain >= 0.0 else RED, 13, true))

func _fill_jobs(w: World, s: Ship) -> void:
	_clear(_jobs)
	var jobs := Contracts.active_for(w, s)
	_jobs_title.visible = not jobs.is_empty()
	_jobs.visible = not jobs.is_empty()
	for c in jobs:
		var left := c.deadline - w.day
		var what := c.describe(Defs.commodities.get(c.commodity, {}).get("name", ""))
		var line := _cell("%s to %s\n    by %s (%d days left)  ·  %s cr" % [what, w.galaxy.systems[c.destination].name,
			Calendar.format(c.deadline, w.start_year), left, Format.thousands(roundi(c.reward))],
			AMBER if left <= 10 else TEXT, 13)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(WIDTH - 40, 0)
		_jobs.add_child(line)

func _fill_buttons(w: World, s: Ship) -> void:
	_clear(_buttons)
	_buttons.add_child(_button("Route ▸" if s.orders_active else "Orders  O", func(): orders_requested.emit(s.id)))
	if s.status != Ship.Status.DOCKED:
		return
	var port := s.system
	if w.economy.market_at(port):
		_buttons.add_child(_button("Market  M", func(): port_requested.emit("market", port)))
		_buttons.add_child(_button("Contracts  C", func(): port_requested.emit("contracts", port)))
	if w.fleet.can_refit_at(port):
		_buttons.add_child(_button("Shipyard" if w.fleet.is_shipyard(port) else "Refit",
			func(): port_requested.emit("yard", port)))

func _fit() -> void:
	if not visible:
		return
	Fit.cap(self, _scroll, _box, bottom_limit)
	offset_bottom = offset_top

func _clear(c: Container) -> void:
	for child in c.get_children():
		c.remove_child(child)
		child.queue_free()

func _section(text: String) -> Label:
	var l := _cell(text.to_upper(), MUTED, 12)
	return l

func _cell(text: String, color: Color, size: int, mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
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
