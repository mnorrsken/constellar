class_name MarketPanel
extends PanelContainer
## Market of the selected system as the player knows it: live while one of
## their ships is docked there (with buy/sell buttons for that ship), else
## the last prices a ship saw, with their age, else nothing. Hovering a price
## shows its last 26 weeks as a graph. The panel closes when the ship it
## trades with leaves (and no other player ship is docked there). While the mouse
## is over another star on the map, the "vs base" column compares with that
## system instead: what a tonne bought here sells for there (after its
## tariff, from the prices the player knows there), green when it pays.

const WEEKS := 26
const GREEN := Color(0.45, 0.85, 0.55)
const AMBER := Color(0.98, 0.72, 0.3)
const MUTED := Color(0.55, 0.62, 0.74)
const LOTS := [0.0, 500.0, 100.0]  # 0 = as much as possible

## The docked ship it traded with left: main.gd closes the market.
signal ship_left

## A unit price whose tooltip is its price graph (the last WEEKS weeks).
class PriceLabel extends Label:
	var good := ""
	var series := PackedFloat32Array()
	var base := 1.0
	## Shown instead of a graph when there is no history (known prices only).
	var note := ""

	func _make_custom_tooltip(_for_text: String) -> Object:
		var box := VBoxContainer.new()
		var title := Label.new()
		title.text = "%s  ·  last %d weeks" % [good, series.size()] if series.size() >= 2 else good
		title.add_theme_font_size_override("font_size", 13)
		box.add_child(title)
		if series.size() < 2:
			var why := Label.new()
			why.text = note
			why.add_theme_font_size_override("font_size", 12)
			why.add_theme_color_override("font_color", MarketPanel.MUTED)
			box.add_child(why)
			return box
		var graph := Sparkline.new()
		graph.custom_minimum_size = Vector2(260, 80)
		graph.set_data(series, base)
		box.add_child(graph)
		var lo := series[0]
		var hi := series[0]
		for v in series:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		var range_line := Label.new()
		range_line.text = "low %s  ·  high %s  ·  base %s" % [Format.thousands(roundi(lo)), Format.thousands(roundi(hi)),
			Format.thousands(roundi(base))]
		range_line.add_theme_font_override("font", Fonts.MONO)
		range_line.add_theme_font_size_override("font_size", 12)
		range_line.add_theme_color_override("font_color", MarketPanel.MUTED)
		box.add_child(range_line)
		return box

## The ship the player has selected (trades use it when docked here).
var ship_id := -1

var _title := Label.new()
var _status := Label.new()
var _hold := Label.new()
var _lot := OptionButton.new()
var _grid := GridContainer.new()
var _system := -1
## The star under the mouse to compare with (-1 = compare with base prices).
var _compare := -1
var _vs_head: Label
var _cells: Array = []  # per commodity: [name, price, change, stock, tag, aboard, buy, sell]
var _trade_ship: Ship
## Screen y the panel must end above (the fleet card; set by main.gd). The
## table scrolls when it would run lower.
var bottom_limit := 800.0:
	set(value):
		if absf(value - bottom_limit) > 1.0:
			bottom_limit = value
			_fit()
var _scroll := ScrollContainer.new()
var _viewer := ShipViewer.new()

