class_name ShipyardPanel
extends PanelContainer
## Shipyard (major worlds) or refit dock (any other port) at one system.
## New ships, at shipyards only: a short list of the hulls this government's
## yards build this year (name, class, price; new models marked); click one
## to see it turning in 3D with all its numbers and traits, its standard
## fit and Buy. Your ships
## here: a fitting view per ship — drag a module from the rack onto a slot
## (or drag between slots to swap), see the ship as refitted, the price and
## days, then Refit. The rack greys out modules this port doesn't make
## (tech level). Service and Sell at shipyards only. Opened from the system
## card; Esc closes. With many ships here, their list scrolls so the panel
## stays on screen.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const AMBER := Color(0.98, 0.72, 0.3)
const CYAN := Color(0.35, 0.85, 1.0)
const GREEN := Color(0.45, 0.85, 0.55)
## A hull this many years old or less is marked NEW.
const NEW_YEARS := 2
## Screen space kept free above and below the panel.
const MARGIN := 24.0
## Module colours by kind on the slot diagram.
const KIND_COLORS := {
	"bulk": Color(0.75, 0.6, 0.4), "container": Color(0.35, 0.75, 0.95), "liquid": Color(0.5, 0.55, 1.0),
	"cold": Color(0.55, 0.95, 0.95), "secure": Color(0.98, 0.72, 0.3), "people": Color(0.75, 0.55, 1.0),
	"other": Color(0.6, 0.7, 0.8),
}

var system := -1

var _title := Label.new()
var _cash := Label.new()
var _hulls := VBoxContainer.new()
var _refits := VBoxContainer.new()
var _refit_scroll := ScrollContainer.new()
## The selected hull's card: model, numbers, standard fit, Buy.
var _preview := ShipViewer.new()
var _detail_name := Label.new()
var _detail_class := Label.new()
var _stats := GridContainer.new()
var _fit_text := Label.new()
var _buy := Button.new()
var _selected_hull := ""
var _new_ships := HBoxContainer.new()
var _new_title: Label
var _no_yard := Label.new()
## Ship id -> the fit being edited (module per slot), until refitted.
var _pending: Dictionary = {}
## What the lists were built for (see _refresh), and per ship the controls
## updated in place: name, service, sell, refit, and the fit shown.
var _key: Variant = null
var _refs: Dictionary = {}

## A module on the rack: drag it onto a slot.
class ModuleChip extends PanelContainer:
	var module_id := ""
	var label := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		if module_id == "":
			return null  # not made at this port
		var preview := Label.new()
		preview.text = label
		preview.add_theme_color_override("font_color", Color(0.98, 0.72, 0.3))
		set_drag_preview(preview)
		return {"module": module_id}

## One slot of a hull: takes a dropped module, or can be dragged to swap
## with another slot.
class SlotBox extends PanelContainer:
	var index := 0
	## "" for a built-in slot: it can't be dragged.
	var module_id := ""
	var label := ""
	## Called with (slot index, module id, from slot or -1).
	var on_drop: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
		if module_id == "":
			return null
		var preview := Label.new()
		preview.text = label
		set_drag_preview(preview)
		return {"module": module_id, "from": index}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("module")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		on_drop.call(index, data.module, data.get("from", -1))

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
	_hulls.add_theme_constant_override("separation", 3)
	_hulls.custom_minimum_size = Vector2(500, 0)
	_refits.add_theme_constant_override("separation", 14)
	_refits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_refit_scroll.add_child(_refits)
	_new_ships.add_theme_constant_override("separation", 18)
	_new_ships.add_child(_hulls)
	_new_ships.add_child(VSeparator.new())
	_new_ships.add_child(_detail_card())
	_new_title = _section("New ships  ·  click one to see it")
	_no_yard.text = "No shipyard here: new ships are built, sold and serviced at the major worlds " \
		+ "(industrial, core, military and robot worlds of tech 8 or more, and any world of tech 10)."
	_no_yard.add_theme_font_size_override("font_size", 14)
	_no_yard.add_theme_color_override("font_color", MUTED)
	_no_yard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_no_yard.custom_minimum_size = Vector2(900, 0)
	for c in [head, _new_title, _new_ships, _no_yard, HSeparator.new(), _section("Your ships here"), _refit_scroll]:
		box.add_child(c)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.fleet_changed.connect(_refresh)

