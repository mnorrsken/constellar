class_name SystemView
extends Control
## Full-screen view of one star system, Elite II style but flat: one row per
## host star, bodies laid out by OrreryLayout (log distance, not to scale),
## habitable zone and snow line marked, the settlement ringed in amber.
## Hover a body for details; Esc or the close button returns to the map.

signal closed

const BG := Color(0.018, 0.026, 0.055, 1.0)
const AMBER := Color(0.98, 0.72, 0.3)
const MUTED := Color(0.55, 0.62, 0.74)
const HEADER_H := 170.0
const FOOTER_H := 96.0
## Right-hand column kept free for the settlement card.
const CARD_W := 440.0

var system: StarSystem
var _layout: Dictionary = {}
var _hovered := -1
var _time := 0.0

var _title := Label.new()
var _facts := Label.new()
var _info := Label.new()
var _card_panel := PanelContainer.new()
var _card := SettlementCard.new()

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_font_override("font", Fonts.weight(Fonts.DISPLAY, 700))
	_title.add_theme_font_size_override("font_size", 36)
	_title.position = Vector2(48, 36)
	_facts.add_theme_font_override("font", Fonts.MONO)
	_facts.add_theme_font_size_override("font_size", 15)
	_facts.add_theme_color_override("font_color", Color(0.45, 0.78, 0.86))
	_facts.position = Vector2(50, 88)
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_color", Color(0.86, 0.9, 0.97))
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.offset_left = 48
	_info.offset_top = -64
	_card_panel.anchor_left = 1.0
	_card_panel.anchor_right = 1.0
	_card_panel.offset_left = -420
	_card_panel.offset_right = -40
	_card_panel.offset_top = 28
	_card_panel.offset_bottom = 28  # zero height: grows to fit the card
	_card_panel.add_child(_card)
	var close := Button.new()
	close.text = "✕  Close   Esc"
	close.focus_mode = Control.FOCUS_NONE
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.anchor_top = 1.0
	close.anchor_bottom = 1.0
	close.offset_left = -190
	close.offset_right = -40
	close.offset_top = -68
	close.offset_bottom = -32
	close.pressed.connect(close_view)
	for c in [_title, _facts, _info, _card_panel, close]:
		add_child(c)

func open(s: StarSystem) -> void:
	system = s
	_hovered = -1
	_title.text = s.name
	var types := PackedStringArray()
	for star in s.stars:
		types.append("%s %s" % [star.get("name", "?"), Format.spectral(star)])
	var where := "home of the Concordance" if s.id == "sol" else "%.2f ly from Sol" % s.position.length()
	_facts.text = "%s\n%s" % ["   ·   ".join(types), where]
	_card.show_system(s)
	visible = true
	# Controls grow with their content but never shrink: reset to zero height
	# after the layout pass so a shorter card doesn't keep the old height.
	(func(): _card_panel.offset_bottom = _card_panel.offset_top).call_deferred()
	_relayout()
	_update_info()

func close_view() -> void:
	visible = false
	closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_relayout()

func _relayout() -> void:
	var r := Rect2(Vector2(24, HEADER_H), size - Vector2(48 + CARD_W, HEADER_H + FOOTER_H))
	_layout = OrreryLayout.build(system, r)
	queue_redraw()

func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm == null or _layout.is_empty():
		return
	var best := -1
	var best_d := 22.0
	for row in _layout.rows:
		for b in row.bodies:
			var d: float = mm.position.distance_to(Vector2(b.x, row.y))
			if d < maxf(best_d, b.r + 6.0) and (best < 0 or d < best_d):
				best_d = d
				best = b.planet
	if best != _hovered:
		_hovered = best
		_update_info()

