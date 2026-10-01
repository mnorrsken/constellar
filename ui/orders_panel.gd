class_name OrdersPanel
extends PanelContainer
## Route orders for one ship (Transport Tycoon style): a looping list of
## stops. Each stop: sell all cargo, buy a list of goods in order (each a
## set number of tonnes, or "fill" for the rest of its hold), auto-trade
## (needs an auto-trader module), or get serviced when worn (at a shipyard). The ship's routing (shortest or
## safest) and insurance are set here too. Stops are added from a list of
## the charted ports nearest the last stop (and the one selected on the
## map), or by typing a name with suggestions from every charted port. A
## stop's name is a link: it closes the panel and shows it on the map.
## Every edit is applied at once; a running route restarts with the change.

signal closed
signal system_requested(system_index: int)

const MUTED := Color(0.55, 0.62, 0.74)
## Ports in the "nearest" list, and suggestions shown while typing.
const NEAREST := 12
const SUGGESTIONS := 8

var ship_id := -1
## The system selected on the map (offered first in the add list), -1 = none.
var add_system := -1

var _title := Label.new()
var _state := Label.new()
var _run := Button.new()
var _stops := VBoxContainer.new()
var _nearest := OptionButton.new()
var _search := LineEdit.new()
var _matches := ItemList.new()
## System index per _nearest item (-1 = the placeholder) and per _matches row.
var _nearest_ids: Array[int] = []
var _match_ids: Array[int] = []
## What the stops were built for (see _refresh).
var _key: Variant = null
var _safest := CheckBox.new()
var _insured := CheckBox.new()
var _viewer := ShipViewer.new()

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
	_nearest.focus_mode = Control.FOCUS_NONE
	_nearest.item_selected.connect(func(k):
		if _nearest_ids[k] >= 0:
			_add_stop(_nearest_ids[k]))
	_search.placeholder_text = "Find a charted port by name…"
	_search.custom_minimum_size = Vector2(300, 0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _suggest())
	_search.text_submitted.connect(func(_t):
		if not _match_ids.is_empty():
			_add_stop(_match_ids[0]))
	_matches.auto_height = true
	_matches.focus_mode = Control.FOCUS_NONE
	_matches.visible = false
	_matches.item_clicked.connect(func(k, _at, _button): _add_stop(_match_ids[k]))
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	add_row.add_child(_nearest)
	add_row.add_child(_search)
	var hint := Label.new()
	hint.text = "Add a stop from the nearest ports, or type a name (Enter adds the first match). The route loops."
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
	_viewer.custom_minimum_size = Vector2(200, 80)
	var switches := VBoxContainer.new()
	switches.alignment = BoxContainer.ALIGNMENT_CENTER
	switches.add_child(_safest)
	switches.add_child(_insured)
	ship_row.add_child(_viewer)
	ship_row.add_child(switches)
	for c in [head, ship_row, _stops, add_row, _matches, hint]:
		box.add_child(c)
	add_child(box)
	Events.fleet_changed.connect(_refresh)

func open(id: int, selected_system: int) -> void:
	ship_id = id
	add_system = selected_system
	_key = null
	visible = true
	Motion.pop_in(self)
	_refresh()

func close_panel() -> void:
	visible = false
	_search.clear()
	_search.release_focus()
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
	_viewer.show_ship(s)
	_safest.set_pressed_no_signal(s.safe_routing)
	_insured.set_pressed_no_signal(s.insured)
	_insured.text = "Insured  (about %s cr a month)" % Format.thousands(roundi(Danger.premium(w, s)))
	# The stops, their buttons and dropdowns are rebuilt only when what they
	# show changes (any ship moving refreshes this panel; an open dropdown
	# must survive that).
	var key := [s.id, var_to_str(s.orders), s.orders_active, s.order_index, s.modules, add_system,
		s.destination(), Sim.player().known.count(1)]
	if key == _key:
		Fit.center.call_deferred(self)
		return
	_key = key
	for child in _stops.get_children():
		child.queue_free()
	for i in s.orders.size():
		_stops.add_child(_stop_row(s, i))
	_fill_nearest(s)
	_suggest()
	Fit.center.call_deferred(self)