func open(system_index: int) -> void:
	system = system_index
	var s: StarSystem = Sim.galaxy.systems[system_index]
	var yard: bool = Sim.world.fleet.is_shipyard(system_index)
	_title.text = "%s  ·  %s  (%s)" % ["Shipyard" if yard else "Refit dock", s.settlement.name, s.name]
	_new_title.visible = yard
	_new_ships.visible = yard
	_no_yard.visible = not yard
	_pending.clear()
	_key = null
	visible = true
	Motion.pop_in(self)
	_refresh()

func close_panel() -> void:
	visible = false
	closed.emit()

func _refresh() -> void:
	if not visible:
		return
	var world: World = Sim.world
	_cash.text = "%s cr   " % Format.thousands(roundi(Sim.player().cash))
	var for_sale := world.fleet.hulls_for_sale(system, world.year())
	if not for_sale.is_empty() and not (_selected_hull in for_sale):
		_selected_hull = for_sale[0]
	var here := world.ships_of(Sim.PLAYER).filter(
		func(s): return s.system == system and s.status != Ship.Status.TRAVELING)
	# Rows, slots and buttons are rebuilt only when what they show changes
	# (any ship moving or money changing refreshes this panel; a drag or a
	# click must survive that). The rest is updated in place.
	var key := [system, for_sale, here.map(func(s): return [s.id, s.status, var_to_str(s.modules),
		var_to_str(_pending.get(s.id, [])), s.busy_until])]
	_show_detail(world)
	if key == _key:
		for s in here:
			_update_fitting(world, s)
		Fit.fit_screen.call_deferred(self, _refit_scroll, _refits, MARGIN)
		return
	_key = key
	_clear(_hulls)
	var group := ButtonGroup.new()
	for id in for_sale:
		_hulls.add_child(_hull_row(world, id, group))
	_clear(_refits)
	_refs.clear()
	if here.is_empty():
		_refits.add_child(_cell("None of your ships is docked here.", MUTED, 14))
	for s in here:
		_refits.add_child(_fitting(s))
		_update_fitting(world, s)
	Fit.fit_screen.call_deferred(self, _refit_scroll, _refits, MARGIN)

## The parts of a ship's fitting view that change without a rebuild: its
## condition, the service price, what it sells for, whether a refit is
## affordable.
func _update_fitting(world: World, s: Ship) -> void:
	var r: Dictionary = _refs.get(s.id, {})
	if r.is_empty():
		return
	var fleet := world.fleet
	var busy := s.status == Ship.Status.REFITTING
	var yard := fleet.is_shipyard(system)
	r.name.text = "%s  ·  %s  ·  %d years  ·  condition %d%%" % [s.name, fleet.hull_def(s).name,
		floori(Aging.age_years(world, s)), roundi(s.condition * 100.0)]
	var q := Aging.service_quote(world, s)
	r.service.text = "Service  %s cr" % Format.thousands(roundi(q.cost)) if q.cost >= 1.0 else "Service"
	r.service.disabled = busy or q.cost < 1.0 or not yard
	r.service.tooltip_text = "%d days in the yard, back to %d%% (the best its age allows)%s" % [q.days,
		roundi(q.condition * 100.0), "\nDearer here: not one of the yards that build this hull" if q.foreign else ""] \
		if q.cost >= 1.0 else "In as good a state as its age allows"
	if not yard:
		r.service.tooltip_text = "Servicing needs a shipyard"
	r.sell.text = "Sell  %s cr" % Format.thousands(roundi(fleet.sale_value(s)))
	r.sell.disabled = busy or not yard
	r.sell.tooltip_text = "Ships are sold at a shipyard" if not yard else ""
	if r.has("refit"):
		var quote := fleet.refit_quote(s, r.fit)
		r.refit.disabled = quote.changed == 0 or Sim.player().cash < quote.cost