func _ready() -> void:
	visible = false
	offset_left = 28
	offset_top = 100
	offset_bottom = 100  # zero height: grows to fit
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 22)
	_status.add_theme_font_size_override("font_size", 14)
	_hold.add_theme_font_size_override("font_size", 14)
	_hold.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))
	# Both wrap, so the table sets the panel's width, not a long line of text.
	for l in [_status, _hold]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1, 0)
	for l in ["Lot: all that fits", "Lot: 500 t", "Lot: 100 t"]:
		_lot.add_item(l)
	_lot.focus_mode = Control.FOCUS_NONE
	var trade_row := HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 12)
	_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_row.add_child(_hold)
	trade_row.add_child(_lot)
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 1)
	for h in ["Good", "Price", "vs base", "Stock", "", "Aboard", "", ""]:
		var head := _label(h, MUTED, 12)
		if h == "vs base":
			_vs_head = head
			head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_grid.add_child(head)
	var ids: PackedStringArray = Sim.world.economy.commodity_ids
	for c in ids.size():
		var id := ids[c]
		var price := PriceLabel.new()
		price.good = Defs.commodities[id].name
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_theme_font_override("font", Fonts.MONO)
		price.add_theme_font_size_override("font_size", 14)
		price.mouse_filter = Control.MOUSE_FILTER_PASS
		price.mouse_default_cursor_shape = Control.CURSOR_HELP
		price.tooltip_text = "price graph"  # any text: the tooltip itself is the graph
		var row := [
			_label(Defs.commodities[id].name, Color(0.86, 0.9, 0.97), 14),
			price,
			_label("", Color.WHITE, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_label("", MUTED, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_label("", MUTED, 12),
			_label("", AMBER, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_button("Buy", func(): _trade(id, true)),
			_button("Sell", func(): _trade(id, false)),
		]
		for cell in row:
			_grid.add_child(cell)
		_cells.append(row)
	var close := _label("M to close", MUTED, 12)
	# Title and status on the left, the docked ship's model on the right.
	var head := HBoxContainer.new()
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(_title)
	words.add_child(_status)
	_viewer.custom_minimum_size = Vector2(220, 84)
	head.add_child(words)
	head.add_child(_viewer)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_grid)
	for c in [head, trade_row, _scroll, close]:
		box.add_child(c)
	add_child(box)
	Events.day_passed.connect(func(_d): _refresh())
	Events.fleet_changed.connect(_refresh)
	Events.world_events_changed.connect(_refresh)
	Events.company_changed.connect(func(_c): _refresh())

## Shows the market of a system, or hides the panel where there is none.
func show_system(s: StarSystem) -> void:
	if Sim.world.economy.market_at(s.index) == null or not Sim.player().is_known(s.index):
		visible = false
		_system = -1
		return
	if s.index != _system:
		_trade_ship = null  # a new place: nothing has left it yet
	_system = s.index
	_title.text = "Market  ·  %s" % s.settlement.name
	if not visible:
		Motion.fade_in(self)
	visible = true
	_refresh()

## The star under the mouse (-1 = none): compare with its prices.
func set_compare(system_index: int) -> void:
	if system_index == _system:
		system_index = -1
	if system_index == _compare:
		return
	_compare = system_index
	_refresh()

func _refresh() -> void:
	if not visible or _system < 0:
		return
	var w: World = Sim.world
	var m := w.economy.market_at(_system)
	var was := _trade_ship
	_trade_ship = _docked_ship()
	if was != null and _trade_ship == null and not _any_ship_here():
		# The ship we traded with left (or was sold or lost), and none is here
		# (a ship in the yard for a refit or service still counts as here).
		visible = false
		ship_left.emit()
		return
	var live := _trade_ship != null
	_viewer.visible = live
	if live:
		_viewer.show_ship(_trade_ship)
	var known := w.known_prices(Sim.PLAYER, _system)
	var prices: PackedFloat64Array
	if live:
		prices = m.price
		_status.text = "Live prices: %s is docked here" % _trade_ship.name
		_status.add_theme_color_override("font_color", GREEN)
		if m.closed:
			_status.text = "The port is closed (strike): no trade until it reopens"
			_status.add_theme_color_override("font_color", AMBER)
	elif not known.is_empty():
		prices = known.price
		var age: int = w.day - int(known.day)
		_status.text = "Prices as of %s  ·  %s" % [Calendar.format(known.day, w.start_year),
			"today" if age == 0 else "%d day%s old" % [age, "" if age == 1 else "s"]]
		_status.add_theme_color_override("font_color", AMBER if age > 60 else MUTED)
	else:
		_status.text = "No price information: none of your ships has docked here."
		_status.add_theme_color_override("font_color", MUTED)
	var st := w.galaxy.systems[_system].settlement
	var general := (float(w.content.governments.get(st.government, {}).get("tariffs", {}).get("*", 0.0)) + m.tariff_add) \
		* m.tariff_mult * Influence.tariff_factor(w, Sim.PLAYER, _system)
	if general > 0.0:
		_status.text += "  ·  %d%% tariff on sales%s" % [roundi(general * 100.0),
			" (your concession)" if Influence.has_concession(w, Sim.PLAYER, _system) else ""]
	_grid.visible = live or not known.is_empty()
	_scroll.visible = _grid.visible
	_hold.visible = live
	_lot.visible = live
	if live:
		var used := {}
		for c in _trade_ship.cargo:
			var cls := Trading.commodity_class(w, c)
			used[cls] = used.get(cls, 0.0) + _trade_ship.cargo[c]
		var parts := PackedStringArray()
		var cap := w.fleet.capacity(_trade_ship)
		for cls in cap:
			# Contract freight takes hold space too.
			var taken: float = used.get(cls, 0.0) + Contracts.freight_reserved(w, _trade_ship, cls)
			parts.append("%s %s/%s t" % [cls, Format.thousands(roundi(taken)), Format.thousands(roundi(cap[cls]))])
		_hold.text = "%s  ·  %s" % [_trade_ship.name, "   ".join(parts) if not parts.is_empty() else "no cargo holds"]
	if not _grid.visible:
		_fit()
		return
	# The system to compare with, and what the player knows of its prices.
	var there := {}
	if _compare >= 0:
		there = w.known_prices(Sim.PLAYER, _compare)
		_vs_head.text = "vs %s%s" % [w.galaxy.systems[_compare].name, "" if not there.is_empty() else " (?)"]
		_vs_head.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
		_vs_head.tooltip_text = "Selling there: what a tonne bought here fetches after its tariff" \
			if not there.is_empty() else "No price information there: none of your ships has docked"
	else:
		_vs_head.text = "vs base"
		_vs_head.add_theme_color_override("font_color", MUTED)
		_vs_head.tooltip_text = ""
	for c in _cells.size():
		var row: Array = _cells[c]
		var ratio: float = prices[c] / m.base_price[c]
		var banned := Trading.is_banned(w, _system, c)
		var duty := Trading.tariff(w, _system, c, Sim.PLAYER)
		row[0].add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if banned else Color(0.86, 0.9, 0.97))
		row[1].text = Format.thousands(roundi(prices[c]))
		row[2].text = "%+d%%" % roundi((ratio - 1.0) * 100.0)
		# Live: an arrow for the move since last week.
		if live and m.history.size() >= 2:
			var before: float = m.history[m.history.size() - 2][c]
			if prices[c] > before * 1.005:
				row[2].text += " ▲"
			elif prices[c] < before * 0.995:
				row[2].text += " ▼"
		row[2].add_theme_color_override("font_color", GREEN if ratio < 0.97 else (AMBER if ratio > 1.03 else MUTED))
		if _compare >= 0:
			_compare_cell(w, row[2], c, prices[c], there)
		row[3].text = Format.thousands(roundi(m.stock[c])) if live else "—"
		if banned:
			row[4].text = "banned"
			row[4].add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		elif absf(duty - general) > 0.001:  # the general rate is in the status line
			row[4].text = "duty %d%%" % roundi(duty * 100.0)
			row[4].add_theme_color_override("font_color", AMBER)
		elif m.supply_rate[c] > m.demand_rate[c]:
			row[4].text = "export"
			row[4].add_theme_color_override("font_color", GREEN)
		elif m.demand_rate[c] > 0.0:
			row[4].text = "import"
			row[4].add_theme_color_override("font_color", AMBER)
		else:
			row[4].text = ""
		var series := PackedFloat32Array()
		if live:
			for week in m.history.slice(maxi(m.history.size() - WEEKS, 0)):
				series.append(week[c])
		row[1].series = series
		row[1].base = m.base_price[c]
		row[1].note = "Price history needs a ship docked here."
		var aboard: float = _trade_ship.cargo.get(c, 0.0) if live else 0.0
		row[5].text = "" if aboard < 0.5 else "%s t @ %s" % [Format.thousands(roundi(aboard)),
			Format.thousands(roundi(_trade_ship.cargo_cost[c] / aboard))]
		# Never hide grid cells: a GridContainer would shift the rest into the
		# wrong columns. Without a ship here the buttons are just invisible.
		for k in [6, 7]:
			row[k].modulate.a = 1.0 if live else 0.0
			row[k].mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
		row[6].disabled = not live or banned or m.closed or Trading.free_space(w, _trade_ship, c) < 1.0 or m.stock[c] < 1.0
		row[7].disabled = not live or banned or m.closed or aboard < 0.5
	_fit()

## "vs <hovered system>": what a tonne bought here (at `here`) sells for
## there after its tariff; "—" without prices, "banned" where it can't be
## sold, "not traded" where the market doesn't deal in it.
func _compare_cell(w: World, cell: Label, c: int, here: float, there: Dictionary) -> void:
	var m := w.economy.market_at(_compare)
	if there.is_empty() or m == null:
		cell.text = "—"
		cell.add_theme_color_override("font_color", MUTED)
	elif Trading.is_banned(w, _compare, c):
		cell.text = "banned"
		cell.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif not m.is_traded(c):
		cell.text = "not traded"
		cell.add_theme_color_override("font_color", MUTED)
	else:
		var net: float = float(there.price[c]) * (1.0 - Trading.tariff(w, _compare, c, Sim.PLAYER))
		var gain := net / here - 1.0
		cell.text = "%+d%%" % roundi(gain * 100.0)
		cell.add_theme_color_override("font_color", GREEN if gain > 0.03 else (Color(1.0, 0.45, 0.4) if gain < -0.03 else MUTED))

## The selected player ship if it is docked here, else any docked here.
func _docked_ship() -> Ship:
	var w: World = Sim.world
	var chosen: Ship = null
	for s in w.ships_of(Sim.PLAYER):
		if s.status == Ship.Status.DOCKED and s.system == _system:
			if s.id == ship_id:
				return s
			if chosen == null:
				chosen = s
	return chosen

## Any player ship at this port, docked or in its yard.
func _any_ship_here() -> bool:
	return Sim.world.ships_of(Sim.PLAYER).any(func(s): return s.system == _system and s.status != Ship.Status.TRAVELING)

func _trade(commodity_id: String, buying: bool) -> void:
	if _trade_ship == null:
		return
	var lot: float = LOTS[_lot.selected]
	var c: int = Sim.world.economy.index_of(commodity_id)
	if buying:
		Sim.buy_cargo(_trade_ship.id, commodity_id, lot if lot > 0.0 else 1e9)
	else:
		var aboard: float = _trade_ship.cargo.get(c, 0.0)
		Sim.sell_cargo(_trade_ship.id, commodity_id, minf(lot, aboard) if lot > 0.0 else aboard)

## Back to content size (Controls grow but never shrink by themselves).
func _fit() -> void:
	(func():
		if not visible:
			return
		if _scroll.visible:
			Fit.cap(self, _scroll, _grid, bottom_limit)
		offset_right = offset_left
		offset_bottom = offset_top).call_deferred()

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	# Compact: a row per good must fit on screen.
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBox = get_theme_stylebox(state, "Button").duplicate()
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(action)
	return b

func _label(text: String, color: Color, font_size: int, font: Font = null,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	if font:
		l.add_theme_font_override("font", font)
	return l
