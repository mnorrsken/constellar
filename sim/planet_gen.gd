class_name PlanetGen
## Fills a StarSystem with planets: real ones from data/known_planets.json
## first, then rolled ones, loosely following real astronomy:
## - habitable zone ~ sqrt(L) AU, snow line ~ 2.7 sqrt(L) AU; rocky worlds
##   inside, giants mostly beyond;
## - red dwarfs get small, close, often tidally locked planets;
## - white dwarfs keep debris belts; giant stars have swallowed their inner
##   planets;
## - in multiple systems each star (or close pair, orbited together) only
##   keeps planets inside ~0.3x the distance to its nearest companion.
## All randomness comes from the rng passed in (seeded per star system).

## Stars closer than this (AU) are orbited together, as one host.
const CLOSE_PAIR_AU := 0.5
const COMPANION_LIMIT := 0.3
const CIRCUMBINARY_FACTOR := 3.0
const MAX_ORBIT_AU := 80.0
const GIANT_STAR_CLASSES := ["I", "Ia", "Ib", "II", "III"]
const LETTERS := "bcdefghijklmnopqrstuvwxyz"

static func generate(system: StarSystem, rng: RandomNumberGenerator, known: Dictionary) -> void:
	system.hosts = build_hosts(system, rng, known.get("separations", []))
	var star_host := {}  # star index -> host index
	for h in system.hosts.size():
		for s in system.hosts[h].stars:
			star_host[s] = h

	var by_host := {}  # host index -> Array of known planet dicts
	for kp in known.get("planets", []):
		var star := _star_index(system, kp.get("star", ""))
		if star < 0:
			push_warning("[PlanetGen] %s: unknown star '%s'" % [system.id, kp.get("star")])
			continue
		by_host.get_or_add(star_host[star], []).append(kp)

	var planets: Array[Planet] = []
	for h in system.hosts.size():
		var host := system.hosts[h]
		var list: Array[Planet] = []
		var outermost := 0.0
		for kp in by_host.get(h, []):
			var p := _known_planet(host, h, kp, rng)
			list.append(p)
			outermost = maxf(outermost, p.orbit_au)
		if not known.get("complete", false):
			var min_au := outermost * 2.0 if outermost > 0.0 else 0.0
			list.append_array(_roll_planets(host, h, rng, min_au))
		list.sort_custom(func(x: Planet, y: Planet) -> bool: return x.orbit_au < y.orbit_au)
		_name_generated(host, list)
		planets.append_array(list)
	system.planets = planets

## Groups the system's stars into hosts. `separations` are curated
## [star name, star name, AU] triples; unknown companions get a rolled
## distance to the primary.
static func build_hosts(system: StarSystem, rng: RandomNumberGenerator, separations: Array) -> Array[Dictionary]:
	var n := system.stars.size()
	var seps := {}  # Vector2i(i, j) with i < j -> AU
	for triple in separations:
		var i := _star_index(system, triple[0])
		var j := _star_index(system, triple[1])
		if i < 0 or j < 0:
			push_warning("[PlanetGen] %s: bad separation %s" % [system.id, triple])
			continue
		seps[Vector2i(mini(i, j), maxi(i, j))] = float(triple[2])
	for k in range(1, n):
		var paired := false
		for key in seps:
			if key.x == k or key.y == k:
				paired = true
		if not paired:
			seps[Vector2i(0, k)] = exp(rng.randf_range(log(0.05), log(3000.0)))

	# Merge close pairs.
	var group := range(n)
	for key in seps:
		if seps[key] < CLOSE_PAIR_AU:
			var gi: int = group[key.x]
			var gj: int = group[key.y]
			for s in n:
				if group[s] == gj:
					group[s] = gi

	var hosts: Array[Dictionary] = []
	var seen := {}
	for s in n:
		var g: int = group[s]
		if seen.has(g):
			continue
		seen[g] = true
		var members: Array[int] = []
		for t in n:
			if group[t] == g:
				members.append(t)
		var lum := 0.0
		var mass := 0.0
		for t in members:
			lum += float(system.stars[t].get("luminosity", 0.0))
			mass += float(system.stars[t].get("mass", 0.0))
		var inner := 0.0
		var outer := INF
		for key in seps:
			var in_x: bool = members.has(key.x)
			var in_y: bool = members.has(key.y)
			if in_x and in_y:
				inner = maxf(inner, seps[key] * CIRCUMBINARY_FACTOR)
			elif in_x or in_y:
				outer = minf(outer, seps[key] * COMPANION_LIMIT)
		var first: Dictionary = system.stars[members[0]]
		var names := PackedStringArray()
		for t in members:
			names.append(system.stars[t].get("name", "?"))
		hosts.append({
			"name": " + ".join(names), "stars": members,
			"luminosity": lum, "mass": mass,
			"class": first.get("class", ""), "lum_class": first.get("lum_class", ""),
			"inner_au": inner, "outer_au": outer,
		})
	return hosts