func _update_info() -> void:
	if _hovered < 0:
		_info.text = "Hover a planet for details"
		_info.add_theme_color_override("font_color", MUTED)
		return
	var p := system.planets[_hovered]
	var bits := PackedStringArray([p.name, Defs.planet_type(p.type).get("name", p.type), Format.au(p.orbit_au)])
	if p.type != "belt":
		bits.append("%s Earth masses" % str(snappedf(p.mass_earth, 0.01 if p.mass_earth < 10.0 else 1.0)))
	bits.append("%d K" % roundi(p.temperature_k))
	if p.tidally_locked:
		bits.append("tidally locked")
	if p.known and system.id != "sol":
		bits.append("known exoplanet")
	_info.text = "   ·   ".join(bits)
	_info.add_theme_color_override("font_color", Color(0.86, 0.9, 0.97))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if _layout.is_empty():
		return
	var font := Fonts.BODY
	var n_rows: int = _layout.rows.size()
	var row_h: float = (size.y - HEADER_H - FOOTER_H) / maxi(n_rows, 1)
	row_h = minf(row_h, OrreryLayout.MAX_ROW_HEIGHT)
	var half := row_h * 0.32
	for row in _layout.rows:
		var y: float = row.y
		var host: Dictionary = system.hosts[row.host]
		var right := size.x - 40.0 - CARD_W
		draw_line(Vector2(row.star_x, y), Vector2(right, y), Color(0.4, 0.6, 0.8, 0.08), 1.0)
		if row.hz != Vector2.ZERO:
			var hz: Vector2 = row.hz
			draw_rect(Rect2(hz.x, y - half, hz.y - hz.x, half * 2.0), Color(0.3, 0.85, 0.5, 0.07))
			draw_string(font, Vector2(hz.x + 4, y - half + 12), "HABITABLE ZONE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.9, 0.6, 0.5))
		if row.snow_x > 0.0:
			draw_dashed_line(Vector2(row.snow_x, y - half), Vector2(row.snow_x, y + half),
				Color(0.55, 0.8, 1.0, 0.28), 1.0, 5.0)
			draw_string(font, Vector2(row.snow_x + 4, y - half + 12), "snow line",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.8, 1.0, 0.5))
		_draw_host(row, host, y)
		_draw_bodies(row, y, half)

func _draw_host(row: Dictionary, host: Dictionary, y: float) -> void:
	var members: Array = host.stars
	var r: float = row.star_r
	for k in members.size():
		var star: Dictionary = system.stars[members[k]]
		var c := StarLook.color(star.get("class", ""), star.get("subclass"))
		var p := Vector2(row.star_x, y + (k - (members.size() - 1) * 0.5) * r * 1.3)
		var rr := r / sqrt(members.size())
		for g in range(6, 0, -1):
			draw_circle(p, rr * (1.0 + g * 0.45), Color(c, 0.035 * (7 - g)))
		draw_circle(p, rr, c.lerp(Color.WHITE, 0.35))
	var label := PlanetGen.host_label(host)
	draw_string(Fonts.DISPLAY, Vector2(row.star_x - 70, y + r + 30), label,
		HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(0.86, 0.9, 0.97, 0.9))