## Charted systems with a port: stops worth adding.
func _ports() -> Array[int]:
	var w: World = Sim.world
	var out: Array[int] = []
	for m in w.economy.markets:
		if Sim.player().is_known(m.system):
			out.append(m.system)
	return out

## "Beta Hydri  ·  Meridian Anchorage".
func _port_name(i: int) -> String:
	var sys: StarSystem = Sim.world.galaxy.systems[i]
	return "%s  ·  %s" % [sys.name, sys.settlement.name] if sys.settlement else sys.name

## The add list: the map selection, then the ports nearest the route's last
## stop (or the ship, with no stops yet).
func _fill_nearest(s: Ship) -> void:
	var w: World = Sim.world
	var from := int(s.orders[s.orders.size() - 1].system) if not s.orders.is_empty() else s.destination()
	var here: Vector3 = w.galaxy.systems[from].position
	_nearest.clear()
	_nearest_ids.clear()
	_nearest.add_item("Add a stop near %s…" % w.galaxy.systems[from].name)
	_nearest_ids.append(-1)
	if add_system >= 0 and add_system in _ports():
		_nearest.add_item("Selected on the map: %s" % _port_name(add_system))
		_nearest_ids.append(add_system)
	var ports := _ports()
	ports.erase(from)
	ports.sort_custom(func(a, b): return w.galaxy.systems[a].position.distance_to(here) < w.galaxy.systems[b].position.distance_to(here))
	for i in ports.slice(0, NEAREST):
		_nearest.add_item("%s  (%.1f ly)" % [_port_name(i), w.galaxy.systems[i].position.distance_to(here)])
		_nearest_ids.append(i)
	_nearest.select(0)

## Suggestions for the typed text: names starting with it first, then
## names containing it.
func _suggest() -> void:
	var text := _search.text.strip_edges().to_lower()
	_matches.clear()
	_match_ids.clear()
	if text != "":
		var starts: Array[int] = []
		var contains: Array[int] = []
		for i in _ports():
			var sys: StarSystem = Sim.world.galaxy.systems[i]
			var names := [sys.name.to_lower(), sys.settlement.name.to_lower() if sys.settlement else ""]
			if names.any(func(n): return n.begins_with(text)):
				starts.append(i)
			elif names.any(func(n): return text in n):
				contains.append(i)
		var by_name := func(a: int, b: int) -> bool: return _port_name(a).naturalnocasecmp_to(_port_name(b)) < 0
		starts.sort_custom(by_name)
		contains.sort_custom(by_name)
		for i in (starts + contains).slice(0, SUGGESTIONS):
			_matches.add_item(_port_name(i))
			_match_ids.append(i)
	_matches.visible = not _match_ids.is_empty()
	Fit.center.call_deferred(self)

func _stop_row(s: Ship, i: int) -> Control:
	var w: World = Sim.world
	var stop: Dictionary = s.orders[i]
	var sys: StarSystem = w.galaxy.systems[int(stop.system)]
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	var number := Label.new()
	var current := s.orders_active and i == s.order_index
	number.text = "%s%d." % ["▶ " if current else "", i + 1]
	number.add_theme_font_size_override("font_size", 16)
	head.add_child(number)
	var name := SystemLink.make(sys.index, "%s  ·  %s" % [sys.name, sys.settlement.name if sys.settlement else "no market"], 16)
	name.pressed.connect(func():
		close_panel()
		system_requested.emit(sys.index))
	head.add_child(name)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
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
	var auto := _check("Auto-trade", stop.get("auto", false),
		func(on): _edit(func(o): o[i].auto = on))
	auto.disabled = not ("auto_trader" in s.modules)
	auto.tooltip_text = "Buys the best known margin for the next stop instead of the list below. Needs an auto-trader module."
	var service := _check("Service when worn", stop.get("service", false),
		func(on): _edit(func(o): o[i].service = on))
	service.disabled = not w.fleet.is_shipyard(int(stop.system))
	service.tooltip_text = "At this shipyard, service the ship when its condition is well below what its age allows." \
		if not service.disabled else "Only at a shipyard"
	for c in [sell, auto, service]:
		opts.add_child(c)
	box.add_child(opts)
	box.add_child(_buy_list(s, i))
	panel.add_child(box)
	return panel