## Equilibrium temperature (K) of a body at `a` AU from a host of luminosity L.
static func temperature(luminosity: float, a: float) -> float:
	return 278.0 * pow(maxf(luminosity, 1e-9), 0.25) / sqrt(maxf(a, 1e-6))

static func habitable_zone_au(luminosity: float) -> float:
	return sqrt(maxf(luminosity, 0.0))

static func snow_line_au(luminosity: float) -> float:
	return 2.7 * sqrt(maxf(luminosity, 0.0))

## Picks a planet type from mass (Earth masses) and temperature (K).
## Rolls only where nature could go several ways (temperate and cold rocks).
static func classify(mass: float, temp: float, locked: bool, host_class: String,
		rng: RandomNumberGenerator) -> String:
	if mass >= 50.0:
		return "gas_giant"
	if mass >= 10.0:
		return "ice_giant"
	if temp > 800.0:
		return "molten"
	if mass < 0.12:
		return "ice" if temp < 170.0 and rng.randf() < 0.5 else "barren"
	if temp > 350.0:
		return "desert" if mass > 0.3 else "barren"
	if temp >= 230.0:
		if locked:
			return "tidally_locked"
		var r := rng.randf()
		if host_class in ["F", "G", "K"] and r < 0.12:
			return "garden"
		if r < 0.5:
			return "ocean"
		if r < 0.75:
			return "desert"
		return "barren"
	if temp >= 150.0:
		return "ice" if rng.randf() < 0.5 else "barren"
	return "ice" if rng.randf() < 0.6 else "barren"

# --- internals -----------------------------------------------------------------

static func _star_index(system: StarSystem, star_name: String) -> int:
	if star_name == "":
		return 0
	for i in system.stars.size():
		if system.stars[i].get("name", "") == star_name:
			return i
	return -1

static func _is_locked(host: Dictionary, a: float) -> bool:
	return a < 0.4 * pow(maxf(host.mass, 0.01), 1.0 / 3.0)

static func _make(host: Dictionary, h: int, a: float, mass: float, type: String) -> Planet:
	var p := Planet.new()
	p.host = h
	p.orbit_au = a
	p.mass_earth = mass
	p.type = type
	p.temperature_k = temperature(host.luminosity, a)
	p.tidally_locked = type != "belt" and _is_locked(host, a)
	return p

static func _known_planet(host: Dictionary, h: int, kp: Dictionary, rng: RandomNumberGenerator) -> Planet:
	var a := float(kp.a)
	var type: String = kp.get("type", "")
	var mass := float(kp.get("mass", 0.0))
	if type == "":
		type = classify(mass, temperature(host.luminosity, a), _is_locked(host, a), host["class"], rng)
	var p := _make(host, h, a, mass, type)
	p.known = true
	var n: String = kp.get("name", "")
	p.name = n if n.length() > 2 else ""
	if p.name == "":
		p.name = "%s %s" % [host_label(host), n]
	return p

