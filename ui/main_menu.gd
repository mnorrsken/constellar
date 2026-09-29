class_name MainMenu
extends PanelContainer
## The main menu, over the paused map. At the first start: Continue (the
## newest save), New game, Load game, Quit. In play (Esc): also Resume and
## Save game. New game takes a seed (the planets and settlements; the stars
## and lanes never change) and a goal. A new game or a load reloads the main
## scene around the new world.

signal closed

const MUTED := Color(0.55, 0.62, 0.74)
const TEXT := Color(0.86, 0.9, 0.97)
const AMBER := Color(0.98, 0.72, 0.3)
const WIDTH := 460.0

## Opened from play (Resume and Save shown; Esc closes it).
var in_game := false

var _pages := {}
var _continue := Button.new()
var _resume := Button.new()
var _save_button := Button.new()
var _seed := LineEdit.new()
var _goal := OptionButton.new()
var _goal_ids: Array[String] = [""]
var _load_list := VBoxContainer.new()
var _save_name := LineEdit.new()
var _save_list := VBoxContainer.new()
var _resume_speed := 1
var _newest := ""

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
	var title := Label.new()
	title.text = "CONSTELLAR"
	title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := Label.new()
	sub.text = "MERCHANT EMPIRE"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", AMBER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(sub)
	box.add_child(HSeparator.new())
	for page in [_main_page(), _new_page(), _load_page(), _save_page()]:
		box.add_child(page)
	add_child(box)

## Opens the menu; `playing`: from the game (Resume, Save, Esc closes).
func open(playing: bool) -> void:
	in_game = playing
	if Sim.speed > 0:
		_resume_speed = Sim.speed
	Sim.set_speed(0)
	_resume.visible = playing
	_save_button.visible = playing
	var saves := SaveGame.list()
	_continue.disabled = saves.is_empty()
	_newest = saves[0].path if not saves.is_empty() else ""
	_continue.text = "Continue  ·  %s" % _describe(saves[0]) if not saves.is_empty() else "Continue"
	_show("main")
	visible = true
	Motion.pop_in(self)

func close_panel() -> void:
	if not in_game:
		return  # at the start there is nothing to go back to
	visible = false
	Sim.set_speed(_resume_speed)
	closed.emit()

## Esc: back to the main page, or close from there.
func back() -> void:
	if not _pages.main.visible:
		_show("main")
	else:
		close_panel()

# --- pages ----------------------------------------------------------------------------

func _main_page() -> Control:
	var page := _page("main")
	_continue.pressed.connect(func(): _load(_newest))
	for b in [_resume, _continue]:
		page.add_child(b)
	_resume.text = "Resume"
	_resume.pressed.connect(close_panel)
	page.add_child(_button("New game", func(): _open_new()))
	page.add_child(_button("Load game", func(): _open_load()))
	_save_button.text = "Save game"
	_save_button.pressed.connect(_open_save)
	page.add_child(_save_button)
	page.add_child(_button("Quit", func(): get_tree().quit()))
	for b in page.get_children():
		_style(b)
	page.move_child(_resume, 0)
	return page

