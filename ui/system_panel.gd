class_name SystemPanel
extends PanelContainer
## Card on the right of the map for the selected star system.

signal view_requested

const WIDTH := 380.0

var _title := Label.new()
var _facts := Label.new()
var _bodies := Label.new()
var _card := SettlementCard.new()
var _button := Button.new()

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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	for c in [_title, _facts, HSeparator.new(), _card, HSeparator.new(), _bodies, _button]:
		box.add_child(c)
	add_child(box)

func show_system(s: StarSystem) -> void:
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
	visible = true
	_fit.call_deferred()

## Shrinks back to the content height (Controls grow by themselves but never
## shrink when their content gets shorter).
func _fit() -> void:
	offset_bottom = offset_top
