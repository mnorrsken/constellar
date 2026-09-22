class_name OrreryLayout
## Where things go in the system view: one row per host star (or close
## pair), star on the left, bodies to the right at log-scaled distance.
## Not to scale on purpose; bodies are pushed apart so none overlap. Pure
## maths, so it is tested for every system.

const STAR_X := 70.0
const FIRST_BODY_X := 170.0
const RIGHT_MARGIN := 60.0
const MIN_GAP := 16.0
const BELT_RADIUS := 9.0
const MAX_ROW_HEIGHT := 240.0

## Returns {rows: [...], lo_au, hi_au}. Each row: host (index), y, star_x,
## star_r, hz (Vector2 of x, or Vector2.ZERO if off the row), snow_x (-1 if
## off the row), bodies: [{planet, x, r}] sorted by x.
static func build(system: StarSystem, rect: Rect2) -> Dictionary:
	var lo := INF
	var hi := 0.0
	for p in system.planets:
		lo = minf(lo, p.orbit_au)
		hi = maxf(hi, p.orbit_au)
	if system.planets.is_empty():
		lo = 0.01
		hi = 10.0
	lo /= 1.6
	hi *= 1.6
	# At least two decades of distance, so one or two bodies don't fill the row.
	if system.planets.size() <= 2 and hi / lo < 100.0:
		var mid := sqrt(lo * hi)
		lo = mid / 10.0
		hi = mid * 10.0
	var x0 := rect.position.x + FIRST_BODY_X
	var x1 := rect.end.x - RIGHT_MARGIN
	var n_rows := maxi(system.hosts.size(), 1)
	var row_h := minf(rect.size.y / n_rows, MAX_ROW_HEIGHT)
	var top := rect.position.y + (rect.size.y - row_h * n_rows) * 0.5

	var rows := []
	for h in system.hosts.size():
		var host: Dictionary = system.hosts[h]
		var bodies := []
		for i in system.planets.size():
			var p := system.planets[i]
			if p.host != h:
				continue
			bodies.append({"planet": i, "x": x_for(p.orbit_au, lo, hi, x0, x1), "r": body_radius(p)})
		_spread(bodies, x0, x1)
		var lum: float = host.luminosity
		var hz_in := x_for(0.95 * sqrt(lum), lo, hi, x0, x1)
		var hz_out := x_for(1.37 * sqrt(lum), lo, hi, x0, x1)
		var snow := PlanetGen.snow_line_au(lum)
		rows.append({
			"host": h,
			"y": top + row_h * (h + 0.5),
			"star_x": rect.position.x + STAR_X,
			"star_r": clampf(12.0 + 5.0 * log(maxf(lum, 1e-6)) / log(10.0), 5.0, 30.0),
			"hz": Vector2(hz_in, hz_out) if hz_out > x0 and hz_in < x1 else Vector2.ZERO,
			"snow_x": x_for(snow, lo, hi, x0, x1) if snow > lo and snow < hi else -1.0,
			"bodies": bodies,
		})
	return {"rows": rows, "lo_au": lo, "hi_au": hi}

## Log-scale position of an orbit between x0 (lo AU) and x1 (hi AU).
static func x_for(a: float, lo: float, hi: float, x0: float, x1: float) -> float:
	var t := (log(maxf(a, 1e-6)) - log(lo)) / (log(hi) - log(lo))
	return x0 + clampf(t, 0.0, 1.0) * (x1 - x0)

static func body_radius(p: Planet) -> float:
	if p.type == "belt":
		return BELT_RADIUS
	return clampf(4.0 + 2.2 * log(1.0 + p.mass_earth * 10.0) / log(10.0), 4.0, 14.0)

## Pushes bodies right so none overlap; if that runs past x1, squeezes the
## row back between x0 and x1 and pushes again with a smaller gap.
static func _spread(bodies: Array, x0: float, x1: float) -> void:
	bodies.sort_custom(func(a, b): return a.x < b.x)
	for gap in [MIN_GAP, MIN_GAP * 0.4, 0.0]:
		for i in range(1, bodies.size()):
			var need: float = bodies[i - 1].x + bodies[i - 1].r + bodies[i].r + gap
			bodies[i].x = maxf(bodies[i].x, need)
		if bodies.is_empty() or bodies[-1].x <= x1:
			return
		var first: float = bodies[0].x
		var last: float = bodies[-1].x
		var target_last := x1
		var target_first := minf(first, x0)
		for b in bodies:
			b.x = target_first + (b.x - first) * (target_last - target_first) / maxf(last - first, 1e-6)
