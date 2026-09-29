class_name FinancePanel
extends PanelContainer
## The finance screen (L): cash and loan with borrow/repay; company value,
## the victory goal (picked at New game) with its progress, and a
## bankruptcy warning; the ledger by
## category for the last three months (cash); charts of the company's
## monthly profit and every ship's (up to two years; goods count when sold,
## see Company.profit); and a ship table with age, condition, last month's
## profit and why a ship made a loss.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const AMBER := Color(0.98, 0.72, 0.3)
const CATEGORIES := ["sales", "purchases", "contracts", "penalties", "tariffs", "fuel", "docking", "crew",
	"maintenance", "insurance", "repairs", "interest", "influence", "ships"]
const STEP := 100000.0
const CHART_MONTHS := 24
## Line colours for ships in the profit chart.
const SHIP_COLORS := [Color(0.35, 0.85, 1.0), Color(0.98, 0.72, 0.3), Color(0.75, 0.55, 1.0),
	Color(0.45, 0.9, 0.55), Color(1.0, 0.5, 0.6), Color(0.9, 0.9, 0.5), Color(0.5, 0.7, 1.0)]

var _title := Label.new()
var _money := Label.new()
var _value := Label.new()
var _goal := Label.new()
var _goal_status := Label.new()
var _warning := Label.new()
var _grid := GridContainer.new()
var _net_chart := Chart.new()
var _ship_chart := Chart.new()
var _legend := HFlowContainer.new()
var _ships := GridContainer.new()

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
	var borrow := _button("Borrow 100,000", func(): Sim.take_loan(STEP))
	var repay := _button("Repay 100,000", func(): Sim.repay_loan(STEP))
	var close := _button("✕  Esc", close_panel)
	for c in [_title, borrow, repay, close]:
		head.add_child(c)
	_money.add_theme_font_override("font", Fonts.MONO)
	_money.add_theme_font_size_override("font_size", 15)
	_money.add_theme_color_override("font_color", AMBER)
	for l in [_value, _goal, _goal_status]:
		l.add_theme_font_override("font", Fonts.MONO)
		l.add_theme_font_size_override("font_size", 15)
	_value.add_theme_color_override("font_color", TEXT)
	_goal_status.add_theme_color_override("font_color", MUTED)
	_warning.add_theme_font_size_override("font_size", 15)
	_warning.add_theme_color_override("font_color", RED)
	_goal.add_theme_color_override("font_color", TEXT)
	var standing := HBoxContainer.new()
	standing.add_theme_constant_override("separation", 18)
	for c in [_value, _goal, _goal_status]:
		standing.add_child(c)
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 2)
	var charts := VBoxContainer.new()
	charts.add_theme_constant_override("separation", 6)
	_ship_chart.custom_minimum_size = Vector2(560, 170)
	_net_chart.custom_minimum_size = Vector2(560, 150)
	_legend.add_theme_constant_override("h_separation", 14)
	for c in [_section("Profit per month  (goods count when sold)"), _net_chart, _section("Profit per ship  (3-month average)"), _ship_chart, _legend]:
		charts.add_child(c)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	top.add_child(_grid)
	top.add_child(VSeparator.new())
	top.add_child(charts)
	_ships.columns = 6
	_ships.add_theme_constant_override("h_separation", 22)
	_ships.add_theme_constant_override("v_separation", 2)
	for c in [head, _money, standing, _warning, HSeparator.new(), top, HSeparator.new(), _ships]:
		box.add_child(c)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.day_passed.connect(func(_d): _refresh())
	Events.fleet_changed.connect(_refresh)
	Events.influence_changed.connect(_refresh)

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
	_title.text = "Finances  ·  %s" % p.name
	_money.text = "Cash %s cr     Loan %s of %s cr at %d%% a year     Fuel and servicing on credit down to -%s cr" % [
		Format.thousands(roundi(p.cash)), Format.thousands(roundi(p.loan)),
		Format.thousands(roundi(p.loan_max)), roundi(p.interest_per_year * 100.0), Format.thousands(roundi(p.overdraft))]
	_value.text = "Company value %s cr" % Format.thousands(roundi(Goals.company_value(w, Sim.PLAYER)))
	_value.tooltip_text = "Cash minus the loan, plus what your ships would sell for and what their cargo cost"
	var g := Goals.progress(w, Sim.PLAYER)
	var target: Dictionary = w.content.balance.get("goals", {}).get(g.goal, {})
	match g.goal:
		"value":
			_goal.text = "Goal: company value %s cr" % Format.money_short(float(target.get("target", 0)))
		"prince":
			_goal.text = "Goal: %s (patron of %d systems)" % [g.name, int(target.get("patrons", 0))]
		_:
			_goal.text = "No goal: sandbox"
	match g.goal:
		"value":
			_goal_status.text = "%s of %s cr" % [Format.money_short(g.current), Format.money_short(g.target)]
		"prince":
			_goal_status.text = "patron of %d of %d" % [g.current, g.target]
		_:
			_goal_status.text = ""
	if p.goal_day >= 0:
		_goal_status.text = "reached %s" % Calendar.format(p.goal_day, w.start_year)
	_goal_status.add_theme_color_override("font_color", GREEN if p.goal_day >= 0 else MUTED)
	var limit := int(w.content.balance.get("bankruptcy_months", 3))
	_warning.visible = p.months_in_red > 0 or p.bankrupt
	_warning.text = "Bankrupt." if p.bankrupt else \
		"No cash and the loan is maxed out: %d of %d months in the red before bankruptcy." % [p.months_in_red, limit]
	var now := w.month()
	_fill_ledger(w, p, [now - 2, now - 1, now])
	var first := maxi(now - CHART_MONTHS + 1, 0)
	var months := range(first, now + 1)
	var labels := PackedStringArray()
	for m in months:
		# "Mar", with the year at each January.
		labels.append(Calendar.month_name(m, w.start_year).left(3) + ("" if m % 12 != 0 else " " + str(w.start_year + m / 12)))
	_net_chart.set_bars(months.map(func(m): return p.profit(m)), labels)
	var lines := []
	for c in _legend.get_children():
		_legend.remove_child(c)
		c.queue_free()
	var k := 0
	for s in w.ships_of(Sim.PLAYER):
		var color: Color = SHIP_COLORS[k % SHIP_COLORS.size()]
		k += 1
		# Trips often span months: a 3-month average shows the trend.
		var values := []
		for m in months:
			var sum := 0.0
			for back in 3:
				sum += p.profit(m - back, s.id)
			values.append(sum / 3.0 if m >= _month_of(s.bought_day) else 0.0)
		lines.append({"name": s.name, "color": color, "values": values})
		_legend.add_child(_cell("●  %s" % s.name, color))
	_ship_chart.set_lines(lines, labels)
	_fill_ships(w, p, now)
	Fit.center.call_deferred(self)