func _draw_bodies(row: Dictionary, y: float, half: float) -> void:
	var font := Fonts.BODY
	for i in row.bodies.size():
		var b: Dictionary = row.bodies[i]
		var p := system.planets[b.planet]
		var pos := Vector2(b.x, y)
		var radius: float = b.x - row.star_x
		var arc := minf(0.5, half / maxf(radius, 1.0))
		draw_arc(Vector2(row.star_x, y), radius, -arc, arc, 32, Color(0.5, 0.7, 0.95, 0.16), 1.0, true)
		var col := Color.html(Defs.planet_type(p.type).get("color", "aaaaaa"))
		if p.type == "belt":
			for k in 16:
				var t := (k / 15.0 - 0.5) * 2.0
				var jitter := sin(k * 12.9898 + b.planet) * 3.0
				draw_circle(pos + Vector2(jitter, t * half * 0.8), 1.6, Color(col, 0.8))
		else:
			draw_circle(pos, b.r, col)
			draw_circle(pos + Vector2(-b.r * 0.3, -b.r * 0.3), b.r * 0.45, Color(col.lightened(0.35), 0.5))
			if p.is_giant():
				for k in [-0.35, 0.2]:
					draw_line(pos + Vector2(-b.r * 0.85, k * b.r), pos + Vector2(b.r * 0.85, k * b.r),
						Color(col.darkened(0.25), 0.8), 1.5)
			if p.tidally_locked:
				draw_arc(pos, b.r * 0.5, -PI * 0.5, PI * 0.5, 16, Color(0, 0, 0, 0.45), b.r, true)
		if b.planet == _hovered:
			draw_arc(pos, b.r + 6.0, 0, TAU, 40, Color(1, 1, 1, 0.8), 1.5, true)
		var st := system.settlement
		if st and st.planet == b.planet:
			var pulse := 0.6 + 0.4 * sin(_time * 2.5)
			draw_arc(pos, b.r + 9.0, 0, TAU, 48, Color(AMBER, pulse), 2.0, true)
			draw_string(Fonts.DISPLAY, pos + Vector2(-80, -b.r - 18), st.name,
				HORIZONTAL_ALIGNMENT_CENTER, 160, 17, AMBER)
	_draw_labels(row, y, font)
	if system.settlement and system.settlement.planet < 0 and row.host == 0:
		var sp := Vector2(row.star_x + row.star_r + 40.0, y - half * 0.6)
		draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), AMBER, false, 2.0)
		draw_string(Fonts.DISPLAY, sp + Vector2(12, 5), system.settlement.name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, AMBER)

## Body labels: a letter (or name) with the type name under it where there
## is room. The settlement's body is labelled first (below, clear of its
## ring); every other label goes below if that spot is free, else above,
## else it is left out (hovering still shows everything).
func _draw_labels(row: Dictionary, y: float, font: Font) -> void:
	var st := system.settlement
	var below := []  # taken [left, right] spans
	var above := []
	var order := range(row.bodies.size())
	order.sort_custom(func(a, b): return _is_home(row.bodies[a]) and not _is_home(row.bodies[b]))
	for i in order:
		var b: Dictionary = row.bodies[i]
		var p := system.planets[b.planet]
		var text := _short_name(p)
		if _is_home(b) and text == st.name:
			continue
		var type_name: String = Defs.planet_type(p.type).get("name", p.type)
		var show_type := _room(row.bodies, i) >= 120.0
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var w_below := maxf(w, font.get_string_size(type_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) \
			if show_type else w
		var span_below := Vector2(b.x - w_below * 0.5 - 4.0, b.x + w_below * 0.5 + 4.0)
		var span_above := Vector2(b.x - w * 0.5 - 4.0, b.x + w * 0.5 + 4.0)
		var ly := 0.0
		if _is_home(b) or _free(below, span_below):
			below.append(span_below)
			ly = y + b.r + (27.0 if _is_home(b) else 18.0)
		elif _free(above, span_above):
			above.append(span_above)
			ly = y - b.r - 10.0
			show_type = false
		else:
			continue
		draw_string(font, Vector2(b.x - 60, ly), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15,
			Color(0.86, 0.9, 0.97, 0.85))
		if show_type:
			draw_string(font, Vector2(b.x - 60, ly + 16), type_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12,
				Color(MUTED, 0.85))

func _is_home(b: Dictionary) -> bool:
	return system.settlement != null and system.settlement.planet == b.planet

static func _free(spans: Array, span: Vector2) -> bool:
	for other in spans:
		if span.x < other.y and other.x < span.y:
			return false
	return true

## Horizontal space (px) between body i and its nearest neighbour in the row.
func _room(bodies: Array, i: int) -> float:
	var room := INF
	if i > 0:
		room = bodies[i].x - bodies[i - 1].x
	if i < bodies.size() - 1:
		room = minf(room, bodies[i + 1].x - bodies[i].x)
	return room

## "Tau Ceti f" -> "f"; "Earth" stays "Earth".
func _short_name(p: Planet) -> String:
	var label := PlanetGen.host_label(system.hosts[p.host])
	if p.name.begins_with(label + " "):
		return p.name.substr(label.length() + 1)
	return p.name
