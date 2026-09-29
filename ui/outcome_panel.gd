class_name OutcomePanel
extends PanelContainer
## The end of the road, centred over the dimmed map: the player's goal was
## reached (keep playing in the sandbox), or the house is bankrupt (the
## game is over: quit).

signal closed
## The bankrupt player wants the main menu (a new game or a load).
signal menu_requested

const MUTED := Color(0.55, 0.62, 0.74)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)

## True while it shows the bankruptcy (it can't be closed then).
var game_over := false

var _title := Label.new()
var _body := Label.new()
var _buttons := HBoxContainer.new()

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
	box.add_theme_constant_override("separation", 14)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_theme_font_size_override("font_size", 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(520, 0)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	for c in [_title, _body, _buttons]:
		box.add_child(c)
	add_child(box)

func show_goal() -> void:
	var w: World = Sim.world
	var p := Sim.player()
	var g := Goals.progress(w, Sim.PLAYER)
	game_over = false
	_title.text = "Goal reached"
	_title.add_theme_color_override("font_color", GREEN)
	var how := "worth %s cr" % Format.thousands(roundi(g.current)) if g.goal == "value" \
		else "patron of %d systems" % g.current
	_body.text = "%s is %s: %s, on %s.\n\nThe rim is still yours to trade. Keep playing as long as you like." % [
		p.name, how, g.name, Calendar.format(p.goal_day, w.start_year)]
	_set_buttons([["Keep playing", close_panel]])
	_open()

func show_bankrupt() -> void:
	var w: World = Sim.world
	var p := Sim.player()
	game_over = true
	_title.text = "Bankrupt"
	_title.add_theme_color_override("font_color", RED)
	_body.text = "%d months with no cash and the bank lending no more: %s's creditors seize the books on %s.\n\nThe house of trade is closed." % [
		int(w.content.balance.get("bankruptcy_months", 3)), p.name, w.date_string()]
	_set_buttons([["Main menu", func():
		visible = false
		menu_requested.emit()], ["Quit", func(): get_tree().quit()]])
	_open()

func close_panel() -> void:
	if game_over:
		return
	visible = false
	closed.emit()

func _open() -> void:
	visible = true
	Motion.pop_in(self)
	Fit.center.call_deferred(self)

func _set_buttons(list: Array) -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for entry in list:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(160, 0)
		b.pressed.connect(entry[1])
		_buttons.add_child(b)