func _new_page() -> Control:
	var page := _page("new")
	page.add_child(_heading("New game"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	var seed_label := _note("Seed")
	seed_label.custom_minimum_size = Vector2(60, 0)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.tooltip_text = "The seed makes the planets and settlements; the stars and lanes are always the same."
	seed_row.add_child(seed_label)
	seed_row.add_child(_seed)
	seed_row.add_child(_button("New seed", func(): _seed.text = str(randi() % 1000000)))
	page.add_child(seed_row)
	var goal_row := HBoxContainer.new()
	goal_row.add_theme_constant_override("separation", 10)
	var goal_label := _note("Goal")
	goal_label.custom_minimum_size = Vector2(60, 0)
	_goal.focus_mode = Control.FOCUS_NONE
	_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goal.add_item("None: sandbox")
	var goals: Dictionary = Defs.world_content.balance.get("goals", {})
	for id in goals:
		var g: Dictionary = goals[id]
		_goal_ids.append(id)
		match id:
			"value":
				_goal.add_item("Company value %s cr" % Format.money_short(float(g.target)))
			"prince":
				_goal.add_item("%s: patron of %d systems" % [g.name, int(g.patrons)])
			_:
				_goal.add_item(str(g.get("name", id)))
	goal_row.add_child(goal_label)
	goal_row.add_child(_goal)
	page.add_child(goal_row)
	page.add_child(_note("You start at Lodestar on the rim with one worn Packet freighter, some cash and a bank loan."))
	page.add_child(_row([_button("Back", func(): _show("main")), _button("Start", _start)]))
	return page

func _load_page() -> Control:
	var page := _page("load")
	page.add_child(_heading("Load game"))
	_load_list.add_theme_constant_override("separation", 6)
	page.add_child(_load_list)
	page.add_child(_row([_button("Back", func(): _show("main"))]))
	return page

func _save_page() -> Control:
	var page := _page("save")
	page.add_child(_heading("Save game"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	_save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name.placeholder_text = "Name of the save"
	_save_name.text_submitted.connect(func(_t): _save())
	name_row.add_child(_save_name)
	name_row.add_child(_button("Save", _save))
	page.add_child(name_row)
	page.add_child(_note("Or pick a save to write over:"))
	_save_list.add_theme_constant_override("separation", 6)
	page.add_child(_save_list)
	page.add_child(_row([_button("Back", func(): _show("main"))]))
	return page

# --- actions -------------------------------------------------------------------------

func _open_new() -> void:
	_seed.text = str(randi() % 1000000)
	_goal.select(0)
	_show("new")

func _start() -> void:
	var seed_value := _seed.text.strip_edges().to_int()
	Sim.new_game(seed_value, _goal_ids[_goal.selected])
	_reload()

func _open_load() -> void:
	_clear(_load_list)
	var saves := SaveGame.list()
	if saves.is_empty():
		_load_list.add_child(_note("No saves yet."))
	for s in saves:
		var b := _button(_describe(s), func(): _load(s.path))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_load_list.add_child(b)
	_show("load")

func _load(path: String) -> void:
	if path != "" and Sim.load_game(path).ok:
		_reload()

func _open_save() -> void:
	_save_name.text = "%s %s" % [Sim.player().name.get_slice(" ", 0), Sim.world.date_string()]
	_clear(_save_list)
	for s in SaveGame.list():
		var b := _button(_describe(s), func(): _save_name.text = s.meta.get("name", s.name))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_save_list.add_child(b)
	_show("save")
	_save_name.grab_focus.call_deferred()

func _save() -> void:
	if _save_name.text.strip_edges() == "":
		return
	if Sim.save_game(_save_name.text.strip_edges()).ok:
		_save_name.release_focus()
		close_panel()

## The main scene again, around the new world (and no menu).
func _reload() -> void:
	Sim.show_menu = false
	get_tree().reload_current_scene()

# --- bits ------------------------------------------------------------------------------

## "autosave  ·  1 Jan 3405  ·  worth 1.2M cr  ·  saved 2026-09-28 14:03".
func _describe(s: Dictionary) -> String:
	var m: Dictionary = s.meta
	var parts := PackedStringArray([str(m.get("name", s.name))])
	if m.has("date"):
		parts.append(str(m.date))
	if m.has("value"):
		parts.append("worth %s cr" % Format.money_short(float(m.value)))
	if m.has("saved"):
		parts.append("saved %s" % str(m.saved).left(16))
	return "  ·  ".join(parts)

func _show(page: String) -> void:
	for k in _pages:
		_pages[k].visible = k == page
	Fit.center.call_deferred(self)

func _page(page_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.custom_minimum_size = Vector2(WIDTH, 0)
	_pages[page_name] = page
	return page

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	l.add_theme_font_size_override("font_size", 22)
	return l

func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	return l

func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	for b in buttons:
		row.add_child(b)
	return row

func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b

## The main page's big buttons.
func _style(b: Button) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(WIDTH, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.clip_text = true

func _clear(c: Container) -> void:
	for child in c.get_children():
		c.remove_child(child)
		child.queue_free()