func _fill_ledger(w: World, p: Company, months: Array) -> void:
	_clear(_grid)
	_grid.add_child(_cell("", MUTED))
	for m in months:
		_grid.add_child(_cell(Calendar.month_name(m, w.start_year) if m >= 0 else "", MUTED, true))
	var totals := [0.0, 0.0, 0.0]
	for cat in CATEGORIES:
		_grid.add_child(_cell(cat.capitalize(), TEXT))
		for k in months.size():
			var v: float = p.ledger.get(months[k], {}).get(cat, 0.0)
			totals[k] += v
			_grid.add_child(_money_cell(v))
	_grid.add_child(_cell("Net", Color.WHITE))
	for v in totals:
		_grid.add_child(_money_cell(v))

func _fill_ships(w: World, p: Company, now: int) -> void:
	_clear(_ships)
	for h in ["Ship", "Age", "Condition", "Last month", "Last 12 months", "Why it made a loss last month"]:
		_ships.add_child(_cell(h, MUTED))
	for s in w.ships_of(Sim.PLAYER):
		var year_total := 0.0
		for m in range(now - 11, now + 1):
			year_total += p.profit(m, s.id)
		var last := p.profit(now - 1, s.id)
		_ships.add_child(_cell("%s  ·  %s" % [s.name, w.fleet.hull_def(s).name], TEXT))
		_ships.add_child(_cell("%d yr" % floori(Aging.age_years(w, s)), TEXT, true))
		_ships.add_child(_cell("%d%%" % roundi(s.condition * 100.0), GREEN if s.condition > 0.7
			else (AMBER if s.condition > 0.45 else RED), true))
		_ships.add_child(_money_cell(last))
		_ships.add_child(_money_cell(year_total))
		_ships.add_child(_cell(Trading.loss_reason(p, s.id, now - 1), AMBER))

static func _month_of(day: int) -> int:
	return Calendar.month_index(maxi(day, 0))

func _clear(grid: Container) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()

func _money_cell(v: float) -> Label:
	var l := _cell("" if absf(v) < 0.5 else Format.thousands(roundi(v)), GREEN if v > 0.0 else RED, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(96, 0)
	return l

func _section(text: String) -> Label:
	var l := _cell(text.to_upper(), MUTED)
	l.add_theme_font_size_override("font_size", 12)
	return l

func _cell(text: String, color: Color, mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	if mono:
		l.add_theme_font_override("font", Fonts.MONO)
	return l

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b
