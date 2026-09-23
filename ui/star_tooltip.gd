class_name StarTooltip
extends PanelContainer
## Small card next to the mouse describing the hovered star system.

const OFFSET := Vector2(18, 18)

var _title := Label.new()
var _facts := Label.new()
var _settlement := Label.new()
var _stars := RichTextLabel.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 600))
	_title.add_theme_font_size_override("font_size", 24)
	_facts.add_theme_font_override("font", Fonts.MONO)
	_facts.add_theme_font_size_override("font_size", 15)
	_facts.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))
	_settlement.add_theme_font_size_override("font_size", 16)
	_stars.bbcode_enabled = true
	_stars.fit_content = true
	_stars.scroll_active = false
	_stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stars.custom_minimum_size = Vector2(260, 0)
	_stars.add_theme_font_size_override("normal_font_size", 16)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_title)
	box.add_child(_facts)
	box.add_child(_settlement)
	box.add_child(_stars)
	add_child(box)

func show_system(g: Galaxy, i: int, mouse: Vector2) -> void:
	var s := g.systems[i]
	var charted: bool = Sim.player().is_known(i)
	_facts.visible = charted
	_settlement.visible = charted
	_stars.visible = charted
	if not charted:
		_title.text = "Uncharted system"
		_place(mouse)
		return
	_title.text = s.name
	var dist := s.position.length()
	var place := "home system" if s.id == "sol" else "%.2f ly from Sol" % dist
	var n_lanes := g.lanes_of(i).size()
	_facts.text = "%s  ·  %d lane%s" % [place, n_lanes, "" if n_lanes == 1 else "s"]
	var st := s.settlement
	if st:
		var people := "%s robots" % Format.population(st.robots) if st.robots > 0 \
			else Format.population(st.population)
		_settlement.text = "%s  ·  %s  ·  %s" % [st.name, Defs.archetype_name(st.archetype), people]
		_settlement.add_theme_color_override("font_color", Color(0.98, 0.72, 0.3))
	else:
		_settlement.text = "Uninhabited"
		_settlement.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	var lines := PackedStringArray()
	for star in s.stars:
		var c := StarLook.color(star.get("class", ""), star.get("subclass"))
		lines.append("[color=#%s]●[/color]  %s  [color=#8a9ab5]%s[/color]" % [
			c.to_html(false), star.get("name", "?"), Format.spectral(star)])
	_stars.text = "\n".join(lines)
	_place(mouse)

func _place(mouse: Vector2) -> void:
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	var pos := mouse + OFFSET
	if pos.x + size.x > vp.x - 8:
		pos.x = mouse.x - OFFSET.x - size.x
	if pos.y + size.y > vp.y - 8:
		pos.y = mouse.y - OFFSET.y - size.y
	position = pos