## One ship's fitting view: header with service and sale, the slot
## diagram, the module rack, and the refit quote.
func _fitting(s: Ship) -> Control:
	var world: World = Sim.world
	var fleet := world.fleet
	var busy := s.status == Ship.Status.REFITTING
	var yard := fleet.is_shipyard(system)
	var fit: Array = _pending.get(s.id, Array(s.modules))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var name_label := _cell("", TEXT, 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var service := _button("Service", func(): Sim.service_ship(s.id))
	var sell := _button("Sell", func(): Sim.sell_ship(s.id))
	_refs[s.id] = {"name": name_label, "service": service, "sell": sell, "fit": fit}
	head.add_child(service)
	head.add_child(sell)
	row.add_child(head)
	if busy:
		row.add_child(_cell("In the yard until %s." % Calendar.format(s.busy_until, world.start_year), AMBER, 14))
		return row
	# The slot diagram and rack on the left, the ship as refitted on the right.
	var fitting := HBoxContainer.new()
	fitting.add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 4)
	for i in fit.size():
		slots.add_child(_slot(s, i, fit[i]))
	left.add_child(slots)
	var model := ShipViewer.new()
	model.custom_minimum_size = Vector2(260, 130)
	model.show_fit(s.hull, fit, Sim.player().color)
	model.tooltip_text = "As it will look after the refit. Drag to turn it."
	fitting.add_child(left)
	fitting.add_child(model)
	row.add_child(fitting)
	# The rack of modules this hull takes.
	var rack := HFlowContainer.new()
	rack.add_theme_constant_override("h_separation", 6)
	rack.add_theme_constant_override("v_separation", 6)
	rack.add_child(_cell("Drag onto a slot:", MUTED, 13))
	for m in Defs.world_content.modules:
		if fleet.module_allowed(s.hull, m):
			rack.add_child(_chip(m, fleet.module_sold_at(system, m)))
	left.add_child(rack)
	# Quote and actions.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	var quote := fleet.refit_quote(s, fit)
	var summary := _cell(_fit_summary(s, fit), CYAN, 14, true)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(summary)
	actions.add_child(_cell("no changes" if quote.changed == 0 else "%s cr  ·  %d days" % [
		Format.thousands(roundi(quote.cost)), quote.days], AMBER if quote.changed > 0 else MUTED, 14, true))
	var reset := _button("Reset", func():
		_pending.erase(s.id)
		_refresh())
	reset.disabled = quote.changed == 0
	var refit := _button("Refit", func():
		if Sim.refit_ship(s.id, fit).ok:
			_pending.erase(s.id))
	_refs[s.id].refit = refit
	actions.add_child(reset)
	actions.add_child(refit)
	row.add_child(actions)
	return row