static func _roll_planets(host: Dictionary, h: int, rng: RandomNumberGenerator, min_au: float) -> Array[Planet]:
	var out: Array[Planet] = []
	var cls: String = host["class"]
	var lum: float = host.luminosity
	if cls in ["L", "T", "Y"]:
		if rng.randf() < 0.3:
			var a := rng.randf_range(0.005, 0.05)
			var m := _log_uniform(rng, 0.05, 1.0)
			out.append(_make(host, h, a, m, classify(m, temperature(lum, a), true, cls, rng)))
		return out
	if cls == "D":
		var belt_a := maxf(rng.randf_range(0.005, 0.03), min_au)
		if belt_a < host.outer_au:
			out.append(_make(host, h, belt_a, 0.0, "belt"))
		if rng.randf() < 0.4:
			var a := rng.randf_range(3.0, 30.0)
			if a < host.outer_au and a > min_au:
				out.append(_make(host, h, a, _log_uniform(rng, 15.0, 600.0), "gas_giant"))
		return out

	var giant_star: bool = host.lum_class in GIANT_STAR_CLASSES
	var count: int
	match cls:
		"M":
			count = 0 if rng.randf() < 0.15 else rng.randi_range(1, 4)
		"K", "G", "F":
			count = rng.randi_range(2, 7)
		_:
			count = rng.randi_range(1, 4)
	if giant_star:
		count = rng.randi_range(0, 2)
		min_au = maxf(min_au, 0.25 * sqrt(lum))  # the inner system was swallowed

	var a := clampf(0.1 * sqrt(lum), 0.01, 1.5) * rng.randf_range(0.8, 1.6)
	a = maxf(a, maxf(min_au, host.inner_au * 1.2))
	var snow := snow_line_au(lum)
	var giants := 0
	for i in count:
		if a > host.outer_au or a > MAX_ORBIT_AU:
			break
		var p: Planet
		if rng.randf() < 0.1:
			p = _make(host, h, a, 0.0, "belt")
		else:
			var giant_chance := 0.12 if cls == "M" else (0.45 if giants == 0 else 0.3)
			var mass: float
			if a > snow and rng.randf() < giant_chance:
				mass = _log_uniform(rng, 10.0, 80.0) if a > 4.0 * snow else _log_uniform(rng, 20.0, 1500.0)
				giants += 1
			else:
				mass = _log_uniform(rng, 0.1, 4.0) if cls == "M" else _log_uniform(rng, 0.05, 6.0)
			var locked := _is_locked(host, a)
			p = _make(host, h, a, mass, classify(mass, temperature(lum, a), locked, cls, rng))
		out.append(p)
		a *= rng.randf_range(1.4, 2.3)
	return out

## Names rolled planets after their host with the next free letters; belts
## become "<host> Belt".
static func _name_generated(host: Dictionary, list: Array[Planet]) -> void:
	var used := {}
	for p in list:
		if p.name != "":
			used[p.name] = true
	var next := 0
	for p in list:
		if p.name != "":
			continue
		var label := host_label(host)
		if p.type == "belt":
			p.name = "%s Belt" % label
			var k := 2
			while used.has(p.name):
				p.name = "%s Belt %d" % [label, k]
				k += 1
		else:
			while used.has("%s %s" % [label, LETTERS[next]]):
				next += 1
			p.name = "%s %s" % [label, LETTERS[next]]
			next += 1
		used[p.name] = true

## Short label for a host, used in planet names: "Tau Ceti",
## "Castor Aa + Castor Ab" -> "Castor Aa-Ab".
static func host_label(host: Dictionary) -> String:
	var parts: PackedStringArray = host.name.split(" + ")
	if parts.size() == 1:
		return parts[0]
	var base := parts[0]
	var cut := base.rfind(" ")
	var suffixes := PackedStringArray()
	for part in parts:
		suffixes.append(part.substr(cut + 1) if cut >= 0 else part)
	return (base.substr(0, cut) + " " if cut >= 0 else "") + "-".join(suffixes)

static func _log_uniform(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	return exp(rng.randf_range(log(lo), log(hi)))
