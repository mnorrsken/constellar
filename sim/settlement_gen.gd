class_name SettlementGen
## Decides whether a system is inhabited and what its settlement is like.
## Driven by data: region (distance from Sol), the best body to live on,
## archetype weights by body type and region (archetypes.json), government
## weights (governments.json) and ranges in balance.json "settlements".
## Names are given later by World, which keeps them unique.

## "core", "inner" or "rim", from distance to Sol in light years.
static func region_of(distance_ly: float, balance: Dictionary) -> String:
	var r: Dictionary = balance.get("regions", {})
	if distance_ly <= float(r.get("core_ly", 12.0)):
		return "core"
	if distance_ly <= float(r.get("inner_ly", 25.0)):
		return "inner"
	return "rim"

## Returns a settlement or null. `forced` (from balance.json) pins fields for
## special systems (Sol, the start world) and always makes a settlement.
## `lanes` is the system's lane count: systems nobody settled may still hold
## a robot world, most often dead ends (1-2 lanes) out of the way.
static func generate(system: StarSystem, rng: RandomNumberGenerator, content: Dictionary,
		forced: Dictionary = {}, lanes := 99) -> Settlement:
	var balance: Dictionary = content.balance
	var cfg: Dictionary = balance.get("settlements", {})
	var region := region_of(system.position.length(), balance)

	var chance := float(cfg.get("inhabited_chance", {}).get(region, 0.5))
	if _only_class(system, ["L", "T", "Y"]):
		chance *= 0.5
	elif _only_class(system, ["D"]):
		chance *= 0.7
	var roll := rng.randf()
	var robot_world := false
	if forced.is_empty() and roll >= chance:
		var robot_chance: Dictionary = cfg.get("robot_world_chance", {})
		var rc := float(robot_chance.get("leaf" if lanes <= 2 else "other", 0.0))
		if region == "core" or rng.randf() >= rc:
			return null
		robot_world = true

	var s := Settlement.new()
	var pick := _pick_body_and_archetype(system, region, rng, content, "robot" if robot_world else "")
	s.planet = pick[0]
	s.archetype = pick[1]
	if forced.has("planet"):
		s.planet = _planet_named(system, forced.planet)
	s.archetype = forced.get("archetype", s.archetype)
	var body_type := "station" if s.planet < 0 else system.planets[s.planet].type
	s.is_station = s.planet < 0 or body_type in ["gas_giant", "ice_giant", "belt"]
	var arch: Dictionary = content.archetypes[s.archetype]
	var habit := 0.2 if s.planet < 0 else float(content.planet_types[body_type].get("habitability", 0.2))

	# Archetypes may bring their own ranges (robot worlds do).
	if arch.has("population_log10"):
		var own: Array = arch.population_log10
		s.population = int(forced.get("population", roundi(pow(10.0, rng.randf_range(own[0], own[1]))) - 1))
	else:
		var pop_range: Array = cfg.get("population_log10", {}).get(region, [4.0, 6.0])
		var pop := pow(10.0, rng.randf_range(pop_range[0], pop_range[1]))
		pop *= float(arch.get("population_factor", 1.0)) * (0.3 + habit)
		s.population = int(forced.get("population", maxf(pop, 500.0)))
	if arch.has("robots_log10"):
		var r: Array = arch.robots_log10
		s.robots = roundi(pow(10.0, rng.randf_range(r[0], r[1])))

	var tech_range: Array = arch.get("tech_level", cfg.get("tech_level", {}).get(region, [3, 6]))
	var tech := rng.randi_range(int(tech_range[0]), int(tech_range[1])) + int(arch.get("tech_bonus", 0))
	s.tech_level = int(forced.get("tech_level", clampi(tech, 1, 10)))

	s.government = forced.get("government",
		arch.get("government", _pick_government(region, s.archetype, rng, content.governments)))
	var jitter := float(cfg.get("stability_jitter", 0.15))
	var stab := float(content.governments[s.government].get("stability", 0.6)) + rng.randf_range(-jitter, jitter)
	s.stability = float(forced.get("stability", clampf(stab, 0.05, 0.95)))
	s.name = forced.get("name", "")
	return s

## Weight of an archetype for a body type ("station" = deep-space station).
static func body_weight(archetype: Dictionary, body_type: String) -> float:
	var w: Dictionary = archetype.get("body_weights", {})
	return float(w.get(body_type, w.get("*", 0.0)))

## Picks where people live and what they do there in one weighted draw over
## every (body, archetype) pair: archetype fit for the body type x region
## weight x how pleasant the body is (+ a base, so giants and belts still
## get refineries and mines). Returns [planet index or -1, archetype id].
## With `only` set, just that archetype, by body fit alone (robots don't care
## where humans would like to live).
static func _pick_body_and_archetype(system: StarSystem, region: String,
		rng: RandomNumberGenerator, content: Dictionary, only := "") -> Array:
	var options := []  # [planet index, archetype id]
	var weights := {}
	for i in range(-1, system.planets.size()):
		var body_type := "station" if i < 0 else system.planets[i].type
		var habit := 0.2 if i < 0 else float(content.planet_types.get(body_type, {}).get("habitability", 0.0))
		for id in content.archetypes:
			if only != "" and id != only:
				continue
			var a: Dictionary = content.archetypes[id]
			var w := body_weight(a, body_type)
			if only == "":
				w *= float(a.get("region_weights", {}).get(region, 1.0)) * (habit + 0.3)
			if w > 0.0:
				weights[options.size()] = w
				options.append([i, id])
	return options[_weighted(weights, rng)]

static func _pick_government(region: String, archetype: String, rng: RandomNumberGenerator,
		governments: Dictionary) -> String:
	var weights := {}
	for id in governments:
		var g: Dictionary = governments[id]
		weights[id] = float(g.get("region_weights", {}).get(region, 1.0)) \
			* float(g.get("archetype_weights", {}).get(archetype, 1.0))
	return _weighted(weights, rng)

static func _weighted(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	var last: Variant = null
	for k in weights:
		if weights[k] <= 0.0:
			continue
		last = k
		r -= weights[k]
		if r < 0.0:
			return k
	return last

static func _only_class(system: StarSystem, classes: Array) -> bool:
	for star in system.stars:
		if not (star.get("class", "") in classes):
			return false
	return true

static func _planet_named(system: StarSystem, planet_name: String) -> int:
	for i in system.planets.size():
		if system.planets[i].name == planet_name:
			return i
	push_warning("[SettlementGen] %s: no planet '%s'" % [system.id, planet_name])
	return -1
