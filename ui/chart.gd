class_name Chart
extends Control
## A small money chart for the finance screen: monthly bars (green above
## zero, red below), or one line per series (a ship's monthly result), with
## a zero line, the top and bottom values and month labels under the axis.

const MUTED := Color(0.55, 0.62, 0.74)
const GREEN := Color(0.45, 0.85, 0.55)
const RED := Color(1.0, 0.45, 0.4)
const PAD := Vector2(52, 22)  # left for values, bottom for months

## [{name, color, values (Array of float)}]; bars use the first series.
var series: Array = []
var labels := PackedStringArray()
var bars := true

var _font := Fonts.MONO

func _init() -> void:
	custom_minimum_size = Vector2(560, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_bars(values: Array, month_labels: PackedStringArray) -> void:
	bars = true
	series = [{"name": "", "color": GREEN, "values": values}]
	labels = month_labels
	queue_redraw()

func set_lines(lines: Array, month_labels: PackedStringArray) -> void:
	bars = false
	series = lines
	labels = month_labels
	queue_redraw()

func _draw() -> void:
	var n := labels.size()
	if n == 0 or series.is_empty():
		return
	var lo := 0.0
	var hi := 0.0
	for s in series:
		for v in s.values:
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if hi - lo < 1.0:
		hi = lo + 1.0
	var area := Rect2(PAD.x, 4.0, size.x - PAD.x - 4.0, size.y - PAD.y - 8.0)
	var y_of := func(v: float) -> float: return area.position.y + area.size.y * (hi - v) / (hi - lo)
	var step := area.size.x / n
	# Grid: zero line, top and bottom values.
	draw_line(Vector2(area.position.x, y_of.call(0.0)), Vector2(area.end.x, y_of.call(0.0)), Color(1, 1, 1, 0.25), 1.0)
	for v in [hi, lo]:
		if absf(v) > 0.5:
			draw_line(Vector2(area.position.x, y_of.call(v)), Vector2(area.end.x, y_of.call(v)), Color(1, 1, 1, 0.07), 1.0)
			draw_string(_font, Vector2(0, y_of.call(v) + 4), Format.money_short(v), HORIZONTAL_ALIGNMENT_RIGHT,
				PAD.x - 8, 11, MUTED)
	draw_string(_font, Vector2(0, y_of.call(0.0) + 4), "0", HORIZONTAL_ALIGNMENT_RIGHT, PAD.x - 8, 11, MUTED)
	# Month labels: every few months so they don't collide.
	var every := maxi(1, ceili(n / 8.0))
	for i in range(0, n, every):
		draw_string(_font, Vector2(area.position.x + step * i, size.y - 4), labels[i], HORIZONTAL_ALIGNMENT_LEFT,
			step * every, 11, MUTED)
	if bars:
		var values: Array = series[0].values
		for i in values.size():
			var v: float = values[i]
			var top: float = y_of.call(maxf(v, 0.0))
			var bottom: float = y_of.call(minf(v, 0.0))
			var r := Rect2(area.position.x + step * i + step * 0.15, top, step * 0.7, maxf(bottom - top, 1.0))
			draw_rect(r, Color(GREEN if v >= 0.0 else RED, 0.85))
		return
	for s in series:
		var pts := PackedVector2Array()
		for i in s.values.size():
			pts.append(Vector2(area.position.x + step * (i + 0.5), y_of.call(s.values[i])))
		if pts.size() >= 2:
			draw_polyline(pts, s.color, 2.0, true)
		for p in pts:
			draw_circle(p, 2.5, s.color)