## One hull in the list: name (and NEW), class, price; click to select.
func _hull_row(world: World, id: String, group: ButtonGroup) -> Button:
	var h: Dictionary = Defs.world_content.hulls[id]
	var row := Button.new()
	row.toggle_mode = true
	row.button_group = group
	row.button_pressed = id == _selected_hull
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 34)
	row.pressed.connect(func():
		_selected_hull = id
		_show_detail(Sim.world))
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.offset_left = 10
	cols.offset_right = -10
	cols.add_theme_constant_override("separation", 10)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fresh := world.year() - int(h.year_from) <= NEW_YEARS and int(h.year_from) > world.start_year - NEW_YEARS
	var name_label := _cell(h.name, TEXT, 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parts: Array[Control] = [name_label]
	if fresh:
		parts.append(_cell("NEW", AMBER, 11))
	parts.append(_cell(h["class"], MUTED, 13))
	var price := _cell("%s cr" % Format.thousands(roundi(_fitted_price(h))), AMBER, 14, true)
	price.custom_minimum_size = Vector2(120, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parts.append(price)
	for p in parts:
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cols.add_child(p)
	row.add_child(cols)
	return row

## The card for the selected hull (built once; filled by _show_detail).
func _detail_card() -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	card.custom_minimum_size = Vector2(420, 0)
	_detail_name.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_detail_name.add_theme_font_size_override("font_size", 20)
	_detail_class.add_theme_font_size_override("font_size", 13)
	_detail_class.add_theme_color_override("font_color", MUTED)
	_preview.custom_minimum_size = Vector2(420, 200)
	_preview.tooltip_text = "Drag to turn it"
	_stats.columns = 4
	_stats.add_theme_constant_override("h_separation", 14)
	_stats.add_theme_constant_override("v_separation", 2)
	_fit_text.add_theme_font_size_override("font_size", 13)
	_fit_text.add_theme_color_override("font_color", CYAN)
	_fit_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fit_text.custom_minimum_size = Vector2(420, 0)
	_buy.focus_mode = Control.FOCUS_NONE
	_buy.pressed.connect(func(): Sim.buy_ship(_selected_hull, system))
	for c in [_detail_name, _detail_class, _preview, _stats, _fit_text, _buy]:
		card.add_child(c)
	return card

func _show_detail(world: World) -> void:
	if _selected_hull == "":
		_detail_name.text = "No ships built here this year"
		_preview.clear()
		_buy.visible = false
		return
	var h: Dictionary = Defs.world_content.hulls[_selected_hull]
	var modules: Array = h.get("default_modules", [])
	_detail_name.text = h.name
	_detail_class.text = "%s  ·  built %d–%d  ·  needs tech %d" % [h["class"], int(h.year_from), int(h.year_to), int(h.tech)]
	_preview.show_fit(_selected_hull, modules, Sim.player().color)
	_clear(_stats)
	var rows := [
		["Slots", "%d × %d t" % [int(h.slots), int(h.slot_tonnes)]],
		["Cargo", "%s t" % Format.thousands(int(h.slots) * int(h.slot_tonnes))],
		["Speed", "%.2f ly/day" % float(h.speed)],
		["Jump", "%.0f ly" % float(h.jump_range)],
		["Reliability", "%d%%" % roundi(float(h.reliability) * 100.0)],
		["Fuel", "%d t per ly" % int(h.get("fuel_per_ly", 0))],
		["Crew", "%s cr/month under way" % Format.thousands(int(h.crew_cost)) if int(h.crew_cost) > 0 else "none (crewless)"],
		["Maintenance", "%s cr/month under way" % Format.thousands(int(h.maintenance))],
	] + _trait_rows(h)
	for r in rows:
		_stats.add_child(_cell(r[0], MUTED, 13))
		_stats.add_child(_cell(r[1], Color.WHITE, 13, true))
	# "4 × Container hold, 2 × Bulk hold", in fitting order.
	var counts := {}
	for m in modules:
		counts[m] = counts.get(m, 0) + 1
	var names := PackedStringArray()
	for m in counts:
		names.append(("%d × %s" % [counts[m], _module_name(m)]) if counts[m] > 1 else _module_name(m))
	_fit_text.text = "Standard fit: %s  ·  refit it later at any shipyard" % ", ".join(names)
	var price := _fitted_price(h)
	var cash := Sim.player().cash
	_buy.visible = true
	_buy.disabled = cash < price
	_buy.text = "Buy  %s cr" % Format.thousands(roundi(price)) if cash >= price \
		else "Buy  %s cr  ·  %s more needed" % [Format.thousands(roundi(price)), Format.thousands(roundi(price - cash))]

## [label, value] rows for a hull's builders and traits (hulls.json).
func _trait_rows(h: Dictionary) -> Array:
	var by := PackedStringArray()
	for g in h.get("builders", []):
		by.append(Defs.government_name(g))
	var rows := [["Built by", " / ".join(by) + " yards"]]
	var tr: Dictionary = h.get("traits", {})
	if tr.has("raid_mult"):
		rows.append(["Cloaked", "raid risk × %s" % str(tr.raid_mult)])
	if tr.has("armour"):
		rows.append(["Armour", "%d built in (risk × %s)" % [int(tr.armour),
			str(pow(float(Defs.world_content.balance.danger.get("armour_factor", 0.5)), int(tr.armour)))]])
	if tr.has("aging_mult"):
		rows.append(["Wear", "%s × normal" % str(tr.aging_mult)])
	if tr.has("influence_mult"):
		rows.append(["Prestige", "+%d%% influence from trade" % roundi((float(tr.influence_mult) - 1.0) * 100.0)])
	if tr.has("fixed"):
		var built_in := PackedStringArray()
		for i in int(tr.fixed):
			built_in.append(_module_name(h.default_modules[i]))
		rows.append(["Built in", ", ".join(built_in)])
	if not h.get("forbid", []).is_empty():
		rows.append(["Cannot fit", ", ".join(h.forbid) + " modules"])
	return rows

func _slot(s: Ship, i: int, module_id: String) -> SlotBox:
	var fixed := i < Sim.world.fleet.fixed_slots(s.hull)
	var box := SlotBox.new()
	box.index = i
	box.module_id = "" if fixed else module_id
	box.label = _module_name(module_id)
	box.custom_minimum_size = Vector2(112, 58)
	box.tooltip_text = "Slot %d: %s. Drop a module here, or drag this one to another slot to swap." % [i + 1, box.label]
	if fixed:
		box.tooltip_text = "Slot %d: %s, built into the hull." % [i + 1, box.label]
	box.on_drop = func(index: int, m: String, from: int) -> void:
		if index < Sim.world.fleet.fixed_slots(s.hull):
			Events.notice.emit("Slot %d is built into the hull" % (index + 1))
			return
		if not Sim.world.fleet.module_allowed(s.hull, m):
			Events.notice.emit("%s cannot be fitted to this hull" % _module_name(m))
			return
		if from < 0 and not Sim.world.fleet.module_sold_at(system, m):
			Events.notice.emit("%s is not made here" % _module_name(m))
			return
		var fit: Array = _pending.get(s.id, Array(s.modules)).duplicate()
		if from >= 0:
			fit[from] = fit[index]
		fit[index] = m
		_pending[s.id] = fit
		_refresh()
	var style := StyleBoxFlat.new()
	var c := _kind_color(module_id)
	style.bg_color = Color(c, 0.14)
	style.border_color = Color(c, 0.8 if module_id != s.modules[i] else 0.45)
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _cell(box.label, TEXT, 13)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stat := _cell(_module_stat(s, module_id), MUTED, 12, true)
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	v.add_child(stat)
	if fixed:
		var built := _cell("built in", MUTED, 11)
		built.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(built)
	if module_id != s.modules[i]:
		var changed := _cell("changed", AMBER, 11)
		changed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(changed)
	box.add_child(v)
	return box

## A module on the rack; one this port doesn't make is greyed out and
## can't be dragged.
func _chip(module_id: String, made_here := true) -> ModuleChip:
	var chip := ModuleChip.new()
	chip.module_id = module_id if made_here else ""
	chip.label = _module_name(module_id)
	chip.mouse_default_cursor_shape = Control.CURSOR_DRAG if made_here else Control.CURSOR_FORBIDDEN
	var def: Dictionary = Defs.world_content.modules[module_id]
	chip.tooltip_text = "%s  ·  %s cr" % [chip.label, Format.thousands(int(def.price))] if made_here \
		else "%s: not made here (needs tech %d)" % [chip.label, int(def.get("tech", 1))]
	if not made_here:
		chip.modulate = Color(1, 1, 1, 0.35)
	var style := StyleBoxFlat.new()
	var c := _kind_color(module_id)
	style.bg_color = Color(c, 0.12)
	style.border_color = Color(c, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", style)
	var l := _cell("%s  %s" % [chip.label, Format.money_short(float(def.price))], TEXT, 13)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(l)
	return chip

## "container 750 t  ·  bulk 600 t  ·  40 berths  ·  0.30 ly/d  ·  12 ly".
func _fit_summary(s: Ship, fit: Array) -> String:
	var fleet: Fleet = Sim.world.fleet
	var probe := Ship.new()
	probe.hull = s.hull
	probe.modules.assign(fit)
	var parts := PackedStringArray()
	var cap := fleet.capacity(probe)
	for cls in cap:
		parts.append("%s %s t" % [cls, Format.thousands(roundi(cap[cls]))])
	var berths := 0
	var mail := 0
	for m in fit:
		berths += int(Defs.world_content.modules[m].get("passengers", 0))
		mail += int(Defs.world_content.modules[m].get("mail", 0))
	if berths > 0:
		parts.append("%d berths" % berths)
	if mail > 0:
		parts.append("%d mail bay%s" % [mail, "" if mail == 1 else "s"])
	parts.append("%.2f ly/d" % fleet.speed(probe))
	parts.append("%.0f ly jump" % fleet.jump_range(probe))
	return "  ·  ".join(parts)

func _module_stat(s: Ship, module_id: String) -> String:
	var def: Dictionary = Defs.world_content.modules.get(module_id, {})
	var slot := float(Sim.world.fleet.hull_def(s).slot_tonnes)
	if def.has("cargo_class"):
		return "%s t" % Format.thousands(roundi(slot * float(def.capacity)))
	if def.has("passengers"):
		return "%d berths" % int(def.passengers)
	if def.has("mail"):
		return "20 sacks"
	if def.has("speed_mult"):
		return "+%d%% speed" % roundi((float(def.speed_mult) - 1.0) * 100.0)
	if def.has("range_add"):
		return "+%.0f ly jump" % float(def.range_add)
	if def.has("armour"):
		return "half the risk"
	return "auto-trade"

func _kind_color(module_id: String) -> Color:
	var def: Dictionary = Defs.world_content.modules.get(module_id, {})
	if def.has("cargo_class"):
		return KIND_COLORS.get(def.cargo_class, KIND_COLORS.other)
	if def.has("passengers") or def.has("mail"):
		return KIND_COLORS.people
	return KIND_COLORS.other

func _module_name(module_id: String) -> String:
	return Defs.world_content.modules.get(module_id, {}).get("name", module_id)

func _fitted_price(h: Dictionary) -> float:
	var p := float(h.price)
	for m in h.get("default_modules", []):
		p += float(Defs.world_content.modules[m].price)
	return p

func _clear(c: Container) -> void:
	for child in c.get_children():
		c.remove_child(child)
		child.queue_free()

func _section(text: String) -> Label:
	return _cell(text.to_upper(), MUTED, 12)

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b

func _cell(text: String, color: Color, size: int, mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	if mono:
		l.add_theme_font_override("font", Fonts.MONO)
	return l
