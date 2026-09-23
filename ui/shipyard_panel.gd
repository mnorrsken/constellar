class_name ShipyardPanel
extends PanelContainer
## Shipyard at one system: hulls for sale (buy), and refit or sell for the
## player's ships docked there. Opened from the system card; Esc closes.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const AMBER := Color(0.98, 0.72, 0.3)

var system := -1

var _title := Label.new()
var _cash := Label.new()
var _hulls := GridContainer.new()
var _refits := VBoxContainer.new()

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
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cash.add_theme_font_override("font", Fonts.MONO)
	_cash.add_theme_color_override("font_color", AMBER)
	var close := Button.new()
	close.text = "✕  Esc"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	for c in [_title, _cash, close]:
		head.add_child(c)
	_hulls.columns = 7
	_hulls.add_theme_constant_override("h_separation", 18)
	_hulls.add_theme_constant_override("v_separation", 4)
	for c in [head, _section("New ships"), _hulls, HSeparator.new(), _section("Your ships here"), _refits]:
		box.add_child(c)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.fleet_changed.connect(_refresh)

func open(system_index: int) -> void:
	system = system_index
	var s: StarSystem = Sim.galaxy.systems[system_index]
	_title.text = "Shipyard  ·  %s  (%s)" % [s.settlement.name, s.name]
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not visible:
		return
	var world: World = Sim.world
	var fleet := world.fleet
	_cash.text = "%s cr   " % Format.thousands(roundi(Sim.player().cash))
	for child in _hulls.get_children():
		child.queue_free()
	for h in ["Hull", "Class", "Cargo", "Speed", "Jump", "Price", ""]:
		_hulls.add_child(_cell(h, MUTED, 13))
	for id in fleet.hulls_for_sale(system, world.year()):
		var h: Dictionary = Defs.world_content.hulls[id]
		var price := _fitted_price(h)
		_hulls.add_child(_cell(h.name, Color(0.86, 0.9, 0.97), 15))
		_hulls.add_child(_cell(h["class"], MUTED, 14))
		_hulls.add_child(_cell("%d × %d t" % [h.slots, h.slot_tonnes], Color.WHITE, 14, true))
		_hulls.add_child(_cell("%.2f ly/d" % h.speed, Color.WHITE, 14, true))
		_hulls.add_child(_cell("%.0f ly" % h.jump_range, Color.WHITE, 14, true))
		_hulls.add_child(_cell("%s cr" % Format.thousands(roundi(price)), AMBER, 14, true))
		var buy := Button.new()
		buy.text = "Buy"
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = Sim.player().cash < price
		buy.pressed.connect(func(): Sim.buy_ship(id, system))
		_hulls.add_child(buy)
	for child in _refits.get_children():
		child.queue_free()
	var here := world.ships_of(Sim.PLAYER).filter(
		func(s): return s.system == system and s.status != Ship.Status.TRAVELING)
	if here.is_empty():
		_refits.add_child(_cell("None of your ships is docked here.", MUTED, 14))
	for s in here:
		_refits.add_child(_refit_row(s))
	(func(): reset_size()).call_deferred()

func _refit_row(s: Ship) -> Control:
	var fleet: Fleet = Sim.world.fleet
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var name_label := _cell("%s  ·  %s" % [s.name, fleet.hull_def(s).name], Color(0.86, 0.9, 0.97), 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var quote := _cell("", MUTED, 14, true)
	head.add_child(quote)
	var refit := Button.new()
	refit.text = "Refit"
	refit.focus_mode = Control.FOCUS_NONE
	var sell := Button.new()
	sell.text = "Sell  %s cr" % Format.thousands(roundi(fleet.sale_value(s)))
	sell.focus_mode = Control.FOCUS_NONE
	sell.pressed.connect(func(): Sim.sell_ship(s.id))
	head.add_child(refit)
	head.add_child(sell)
	row.add_child(head)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	var pickers: Array[OptionButton] = []
	var module_ids: Array = Defs.world_content.modules.keys().filter(func(m): return fleet.module_allowed(s.hull, m))
	for i in s.modules.size():
		var pick := OptionButton.new()
		pick.focus_mode = Control.FOCUS_NONE
		for m in module_ids:
			pick.add_item(Defs.world_content.modules[m].name)
		pick.select(module_ids.find(s.modules[i]))
		pickers.append(pick)
		slots.add_child(pick)
	row.add_child(slots)
	var chosen := func() -> Array:
		return pickers.map(func(p): return module_ids[p.selected])
	var update := func() -> void:
		var q := fleet.refit_quote(s, chosen.call())
		quote.text = "no changes" if q.changed == 0 else "%s cr  ·  %d days" % [Format.thousands(roundi(q.cost)), q.days]
		refit.disabled = q.changed == 0 or s.status != Ship.Status.DOCKED
	for p in pickers:
		p.item_selected.connect(func(_i): update.call())
	refit.pressed.connect(func(): Sim.refit_ship(s.id, chosen.call()))
	if s.status == Ship.Status.REFITTING:
		for p in pickers:
			p.disabled = true
		sell.disabled = true
	update.call()
	return row

func _fitted_price(h: Dictionary) -> float:
	var p := float(h.price)
	for m in h.get("default_modules", []):
		p += float(Defs.world_content.modules[m].price)
	return p

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
