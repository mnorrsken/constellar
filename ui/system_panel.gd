class_name SystemPanel
extends PanelContainer
## Card on the right of the map for the selected star system. With a ship
## selected it also offers to send that ship here (route length, days,
## arrival date, or why it cannot go).

signal view_requested
signal market_requested
signal shipyard_requested
signal send_requested
signal contracts_requested

const WIDTH := 380.0

var _title := Label.new()
var _facts := Label.new()
var _bodies := Label.new()
var _card := SettlementCard.new()
var _button := Button.new()
var _market_button := Button.new()
var _yard_button := Button.new()
var _contracts_button := Button.new()
var _send_info := Label.new()
var _send_button := Button.new()
var _send_box := VBoxContainer.new()
var _system: StarSystem
## Controls hidden for an uncharted system.
var _details: Array = []
## Selected ship id, or -1.
var ship_id := -1

func _ready() -> void:
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -WIDTH - 28
	offset_right = -28
	offset_top = 100
	offset_bottom = 100  # zero height: the panel grows to fit its content
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 28)
	_facts.add_theme_font_override("font", Fonts.MONO)
	_facts.add_theme_font_size_override("font_size", 14)
	_facts.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))
	_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_facts.custom_minimum_size = Vector2(WIDTH - 28, 0)
	_bodies.add_theme_font_size_override("font_size", 14)
	_bodies.add_theme_color_override("font_color", SettlementCard.MUTED)
	_button.text = "View system   ⏎"
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(func(): view_requested.emit())
	_market_button.text = "Market   M"
	_market_button.focus_mode = Control.FOCUS_NONE
	_market_button.pressed.connect(func(): market_requested.emit())
	_yard_button.text = "Shipyard"
	_yard_button.focus_mode = Control.FOCUS_NONE
	_yard_button.pressed.connect(func(): shipyard_requested.emit())
	_contracts_button.focus_mode = Control.FOCUS_NONE
	_contracts_button.pressed.connect(func(): contracts_requested.emit())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	for b in [_button, _market_button, _yard_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	_send_info.add_theme_font_size_override("font_size", 14)
	_send_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_send_info.custom_minimum_size = Vector2(WIDTH - 28, 0)
	_send_button.focus_mode = Control.FOCUS_NONE
	_send_button.pressed.connect(func(): send_requested.emit())
	_send_box.add_theme_constant_override("separation", 6)
	_send_box.add_child(HSeparator.new())
	_send_box.add_child(_send_info)
	_send_box.add_child(_send_button)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_details = [HSeparator.new(), _card, HSeparator.new(), _bodies, buttons, _contracts_button]
	for c in [_title, _facts] + _details + [_send_box]:
		box.add_child(c)
	add_child(box)
	Events.fleet_changed.connect(func(): if visible and _system: show_system(_system))
	Events.world_events_changed.connect(func(): if visible and _system: show_system(_system))
	Events.contracts_changed.connect(func(): if visible and _system: show_system(_system))
	# Arrival dates in the send line move on with the calendar.
	Events.day_passed.connect(func(_d): if visible and _system and ship_id >= 0: _update_send())

## Sets (or clears, with -1) the ship the send section is about.
func set_ship(id: int) -> void:
	ship_id = id
	if visible and _system:
		show_system(_system)

func show_system(s: StarSystem) -> void:
	if not visible:
		Motion.fade_in(self)
	_system = s
	var charted: bool = Sim.player().is_known(s.index)
	for c in _details:
		c.visible = charted
	if not charted:
		_title.text = "Uncharted system"
		_facts.text = "Send a ship within one jump to chart it."
		_update_send()
		visible = true
		_fit.call_deferred()
		return
	_title.text = s.name
	var types := PackedStringArray()
	for star in s.stars:
		types.append(Format.spectral(star))
	var where := "home of the Concordance" if s.id == "sol" else "%.2f ly from Sol" % s.position.length()
	_facts.text = "%s  ·  %s  ·  %s region" % [
		", ".join(types), where, SettlementGen.region_of(s.position.length(), Defs.world_content.balance)]
	_card.show_system(s)
	var planets := s.planets.filter(func(p): return p.type != "belt").size()
	var belts := s.planets.size() - planets
	_bodies.text = "%d planet%s%s" % [planets, "" if planets == 1 else "s",
		"" if belts == 0 else "  ·  %d belt%s" % [belts, "" if belts == 1 else "s"]]
	_system = s
	_market_button.disabled = s.settlement == null
	_yard_button.disabled = not Sim.world.fleet.is_shipyard(s.index)
	var offers := Contracts.offers_at(Sim.world, s.index).size()
	_contracts_button.text = "Contracts  ·  %d on the board   C" % offers
	_contracts_button.disabled = s.settlement == null
	_update_send()
	visible = true
	_fit.call_deferred()

func _update_send() -> void:
	var fleet: Fleet = Sim.world.fleet
	var ship := fleet.get_ship(ship_id) if ship_id >= 0 else null
	_send_box.visible = ship != null
	if ship == null:
		return
	_send_button.text = "Send %s here   S" % ship.name
	var plan := Sim.plan_route(ship.id, _system.index)
	if ship.status == Ship.Status.TRAVELING:
		plan = {"ok": false, "error": "%s is already under way" % ship.name}
	elif ship.status == Ship.Status.REFITTING:
		plan = {"ok": false, "error": "%s is being refitted" % ship.name}
	_send_button.disabled = not plan.ok
	if plan.ok:
		var jumps: int = plan.path.size() - 1
		_send_info.text = "%d jump%s  ·  %.1f ly  ·  %d days  ·  arrives %s" % [
			jumps, "" if jumps == 1 else "s", plan.length, plan.days,
			Calendar.format(Sim.world.day + plan.days, Sim.world.start_year)]
		_send_info.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
		# Worth a warning from 1 in 100 up.
		if plan.risk >= 0.01:
			_send_info.text += "  ·  %.0f%% risk of a hit%s" % [plan.risk * 100.0,
				" (safest route)" if ship.safe_routing else ""]
			_send_info.add_theme_color_override("font_color", MapModeBar.danger_ramp(plan.risk / 2.0))
	else:
		_send_info.text = plan.error
		_send_info.add_theme_color_override("font_color", SettlementCard.MUTED)

## Shrinks back to the content height (Controls grow by themselves but never
## shrink when their content gets shorter).
func _fit() -> void:
	offset_bottom = offset_top
