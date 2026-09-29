class_name InfluenceCard
extends VBoxContainer
## The player's standing at one system (in the system panel): the influence
## score on a bar with the tier marks, what the player holds there (trading
## post, concession, patron), and the action the next tier unlocks. As
## patron: veto a running tariff hike, broker peace in a war when both
## sides depend on the player. Hidden where there is no market.

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const CYAN := Color(0.35, 0.85, 1.0)
const AMBER := Color(0.98, 0.72, 0.3)
const WIDTH := 352.0

var _system := -1
var _head := Label.new()
var _bar := Bar.new()
var _holds := Label.new()
var _actions := VBoxContainer.new()
## The action buttons wanted ([text, tooltip, disabled, callable]) and what
## the current ones were built for.
var _specs: Array = []
var _actions_key: Variant = null

## The score as a bar, with a tick at every tier.
class Bar extends Control:
	var value := 0.0
	var marks: Array[float] = []
	var max_value := 100.0

	func _draw() -> void:
		var r := Rect2(Vector2(0, 3), Vector2(size.x, size.y - 6))
		draw_rect(r, Color(1, 1, 1, 0.07))
		var fill := r
		fill.size.x = r.size.x * clampf(value / max_value, 0.0, 1.0)
		draw_rect(fill, InfluenceCard.tier_color(value, marks))
		for m in marks:
			var x := r.size.x * m / max_value
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.45 if value >= m else 0.25), 1.0)

## Bar colour by tier: slate, cyan (post), green (concession), amber (patron).
static func tier_color(value: float, marks: Array) -> Color:
	var colors := [Color(0.45, 0.52, 0.64), CYAN, Color(0.45, 0.9, 0.55), AMBER]
	var t := 0
	for m in marks:
		if value >= m:
			t += 1
	return colors[t]

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_head.add_theme_font_size_override("font_size", 12)
	_head.add_theme_color_override("font_color", MUTED)
	_head.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.custom_minimum_size = Vector2(WIDTH, 14)
	_holds.add_theme_font_size_override("font_size", 13)
	_holds.add_theme_color_override("font_color", TEXT)
	_holds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_holds.custom_minimum_size = Vector2(WIDTH, 0)
	_actions.add_theme_constant_override("separation", 5)
	for c in [HSeparator.new(), _head, _bar, _holds, _actions]:
		add_child(c)
	for sig in [Events.influence_changed, Events.world_events_changed]:
		sig.connect(func(): if visible and _system >= 0: show_system(_system))
	Events.company_changed.connect(func(_c): if visible and _system >= 0: show_system(_system))

func show_system(i: int) -> void:
	_system = i
	var w: World = Sim.world
	visible = w.economy.market_at(i) != null
	if not visible:
		return
	_specs.clear()
	var p := Sim.PLAYER
	var score := Influence.of(w, p, i)
	var tier := Influence.tier(w, p, i)
	var marks: Array[float] = [Influence.threshold(w, Influence.Tier.POST),
		Influence.threshold(w, Influence.Tier.CONCESSION), Influence.threshold(w, Influence.Tier.PATRON)]
	_head.text = "YOUR INFLUENCE  ·  %d / 100  ·  %s" % [floori(score), Influence.TIER_NAMES[tier].to_upper()]
	_bar.value = score
	_bar.marks = marks
	_bar.queue_redraw()
	var holds := PackedStringArray()
	if Influence.has_post(w, p, i):
		holds.append("Trading post: live prices, half docking fees")
	if Influence.has_concession(w, p, i):
		holds.append("Concession: half tariffs, first pick of new contracts")
	if tier == Influence.Tier.PATRON:
		holds.append("Patron: wars and coups are rarer here")
	# Nothing held yet: the how-to is a tooltip, not two lines of text.
	_holds.text = "\n".join(holds)
	_holds.visible = not holds.is_empty()
	var tip := "Sell goods here (best what it's short of) and deliver contracts to gain influence."
	_head.tooltip_text = tip
	_bar.tooltip_text = tip
	var k := Influence.cfg(w)
	if not Influence.has_post(w, p, i):
		_action("Open trading post  ·  %s cr" % Format.money_short(float(k.get("post_cost", 0))),
			"Live prices here and half the docking fees. Needs influence %d." % roundi(marks[0]),
			tier < Influence.Tier.POST, func(): Sim.open_trading_post(i))
	elif not Influence.has_concession(w, p, i):
		_action("Sign trade concession  ·  %s cr" % Format.money_short(float(k.get("concession_cost", 0))),
			"Half the tariffs here and first pick of new contracts. Needs influence %d; lost below %d." % [
				roundi(marks[1]), roundi(float(k.get("concession_keep", 40)))],
			tier < Influence.Tier.CONCESSION, func(): Sim.sign_concession(i))
	for ev in WorldEvents.active_at(w, i):
		var d := WorldEvents.def_of(w, ev.kind)
		if d.get("vetoable", false):
			_action("Veto the %s  ·  −%d influence" % [d.get("name", ev.kind).to_lower(), roundi(float(k.get("veto_cost", 15)))],
				"Your lobby blocks it. Only the patron can." if tier < Influence.Tier.PATRON else "Your lobby blocks it.",
				tier < Influence.Tier.PATRON, func(): Sim.veto_event(ev.id))
		elif d.get("brokerable", false):
			var other: int = ev.systems[1] if ev.systems[0] == i else ev.systems[0]
			var both := Influence.is_patron(w, p, i) and Influence.is_patron(w, p, other)
			_action("Broker peace with %s  ·  −%d influence each" % [WorldEvents.place_name(w, other), roundi(float(k.get("peace_cost", 20)))],
				"Both sides depend on you: the war ends." if both else "You must be patron of both sides.",
				not both, func(): Sim.broker_peace(ev.id))
	_build_actions(i)

## Collects an action button; _build_actions makes them.
func _action(text: String, tip: String, disabled: bool, action: Callable) -> void:
	_specs.append([text, tip, disabled, action])

## Rebuilds the buttons only when they change, so one isn't replaced under
## the mouse whenever money moves.
func _build_actions(i: int) -> void:
	# The running events too: a veto or peace button is bound to one.
	var key := [i, _specs.map(func(a): return [a[0], a[1], a[2]]),
		WorldEvents.active_at(Sim.world, i).map(func(ev): return ev.id)]
	if key == _actions_key:
		return
	_actions_key = key
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for a in _specs:
		var b := Button.new()
		b.text = a[0]
		b.tooltip_text = a[1]
		b.disabled = a[2]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(a[3])
		_actions.add_child(b)
