class_name ShipyardPanel
extends PanelContainer
## Shipyard at one system. New ships: the hulls built here this year side
## by side (new models marked). Your ships here: a fitting view per ship —
## drag a module from the rack onto a slot (or drag between slots to swap),
## see the refit price and days, then Refit — plus Service and Sell.
## Opened from the system card; Esc closes.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const AMBER := Color(0.98, 0.72, 0.3)
const CYAN := Color(0.35, 0.85, 1.0)
const GREEN := Color(0.45, 0.85, 0.55)
## A hull this many years old or less is marked NEW.
const NEW_YEARS := 2
## Module colours by kind on the slot diagram.
const KIND_COLORS := {
	"bulk": Color(0.75, 0.6, 0.4), "container": Color(0.35, 0.75, 0.95), "liquid": Color(0.5, 0.55, 1.0),
	"cold": Color(0.55, 0.95, 0.95), "secure": Color(0.98, 0.72, 0.3), "people": Color(0.75, 0.55, 1.0),
	"other": Color(0.6, 0.7, 0.8),
}

var system := -1

var _title := Label.new()
var _cash := Label.new()
var _hulls := GridContainer.new()
var _refits := VBoxContainer.new()
## Ship id -> the fit being edited (module per slot), until refitted.
var _pending: Dictionary = {}

## A module on the rack: drag it onto a slot.
class ModuleChip extends PanelContainer:
	var module_id := ""
	var label := ""

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = label
		preview.add_theme_color_override("font_color", Color(0.98, 0.72, 0.3))
		set_drag_preview(preview)
		return {"module": module_id}

## One slot of a hull: takes a dropped module, or can be dragged to swap
## with another slot.
class SlotBox extends PanelContainer:
	var index := 0
	var module_id := ""
	var label := ""
	## Called with (slot index, module id, from slot or -1).
	var on_drop: Callable

	func _get_drag_data(_at: Vector2) -> Variant:
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
	_hulls.columns = 11
	_hulls.add_theme_constant_override("h_separation", 16)
	_hulls.add_theme_constant_override("v_separation", 4)
	_refits.add_theme_constant_override("separation", 14)
	for c in [head, _section("New ships"), _hulls, HSeparator.new(), _section("Your ships here"), _refits]:
		box.add_child(c)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.fleet_changed.connect(_refresh)

func open(system_index: int) -> void:
	system = system_index
	var s: StarSystem = Sim.galaxy.systems[system_index]
	_title.text = "Shipyard  ·  %s  (%s)" % [s.settlement.name, s.name]
	_pending.clear()
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
	_clear(_hulls)
	for h in ["Hull", "", "Class", "Slots", "Cargo", "Speed", "Jump", "Reliability", "Upkeep / month", "Price", ""]:
		_hulls.add_child(_cell(h, MUTED, 12))
	for id in world.fleet.hulls_for_sale(system, world.year()):
		var h: Dictionary = Defs.world_content.hulls[id]
		var price := _fitted_price(h)
		var fresh := world.year() - int(h.year_from) <= NEW_YEARS and int(h.year_from) > world.start_year - NEW_YEARS
		_hulls.add_child(_cell(h.name, TEXT, 15))
		_hulls.add_child(_cell("NEW" if fresh else "", AMBER, 11))
		_hulls.add_child(_cell(h["class"], MUTED, 14))
		_hulls.add_child(_cell("%d" % h.slots, Color.WHITE, 14, true))
		_hulls.add_child(_cell("%s t" % Format.thousands(int(h.slots) * int(h.slot_tonnes)), Color.WHITE, 14, true))
		_hulls.add_child(_cell("%.2f ly/d" % h.speed, Color.WHITE, 14, true))
		_hulls.add_child(_cell("%.0f ly" % h.jump_range, Color.WHITE, 14, true))
		_hulls.add_child(_cell("%d%%" % roundi(float(h.reliability) * 100.0), Color.WHITE, 14, true))
		_hulls.add_child(_cell("%s cr" % Format.thousands(int(h.crew_cost) + int(h.maintenance)), Color.WHITE, 14, true))
		_hulls.add_child(_cell("%s cr" % Format.thousands(roundi(price)), AMBER, 14, true))
		var buy := Button.new()
		buy.text = "Buy"
		buy.focus_mode = Control.FOCUS_NONE
		buy.disabled = Sim.player().cash < price
		buy.pressed.connect(func(): Sim.buy_ship(id, system))
		_hulls.add_child(buy)
	_clear(_refits)
	var here := world.ships_of(Sim.PLAYER).filter(
		func(s): return s.system == system and s.status != Ship.Status.TRAVELING)
	if here.is_empty():
		_refits.add_child(_cell("None of your ships is docked here.", MUTED, 14))
	for s in here:
		_refits.add_child(_fitting(s))
	(func(): reset_size()).call_deferred()

