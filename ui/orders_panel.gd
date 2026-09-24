class_name OrdersPanel
extends PanelContainer
## Route orders for one ship (Transport Tycoon style): a looping list of
## stops. Each stop: sell all cargo, buy one good (0 t = fill the hold),
## wait for a full load, or auto-trade (needs an auto-trader module). The
## ship's routing (shortest or safest) and insurance are set here too.
## Every edit is applied at once; a running route restarts with the change.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)

var ship_id := -1
## System the "Add stop" button adds (the map selection), -1 = none.
var add_system := -1

var _title := Label.new()
var _state := Label.new()
var _run := Button.new()
var _stops := VBoxContainer.new()
var _add := Button.new()
var _safest := CheckBox.new()
var _insured := CheckBox.new()

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(760, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_run.focus_mode = Control.FOCUS_NONE
	_run.pressed.connect(_toggle_run)
	var close := Button.new()
	close.text = "✕  Esc"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_panel)
	for c in [_title, _state, _run, close]:
		head.add_child(c)
	_stops.add_theme_constant_override("separation", 8)
	_add.focus_mode = Control.FOCUS_NONE
	_add.pressed.connect(_add_stop)
	var hint := Label.new()
	hint.text = "Select a charted system on the map, then add it as a stop. The route loops."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED)
	var ship_row := HBoxContainer.new()
	ship_row.add_theme_constant_override("separation", 18)
	_safest.text = "Safest routes (around dangerous lanes)"
	_safest.focus_mode = Control.FOCUS_NONE
	_safest.toggled.connect(func(on): Sim.set_routing(ship_id, on))
	_insured.focus_mode = Control.FOCUS_NONE
	_insured.toggled.connect(func(on): Sim.set_insurance(ship_id, on))
	_insured.tooltip_text = "Pays for cargo, repairs and the ship itself after a raid or a loss.\nThe premium follows the risk the ship ran last month."
	ship_row.add_child(_safest)
	ship_row.add_child(_insured)
	for c in [head, ship_row, _stops, _add, hint]:
		box.add_child(c)
	add_child(box)
	Events.fleet_changed.connect(_refresh)

func open(id: int, selected_system: int) -> void:
	ship_id = id
	add_system = selected_system
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func set_add_system(i: int) -> void:
	add_system = i
	if visible:
		_refresh()

func _ship() -> Ship:
	return Sim.world.fleet.get_ship(ship_id)

func _refresh() -> void:
	if not visible:
		return
	var s := _ship()
	if s == null:
		close_panel()
		return
	var w: World = Sim.world
	_title.text = "Route orders  ·  %s" % s.name
	_state.text = "running" if s.orders_active else "stopped"
	_state.add_theme_color_override("font_color", Color(0.45, 0.85, 0.55) if s.orders_active else MUTED)
	_run.text = "Stop route" if s.orders_active else "Start route"
	_run.disabled = s.orders.size() < 2 and not s.orders_active
	_safest.set_pressed_no_signal(s.safe_routing)
	_insured.set_pressed_no_signal(s.insured)
	_insured.text = "Insured  (about %s cr a month)" % Format.thousands(roundi(Danger.premium(w, s)))
	for child in _stops.get_children():
		child.queue_free()
	for i in s.orders.size():
		_stops.add_child(_stop_row(s, i))
	var can_add := add_system >= 0 and Sim.player().is_known(add_system) \
		and w.economy.market_at(add_system) != null
	_add.disabled = not can_add
	_add.text = "Add stop: %s" % (w.galaxy.systems[add_system].name if add_system >= 0 else "select a system")
	(func(): reset_size()).call_deferred()

func _stop_row(s: Ship, i: int) -> Control:
	var w: World = Sim.world
	var stop: Dictionary = s.orders[i]
	var sys: StarSystem = w.galaxy.systems[int(stop.system)]
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	var name := Label.new()
	var current := s.orders_active and i == s.order_index
	name.text = "%s%d.  %s  ·  %s" % ["▶ " if current else "", i + 1, sys.name,
		sys.settlement.name if sys.settlement else "no market"]
	name.add_theme_font_size_override("font_size", 16)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	for pair in [["↑", -1], ["↓", 1]]:
		var move := Button.new()
		move.text = pair[0]
		move.focus_mode = Control.FOCUS_NONE
		move.disabled = i + pair[1] < 0 or i + pair[1] >= s.orders.size()
		move.pressed.connect(func(): _move(i, pair[1]))
		head.add_child(move)
	var remove := Button.new()
	remove.text = "✕"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func(): _edit(func(o): o.remove_at(i)))
	head.add_child(remove)
	box.add_child(head)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 14)
	var sell := _check("Sell all cargo", stop.get("sell_all", true),
		func(on): _edit(func(o): o[i].sell_all = on))
	var wait := _check("Wait for full load", stop.get("wait_full", false),
		func(on): _edit(func(o): o[i].wait_full = on))
	var auto := _check("Auto-trade", stop.get("auto", false),
		func(on): _edit(func(o): o[i].auto = on))
	auto.disabled = not ("auto_trader" in s.modules)
	auto.tooltip_text = "Buys the best known margin for the next stop. Needs an auto-trader module."
	var buy := OptionButton.new()
	buy.focus_mode = Control.FOCUS_NONE
	buy.add_item("Buy: nothing")
	var ids: PackedStringArray = w.economy.commodity_ids
	var holds := w.fleet.capacity(s)
	for id in ids:
		var carry: bool = holds.get(Defs.commodities[id].cargo_class, 0.0) > 0.0
		buy.add_item("Buy: %s%s" % [Defs.commodities[id].name, "" if carry else "  (no hold)"])
	var buys: Array = stop.get("buy", [])
	buy.select(0 if buys.is_empty() else ids.find(buys[0].commodity) + 1)
	buy.disabled = stop.get("auto", false)
	buy.item_selected.connect(func(k): _edit(func(o):
		o[i].buy = [] if k == 0 else [{"commodity": ids[k - 1], "amount": 0}]))
	for c in [sell, buy, wait, auto]:
		opts.add_child(c)
	box.add_child(opts)
	panel.add_child(box)
	return panel

## Applies a change to a copy of the orders; restarts the route if it ran.
func _edit(change: Callable) -> void:
	var s := _ship()
	var was_running := s.orders_active
	var orders := s.orders.duplicate(true)
	change.call(orders)
	Sim.set_orders(s.id, orders)
	if was_running and orders.size() >= 2:
		Sim.start_orders(s.id)

func _move(i: int, by: int) -> void:
	_edit(func(o):
		var stop = o[i]
		o.remove_at(i)
		o.insert(i + by, stop))

func _add_stop() -> void:
	var w: World = Sim.world
	var sell := w.economy.market_at(add_system) != null
	_edit(func(o): o.append({"system": add_system, "sell_all": sell, "buy": [], "wait_full": false, "auto": false}))

func _toggle_run() -> void:
	var s := _ship()
	if s.orders_active:
		Sim.stop_orders(s.id)
	else:
		Sim.start_orders(s.id)

func _check(text: String, on: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(action)
	return c
