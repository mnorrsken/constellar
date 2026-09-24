class_name Hud
extends Control
## Screen furniture for the map: the wordmark and a line of control hints.
## The real game UI arrives in Milestone 9.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.text = "CONSTELLAR"
	title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700, 6))
	title.add_theme_font_size_override("font_size", 30)
	title.position = Vector2(32, 24)
	add_child(title)

	var sub := Label.new()
	sub.text = "MERCHANT EMPIRE"
	sub.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 500, 5))
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.95, 0.66, 0.23))
	sub.position = Vector2(35, 64)
	add_child(sub)

	var hints := Label.new()
	hints.text = "Drag  rotate   ·   Right-drag  pan   ·   Scroll  zoom   ·   Click  select   ·   M  market   ·   S  send   ·   O  orders   ·   V  fleet   ·   C  contracts   ·   N  news   ·   L  finances   ·   P  price map   ·   Z  drop lines   ·   Space  pause   ·   1–4  speed   ·   Home  Sol   ·   F1  debug"
	hints.add_theme_font_size_override("font_size", 14)
	hints.add_theme_color_override("font_color", Color(0.55, 0.64, 0.78, 0.8))
	# Full-width strip along the bottom edge.
	hints.anchor_left = 0.0
	hints.anchor_right = 1.0
	hints.anchor_top = 1.0
	hints.anchor_bottom = 1.0
	hints.offset_left = 32
	hints.offset_right = -32
	hints.offset_top = -44
	hints.offset_bottom = -20
	add_child(hints)
