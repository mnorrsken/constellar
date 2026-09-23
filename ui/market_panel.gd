class_name MarketPanel
extends PanelContainer
## Temporary market view (the real one arrives in Milestone 9): every good's
## price, change against its base price, stock, whether the settlement makes
## or needs it, and a 26-week sparkline. Updates every game day.

const WEEKS := 26
const GREEN := Color(0.45, 0.85, 0.55)
const AMBER := Color(0.98, 0.72, 0.3)
const MUTED := Color(0.55, 0.62, 0.74)

var _title := Label.new()
var _grid := GridContainer.new()
var _market: Market
var _cells: Array = []  # per commodity: [price, change, stock, tag, sparkline]

func _ready() -> void:
	visible = false
	offset_left = 28
	offset_top = 100
	offset_bottom = 100  # zero height: grows to fit
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 22)
	var sub := Label.new()
	sub.text = "credits per tonne  ·  M to close"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", MUTED)
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 2)
	for h in ["Good", "Price", "vs base", "Stock", "", "26 weeks"]:
		_grid.add_child(_label(h, MUTED, 12))
	var ids: PackedStringArray = Sim.world.economy.commodity_ids
	for id in ids:
		_grid.add_child(_label(Defs.commodities[id].name, Color(0.86, 0.9, 0.97), 14))
		var price := _label("", Color.WHITE, 14, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT)
		var change := _label("", Color.WHITE, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT)
		var stock := _label("", MUTED, 13, Fonts.MONO, HORIZONTAL_ALIGNMENT_RIGHT)
		var tag := _label("", MUTED, 12)
		var spark := Sparkline.new()
		for c in [price, change, stock, tag, spark]:
			_grid.add_child(c)
		_cells.append([price, change, stock, tag, spark])
	for c in [_title, sub, _grid]:
		box.add_child(c)
	add_child(box)
	Events.day_passed.connect(func(_d): _refresh())

## Shows the market of a system, or hides the panel for an uninhabited one.
func show_system(s: StarSystem) -> void:
	_market = Sim.world.economy.market_at(s.index)
	if _market == null or not Sim.player().is_known(s.index):
		visible = false
		return
	_title.text = "Market  ·  %s" % s.settlement.name
	visible = true
	_refresh()
	(func(): offset_bottom = offset_top).call_deferred()

func _refresh() -> void:
	if not visible or _market == null:
		return
	var m := _market
	for c in _cells.size():
		var row: Array = _cells[c]
		var ratio := m.price[c] / m.base_price[c]
		row[0].text = Format.thousands(roundi(m.price[c]))
		row[1].text = "%+d%%" % roundi((ratio - 1.0) * 100.0)
		row[1].add_theme_color_override("font_color", GREEN if ratio < 0.97 else (AMBER if ratio > 1.03 else MUTED))
		row[2].text = Format.thousands(roundi(m.stock[c]))
		if m.supply_rate[c] > m.demand_rate[c]:
			row[3].text = "export"
			row[3].add_theme_color_override("font_color", GREEN)
		elif m.demand_rate[c] > 0.0:
			row[3].text = "import"
			row[3].add_theme_color_override("font_color", AMBER)
		else:
			row[3].text = ""
		var series := PackedFloat32Array()
		for week in m.history.slice(maxi(m.history.size() - WEEKS, 0)):
			series.append(week[c])
		row[4].set_data(series, m.base_price[c])

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