## The goods a stop buys, in order: a row per good (good, tonnes or "fill",
## remove) and a dropdown to add another. Greyed while auto-trade is on.
func _buy_list(s: Ship, i: int) -> Control:
	var w: World = Sim.world
	var stop: Dictionary = s.orders[i]
	var buys: Array = stop.get("buy", [])
	var auto: bool = stop.get("auto", false)
	var ids: PackedStringArray = w.economy.commodity_ids
	var holds := w.fleet.capacity(s)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	for k in buys.size():
		var b: Dictionary = buys[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "Buy" if k == 0 else "then"
		label.custom_minimum_size = Vector2(40, 0)
		label.add_theme_color_override("font_color", MUTED)
		var good := _goods(ids, holds, "")
		good.select(ids.find(b.commodity))
		good.disabled = auto
		good.item_selected.connect(func(g): _edit(func(o): o[i].buy[k].commodity = ids[g]))
		var amount := LineEdit.new()
		amount.custom_minimum_size = Vector2(80, 0)
		amount.placeholder_text = "fill"
		amount.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.text = "" if float(b.get("amount", 0)) <= 0.0 else str(roundi(float(b.amount)))
		amount.editable = not auto
		amount.tooltip_text = "Tonnes to have aboard after buying. Empty: fill the rest of its hold."
		var commit := func(_t = null):
			var v := maxf(amount.text.strip_edges().to_float(), 0.0)
			if not is_equal_approx(v, float(b.get("amount", 0))):
				_edit(func(o): o[i].buy[k].amount = v)
		amount.text_submitted.connect(commit)
		amount.focus_exited.connect(commit)
		var unit := Label.new()
		unit.text = "t"
		unit.add_theme_color_override("font_color", MUTED)
		var remove := Button.new()
		remove.text = "✕"
		remove.focus_mode = Control.FOCUS_NONE
		remove.disabled = auto
		remove.tooltip_text = "Don't buy this here"
		remove.pressed.connect(func(): _edit(func(o): o[i].buy.remove_at(k)))
		for c in [label, good, amount, unit, remove]:
			row.add_child(c)
		list.add_child(row)
	var add := _goods(ids, holds, "+ Buy a good…" if buys.is_empty() else "+ Then buy…")
	add.select(0)
	add.disabled = auto
	add.item_selected.connect(func(g):
		if g > 0:
			_edit(func(o):
				if not o[i].has("buy"):
					o[i].buy = []
				o[i].buy.append({"commodity": ids[g - 1], "amount": 0})))
	var add_row := HBoxContainer.new()
	add_row.add_child(add)
	list.add_child(add_row)
	return list

## A dropdown of every good (noting the ones this ship has no hold for),
## after a first `placeholder` item if one is given.
func _goods(ids: PackedStringArray, holds: Dictionary, placeholder: String) -> OptionButton:
	var b := OptionButton.new()
	b.focus_mode = Control.FOCUS_NONE
	if placeholder != "":
		b.add_item(placeholder)
	for id in ids:
		var carry: bool = holds.get(Defs.commodities[id].cargo_class, 0.0) > 0.0
		b.add_item("%s%s" % [Defs.commodities[id].name, "" if carry else "  (no hold)"])
	return b

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

func _add_stop(system_index: int) -> void:
	var w: World = Sim.world
	var sell := w.economy.market_at(system_index) != null
	_search.clear()
	_search.release_focus()
	_edit(func(o): o.append({"system": system_index, "sell_all": sell, "buy": [], "auto": false}))
	_suggest()

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