## One ship's fitting view: header with service and sale, the slot
## diagram, the module rack, and the refit quote.
func _fitting(s: Ship) -> Control:
	var world: World = Sim.world
	var fleet := world.fleet
	var busy := s.status == Ship.Status.REFITTING
	var fit: Array = _pending.get(s.id, Array(s.modules))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var name_label := _cell("%s  ·  %s  ·  %d years  ·  condition %d%%" % [s.name, fleet.hull_def(s).name,
		floori(Aging.age_years(world, s)), roundi(s.condition * 100.0)], TEXT, 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var q := Aging.service_quote(world, s)
	var service := _button("Service  %s cr" % Format.thousands(roundi(q.cost)), func(): Sim.service_ship(s.id))
	service.disabled = busy or q.cost < 1.0
	service.tooltip_text = "%d days in the yard, back to %d%% (the best its age allows)" % [q.days,
		roundi(q.condition * 100.0)] if q.cost >= 1.0 else "In as good a state as its age allows"
	var sell := _button("Sell  %s cr" % Format.thousands(roundi(fleet.sale_value(s))), func(): Sim.sell_ship(s.id))
	sell.disabled = busy
	head.add_child(service)
	head.add_child(sell)
	row.add_child(head)
	if busy:
		row.add_child(_cell("In the yard until %s." % Calendar.format(s.busy_until, world.start_year), AMBER, 14))
		return row
	# The slot diagram.
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 4)
	for i in fit.size():
		slots.add_child(_slot(s, i, fit[i]))
	row.add_child(slots)
	# The rack of modules this hull takes.
	var rack := HFlowContainer.new()
	rack.add_theme_constant_override("h_separation", 6)
	rack.add_theme_constant_override("v_separation", 6)
	rack.add_child(_cell("Drag onto a slot:", MUTED, 13))
	for m in Defs.world_content.modules:
		if fleet.module_allowed(s.hull, m):
			rack.add_child(_chip(m))
	row.add_child(rack)
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
	refit.disabled = quote.changed == 0 or Sim.player().cash < quote.cost
	actions.add_child(reset)
	actions.add_child(refit)
	row.add_child(actions)
	return row

func _slot(s: Ship, i: int, module_id: String) -> SlotBox:
	var box := SlotBox.new()
	box.index = i
	box.module_id = module_id
	box.label = _module_name(module_id)
	box.custom_minimum_size = Vector2(112, 58)
	box.tooltip_text = "Slot %d: %s. Drop a module here, or drag this one to another slot to swap." % [i + 1, box.label]
	box.on_drop = func(index: int, m: String, from: int) -> void:
		if not Sim.world.fleet.module_allowed(s.hull, m):
			Events.notice.emit("%s cannot be fitted to this hull" % _module_name(m))
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
	if module_id != s.modules[i]:
		var changed := _cell("changed", AMBER, 11)
		changed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(changed)
	box.add_child(v)
	return box

func _chip(module_id: String) -> ModuleChip:
	var chip := ModuleChip.new()
	chip.module_id = module_id
	chip.label = _module_name(module_id)
	chip.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var def: Dictionary = Defs.world_content.modules[module_id]
	chip.tooltip_text = "%s  ·  %s cr" % [chip.label, Format.thousands(int(def.price))]
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
