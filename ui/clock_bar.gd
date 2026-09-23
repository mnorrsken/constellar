class_name ClockBar
extends PanelContainer
## Top-centre bar: the game date and the speed buttons (pause, 1x-8x).
## Space pauses/resumes, keys 1-4 pick a speed (handled in main.gd).

var _date := Label.new()
var _cash := Label.new()
var _buttons: Array[Button] = []

func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_top = 18
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_date.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 600))
	_date.add_theme_font_size_override("font_size", 20)
	_date.custom_minimum_size = Vector2(150, 0)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_date)
	var group := ButtonGroup.new()
	var labels := ["||", "1×", "2×", "4×", "8×"]
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, 0)
		b.pressed.connect(Sim.set_speed.bind(i))
		box.add_child(b)
		_buttons.append(b)
	var sep := VSeparator.new()
	box.add_child(sep)
	_cash.add_theme_font_override("font", Fonts.MONO)
	_cash.add_theme_font_size_override("font_size", 17)
	_cash.add_theme_color_override("font_color", Color(0.98, 0.72, 0.3))
	_cash.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_cash)
	add_child(box)
	Events.company_changed.connect(func(_c): _refresh())
	Events.day_passed.connect(func(_d): _refresh())
	Events.speed_changed.connect(func(_s): _refresh())
	_refresh()

func _refresh() -> void:
	_date.text = Sim.world.date_string()
	var p: Company = Sim.player()
	_cash.text = "%s cr " % Format.thousands(roundi(p.cash))
	_cash.tooltip_text = "%s\nCash %s cr\nLoan %s of %s cr" % [p.name, Format.thousands(roundi(p.cash)),
		Format.thousands(roundi(p.loan)), Format.thousands(roundi(p.loan_max))]
	_buttons[Sim.speed].set_pressed_no_signal(true)
