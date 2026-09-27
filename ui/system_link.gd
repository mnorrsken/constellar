class_name SystemLink
extends LinkButton
## A star system's name as a link (underlined on hover): clicking it asks to
## show that system on the map. Panels connect `pressed` and pass the
## system on (usually closing themselves and emitting system_requested).

const COLOR := Color(0.55, 0.85, 1.0)

var system_index := -1

static func make(system_index: int, text: String, font_size := 14, color := COLOR) -> SystemLink:
	var l := SystemLink.new()
	l.system_index = system_index
	l.text = text
	l.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	l.focus_mode = Control.FOCUS_NONE
	l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.tooltip_text = "Show on the map"
	l.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		l.add_theme_color_override(state, color if state == "font_color" else color.lightened(0.3))
	return l
