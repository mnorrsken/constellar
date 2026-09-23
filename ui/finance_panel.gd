class_name FinancePanel
extends PanelContainer
## The ledger (L): this month and the last two by category, net, and each
## ship's result; cash and loan with borrow/repay. Charts come in
## Milestone 9.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const CATEGORIES := ["sales", "purchases", "fuel", "docking", "crew", "maintenance", "interest", "ships"]
const STEP := 100000.0

var _title := Label.new()
var _money := Label.new()
var _grid := GridContainer.new()
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
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 28)
	_ships.columns = 4
	_ships.add_theme_constant_override("h_separation", 28)
	for c in [head, _money, HSeparator.new(), _grid, HSeparator.new(), _ships]:
		box.add_child(c)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.day_passed.connect(func(_d): _refresh())
	Events.fleet_changed.connect(_refresh)

func open() -> void:
	visible = true
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
	_money.text = "Cash %s cr     Loan %s of %s cr at %d%% a year" % [
		Format.thousands(roundi(p.cash)), Format.thousands(roundi(p.loan)),
		Format.thousands(roundi(p.loan_max)), roundi(p.interest_per_year * 100.0)]
	var now := w.month()
	var months := [now - 2, now - 1, now]
	for c in _grid.get_children():
		c.queue_free()
	_grid.add_child(_cell("", MUTED))
	for m in months:
		_grid.add_child(_cell(Calendar.month_name(m, w.start_year) if m >= 0 else "", MUTED, true))
	var totals := [0.0, 0.0, 0.0]
	for cat in CATEGORIES:
		_grid.add_child(_cell(cat.capitalize(), Color(0.86, 0.9, 0.97)))
		for k in months.size():
			var v: float = p.ledger.get(months[k], {}).get(cat, 0.0)
			totals[k] += v
			_grid.add_child(_money_cell(v))
	_grid.add_child(_cell("Net", Color.WHITE))
	for v in totals:
		_grid.add_child(_money_cell(v))
	for c in _ships.get_children():
		c.queue_free()
	_ships.add_child(_cell("Ship", MUTED))
	for m in months:
		_ships.add_child(_cell(Calendar.month_name(m, w.start_year) if m >= 0 else "", MUTED, true))
	for s in w.ships_of(Sim.PLAYER):
		_ships.add_child(_cell(s.name, Color(0.86, 0.9, 0.97)))
		for m in months:
			_ships.add_child(_money_cell(p.ship_ledger.get(s.id, {}).get(m, 0.0)))
	(func(): reset_size()).call_deferred()

func _money_cell(v: float) -> Label:
	var l := _cell("" if absf(v) < 0.5 else Format.thousands(roundi(v)), GREEN if v > 0.0 else RED, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(120, 0)
	return l

func _cell(text: String, color: Color, mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
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
