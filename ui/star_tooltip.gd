class_name StarTooltip
extends PanelContainer
## Small card next to the mouse describing the hovered star system.

const OFFSET := Vector2(18, 18)

var _title := Label.new()
var _facts := Label.new()
var _stars := RichTextLabel.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 600))
	_title.add_theme_font_size_override("font_size", 24)
	_facts.add_theme_font_override("font", Fonts.MONO)
	_facts.add_theme_font_size_override("font_size", 14)
	_facts.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))
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
	box.add_child(_stars)
	add_child(box)

func show_system(g: Galaxy, i: int, mouse: Vector2) -> void:
	var s := g.systems[i]
	_title.text = s.name
	var dist := s.position.length()
	var place := "home system" if s.id == "sol" else "%.2f ly from Sol" % dist
	var n_lanes := g.lanes_of(i).size()
	_facts.text = "%s  ·  %d lane%s" % [place, n_lanes, "" if n_lanes == 1 else "s"]
	var lines := PackedStringArray()
	for star in s.stars:
		var c := StarLook.color(star.get("class", ""), star.get("subclass"))
		lines.append("[color=#%s]●[/color]  %s  [color=#8a9ab5]%s[/color]" % [
			c.to_html(false), star.get("name", "?"), _type_text(star)])
	_stars.text = "\n".join(lines)
	visible = true
	reset_size()
	var vp := get_viewport_rect().size
	var pos := mouse + OFFSET
	if pos.x + size.x > vp.x - 8:
		pos.x = mouse.x - OFFSET.x - size.x
	if pos.y + size.y > vp.y - 8:
		pos.y = mouse.y - OFFSET.y - size.y
	position = pos

func _type_text(star: Dictionary) -> String:
	var cls: String = star.get("class", "")
	match cls:
		"D":
			return "white dwarf"
		"L", "T", "Y":
			return "brown dwarf"
	var sub: Variant = star.get("subclass")
	var sub_text := "" if sub == null else str(snappedf(float(sub), 0.1)).trim_suffix(".0")
	var lum_class: String = star.get("lum_class", "")
	var kind := ""
	match lum_class:
		"III", "II", "Ia", "Ib", "I":
			kind = " giant"
		"IV":
			kind = " subgiant"
		_:
			kind = " dwarf" if cls in ["K", "M"] else ""
	return "%s%s%s" % [cls, sub_text, kind]
