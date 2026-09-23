class_name MarketPanel
extends PanelContainer
## Market of the selected system as the player knows it: live while one of
## their ships is docked there (with buy/sell buttons for that ship), else
## the last prices a ship saw, with their age, else nothing. The full market
## screen comes in Milestone 9.

const WEEKS := 26
const GREEN := Color(0.45, 0.85, 0.55)
const AMBER := Color(0.98, 0.72, 0.3)
const MUTED := Color(0.55, 0.62, 0.74)
const LOTS := [0.0, 500.0, 100.0]  # 0 = as much as possible

## The ship the player has selected (trades use it when docked here).
var ship_id := -1

var _title := Label.new()
var _status := Label.new()
var _hold := Label.new()
var _lot := OptionButton.new()
var _grid := GridContainer.new()
var _system := -1
var _cells: Array = []  # per commodity: [name, price, change, stock, tag, spark, aboard, buy, sell]
var _trade_ship: Ship

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
	for l in ["Lot: all that fits", "Lot: 500 t", "Lot: 100 t"]:
		_lot.add_item(l)
	_lot.focus_mode = Control.FOCUS_NONE
	var trade_row := HBoxContainer.new()
	trade_row.add_theme_constant_override("separation", 12)
	_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trade_row.add_child(_hold)
	trade_row.add_child(_lot)
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 1)
	for h in ["Good", "Price", "vs base", "Stock", "", "26 weeks", "Aboard", "", ""]:
		_grid.add_child(_label(h, MUTED, 12))
	var ids: PackedStringArray = Sim.world.economy.commodity_ids
	for c in ids.size():
		var id := ids[c]
		var row := [
			_label(Defs.commodities[id].name, Color(0.86, 0.9, 0.97), 14),
			_label("", Color.WHITE, 14, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_label("", Color.WHITE, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_label("", MUTED, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_label("", MUTED, 12),
			Sparkline.new(),
			_label("", AMBER, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT),
			_button("Buy", func(): _trade(id, true)),
			_button("Sell", func(): _trade(id, false)),
		]
		for cell in row:
			_grid.add_child(cell)
		_cells.append(row)
	var close := _label("M to close", MUTED, 12)
	for c in [_title, _status, trade_row, _grid, close]:
		box.add_child(c)
	add_child(box)
	Events.day_passed.connect(func(_d): _refresh())
	Events.fleet_changed.connect(_refresh)
	Events.company_changed.connect(func(_c): _refresh())

## Shows the market of a system, or hides the panel where there is none.
func show_system(s: StarSystem) -> void:
	if Sim.world.economy.market_at(s.index) == null or not Sim.player().is_known(s.index):
		visible = false
		_system = -1
		return
	_system = s.index
	_title.text = "Market  ·  %s" % s.settlement.name
	visible = true
	_refresh()

func _refresh() -> void:
	if not visible or _system < 0:
		return
	var w: World = Sim.world
	var m := w.economy.market_at(_system)
	_trade_ship = _docked_ship()
	var live := _trade_ship != null
	var known := w.known_prices(Sim.PLAYER, _system)
	var prices: PackedFloat64Array
	if live:
		prices = m.price
		_status.text = "Live prices: %s is docked here" % _trade_ship.name
		_status.add_theme_color_override("font_color", GREEN)
	elif not known.is_empty():
		prices = known.price
		var age: int = w.day - int(known.day)
		_status.text = "Prices as of %s  ·  %s" % [Calendar.format(known.day, w.start_year),
			"today" if age == 0 else "%d day%s old" % [age, "" if age == 1 else "s"]]
		_status.add_theme_color_override("font_color", AMBER if age > 60 else MUTED)
	else:
		_status.text = "No price information: none of your ships has docked here."
		_status.add_theme_color_override("font_color", MUTED)
	_grid.visible = live or not known.is_empty()
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
			parts.append("%s %s/%s t" % [cls, Format.thousands(roundi(used.get(cls, 0.0))), Format.thousands(roundi(cap[cls]))])
		_hold.text = "%s  ·  %s" % [_trade_ship.name, "   ".join(parts) if not parts.is_empty() else "no cargo holds"]
	if not _grid.visible:
		_fit()
		return
	for c in _cells.size():
		var row: Array = _cells[c]
		var ratio: float = prices[c] / m.base_price[c]
		row[1].text = Format.thousands(roundi(prices[c]))
		row[2].text = "%+d%%" % roundi((ratio - 1.0) * 100.0)
		row[2].add_theme_color_override("font_color", GREEN if ratio < 0.97 else (AMBER if ratio > 1.03 else MUTED))
		row[3].text = Format.thousands(roundi(m.stock[c])) if live else "—"
		if m.supply_rate[c] > m.demand_rate[c]:
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
		row[5].set_data(series, m.base_price[c])
		var aboard: float = _trade_ship.cargo.get(c, 0.0) if live else 0.0
		row[6].text = "" if aboard < 0.5 else "%s t @ %s" % [Format.thousands(roundi(aboard)),
			Format.thousands(roundi(_trade_ship.cargo_cost[c] / aboard))]
		# Never hide grid cells: a GridContainer would shift the rest into the
		# wrong columns. Without a ship here the buttons are just invisible.
		for k in [7, 8]:
			row[k].modulate.a = 1.0 if live else 0.0
			row[k].mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
		row[7].disabled = not live or Trading.free_space(w, _trade_ship, c) < 1.0 or m.stock[c] < 1.0
		row[8].disabled = not live or aboard < 0.5
	_fit()

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
		offset_right = offset_left
		offset_bottom = offset_top).call_deferred()

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
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
