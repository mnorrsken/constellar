class_name World
extends RefCounted
## The whole game world. For now: the star map with its planets and
## settlements, generated from a seed. The day clock, markets and companies
## join in later milestones.
##
## Generation is deterministic: every system draws from its own RNG streams,
## seeded from (world seed, system id, stream name). So editing one system's
## data (e.g. known_planets.json) never changes any other system.

var world_seed: int
var galaxy: Galaxy
## Index of the fixed rim start world (balance.json "start_system"), or -1.
var start_system := -1

static func create(world_seed: int, stars_data: Dictionary, content: Dictionary) -> World:
	var w := World.new()
	w.world_seed = world_seed
	w.galaxy = Galaxy.from_dict(stars_data)
	var balance: Dictionary = content.balance
	var forced: Dictionary = balance.get("forced_settlements", {})
	w.start_system = w.galaxy.index_of(balance.get("start_system", ""))
	for s in w.galaxy.systems:
		PlanetGen.generate(s, stream(world_seed, s.id, "planets"),
			content.known_planets.get(s.id, {}))
		s.settlement = SettlementGen.generate(s, stream(world_seed, s.id, "settlement"),
			content, forced.get(s.id, {}), w.galaxy.lanes_of(s.index).size())
	_assign_names(w, content.names)
	return w

## A fresh RNG for one system and purpose.
static func stream(world_seed: int, system_id: String, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%s" % [world_seed, system_id, purpose])
	return rng

## Everything generated, as plain data (for tests and, later, saves).
func snapshot() -> Dictionary:
	var systems := {}
	for s in galaxy.systems:
		var planets := []
		for p in s.planets:
			planets.append(p.to_dict())
		systems[s.id] = {
			"hosts": s.hosts.duplicate(true),
			"planets": planets,
			"settlement": s.settlement.to_dict() if s.settlement else null,
		}
	return {"seed": world_seed, "start_system": start_system, "systems": systems}

func settlements() -> Array[Settlement]:
	var out: Array[Settlement] = []
	for s in galaxy.systems:
		if s.settlement:
			out.append(s.settlement)
	return out

## Unique names for all settlements without a forced one, in system order.
## Each root is used once, so "Dunmore" and "Dunmore Foundry" never coexist.
static func _assign_names(w: World, names: Dictionary) -> void:
	var used := {}
	var used_roots := {}
	for s in w.galaxy.systems:
		if s.settlement and s.settlement.name != "":
			used[s.settlement.name] = true
			used_roots[s.settlement.name] = true
	var roots: Array = names.get("roots", ["Colony"])
	var prefixes: Array = names.get("prefixes", [])
	var suffixes: Array = names.get("station_suffixes", ["Station"])
	var robot_suffixes: Array = names.get("robot_suffixes", ["Works"])
	var prefix_chance := float(names.get("prefix_chance", 0.25))
	for s in w.galaxy.systems:
		var st := s.settlement
		if st == null or st.name != "":
			continue
		var rng := stream(w.world_seed, s.id, "name")
		# A random unused root; the first unused one if luck runs out.
		var root: String = roots[rng.randi_range(0, roots.size() - 1)]
		for attempt in 60:
			if not used_roots.has(root):
				break
			root = roots[rng.randi_range(0, roots.size() - 1)]
		if used_roots.has(root):
			for r in roots:
				if not used_roots.has(r):
					root = r
					break
		var candidate := root
		if st.robots > 0:
			candidate = "%s %s" % [root, robot_suffixes[rng.randi_range(0, robot_suffixes.size() - 1)]]
		elif st.is_station:
			candidate = "%s %s" % [root, suffixes[rng.randi_range(0, suffixes.size() - 1)]]
		elif not prefixes.is_empty() and rng.randf() < prefix_chance:
			candidate = "%s %s" % [prefixes[rng.randi_range(0, prefixes.size() - 1)], root]
		var k := 2
		var base := candidate
		while used.has(candidate):
			candidate = "%s %d" % [base, k]
			k += 1
		st.name = candidate
		used[candidate] = true
		used_roots[root] = true
