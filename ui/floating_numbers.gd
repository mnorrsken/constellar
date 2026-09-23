class_name FloatingNumbers
extends Control
## Profit pop-ups: when a player ship sells cargo or delivers a contract,
## "+12,340 cr" (green) or "-3,100 cr" (red) rises from the ship on the map
## and fades out.

const LIFE := 2.8
const RISE_PX := 70.0

var camera: Camera3D
var markers: ShipMarkers

var _items: Array = []  # {pos: Vector3, text, color, age}
var _font := Fonts.weight(Fonts.DISPLAY, 700)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Events.profit.connect(_on_profit)

func _on_profit(ship_id: int, amount: float) -> void:
	if markers == null or absf(amount) < 0.5:
		return
	_items.append({
		"pos": markers.ship_position(ship_id),
		"text": "%s%s cr" % ["+" if amount > 0.0 else "−", Format.thousands(roundi(absf(amount)))],
		"color": Color(0.45, 0.95, 0.55) if amount > 0.0 else Color(1.0, 0.42, 0.38),
		"age": 0.0,
	})

func _process(delta: float) -> void:
	if _items.is_empty():
		return
	for it in _items:
		it.age += delta
	_items = _items.filter(func(it): return it.age < LIFE)
	queue_redraw()

func _draw() -> void:
	if camera == null:
		return
	for it in _items:
		if camera.is_position_behind(it.pos):
			continue
		var t: float = it.age / LIFE
		var p := camera.unproject_position(it.pos) - Vector2(0, 28 + RISE_PX * t)
		var a := 1.0 - smoothstep(0.65, 1.0, t)
		var w := _font.get_string_size(it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var at := p - Vector2(w * 0.5, 0)
		draw_string_outline(_font, at, it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0.02, 0.03, 0.07, 0.8 * a))
		draw_string(_font, at, it.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(it.color, a))
