class_name Sparkline
extends Control
## Tiny price chart: the last weeks of one commodity's price, with a faint
## line at the base price. Green when the latest price is below base, amber
## above.

var values := PackedFloat32Array()
var base := 1.0

func _init() -> void:
	custom_minimum_size = Vector2(110, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_data(series: PackedFloat32Array, base_price: float) -> void:
	values = series
	base = base_price
	queue_redraw()

func _draw() -> void:
	if values.size() < 2:
		return
	var lo := base
	var hi := base
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span := maxf(hi - lo, base * 0.05)
	var h := size.y - 4.0
	var y_of := func(v: float) -> float: return 2.0 + h - (v - lo) / span * h
	draw_line(Vector2(0, y_of.call(base)), Vector2(size.x, y_of.call(base)), Color(1, 1, 1, 0.12), 1.0)
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(size.x * i / (values.size() - 1), y_of.call(values[i])))
	var c := Color(0.45, 0.85, 0.55) if values[-1] <= base else Color(0.98, 0.72, 0.3)
	draw_polyline(pts, c, 1.5, true)
