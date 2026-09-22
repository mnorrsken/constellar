class_name SettlementCard
extends VBoxContainer
## Settlement facts for one star system: name, archetype and body, a short
## summary, then population, tech level, government and stability. Used by
## the map's system panel and by the system view.

const AMBER := Color(0.98, 0.72, 0.3)
const MUTED := Color(0.55, 0.62, 0.74)

var _name := Label.new()
var _where := Label.new()
var _summary := Label.new()
var _grid := GridContainer.new()

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_name.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 600))
	_name.add_theme_font_size_override("font_size", 21)
	_name.add_theme_color_override("font_color", AMBER)
	_where.add_theme_font_size_override("font_size", 15)
	_summary.add_theme_font_size_override("font_size", 14)
	_summary.add_theme_color_override("font_color", MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(300, 0)
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 3)
	for c in [_name, _where, _summary, _grid]:
		add_child(c)

func show_system(s: StarSystem) -> void:
	for child in _grid.get_children():
		child.queue_free()
	var st := s.settlement
	if st == null:
		_name.text = "Uninhabited"
		_name.add_theme_color_override("font_color", MUTED)
		_where.text = "No port, no market. Ships can still pass through."
		_summary.text = ""
		_summary.visible = false
		return
	_name.add_theme_color_override("font_color", AMBER)
	_name.text = st.name
	var body := "a deep-space station" if st.planet < 0 else s.planets[st.planet].name
	if st.planet >= 0 and st.is_station:
		body = "orbit of " + body
	_where.text = "%s on %s" % [Defs.archetype_name(st.archetype), body]
	_summary.visible = true
	_summary.text = Defs.world_content.archetypes.get(st.archetype, {}).get("summary", "")
	_row("Population", Format.population(st.population) if st.population > 0 else "none")
	if st.robots > 0:
		_row("Robots", Format.population(st.robots))
	_row("Tech level", "%d / 10" % st.tech_level)
	_row("Government", Defs.government_name(st.government))
	_row("Stability", "%s (%d%%)" % [_stability_word(st.stability), roundi(st.stability * 100.0)])

func _row(key: String, value: String) -> void:
	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", MUTED)
	var v := Label.new()
	v.text = value
	v.add_theme_font_override("font", Fonts.MONO)
	v.add_theme_font_size_override("font_size", 14)
	_grid.add_child(k)
	_grid.add_child(v)

static func _stability_word(x: float) -> String:
	if x < 0.3:
		return "unstable"
	if x < 0.6:
		return "uneasy"
	return "stable"
