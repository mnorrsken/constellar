extends RefCounted
## World generation: planets (PlanetGen), settlements (SettlementGen), World,
## on the real data files.

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")
var _world := World.create(1, _stars, _content)

func _create(seed_value: int, content := _content) -> World:
	return World.create(seed_value, _stars, content)

func test_same_seed_same_world(t: Object) -> void:
	t.eq(_create(1).snapshot(), _world.snapshot(), "seed 1 twice gives the same world")

func test_other_seed_differs(t: Object) -> void:
	t.ok(_create(2).snapshot() != _world.snapshot(), "seed 2 gives a different world")

func test_known_planets_change_only_their_system(t: Object) -> void:
	var edited := _content.duplicate(true)
	edited.known_planets["tau_ceti"] = {}
	var a: Dictionary = _world.snapshot().systems
	var b: Dictionary = _create(1, edited).snapshot().systems
	t.ok(a["tau_ceti"] != b["tau_ceti"], "Tau Ceti changed")
	var same := 0
	for id in a:
		if id != "tau_ceti" and a[id] == b[id]:
			same += 1
	t.eq(same, a.size() - 1, "every other system is untouched")

func test_known_planets_present(t: Object) -> void:
	var trappist := _world.galaxy.system_by_id("trappist_1")
	t.eq(trappist.planets.size(), 7, "TRAPPIST-1 has its seven planets")
	t.eq(trappist.planets[0].name, "TRAPPIST-1 b", "named after the star")
	t.ok(trappist.planets.all(func(p): return p.known), "all real")
	var acen := _world.galaxy.system_by_id("alpha_centauri")
	var proxima_b: Planet = acen.planets.filter(func(p): return p.name == "Proxima Centauri b")[0]
	t.ok(is_equal_approx(proxima_b.orbit_au, 0.0485), "Proxima b orbit")
	t.eq(proxima_b.type, "tidally_locked", "Proxima b is an eyeball world")
	t.eq(acen.hosts[proxima_b.host].name, "Proxima Centauri", "orbits Proxima")

func test_sol_is_real(t: Object) -> void:
	var sol := _world.galaxy.system_by_id("sol")
	var names := sol.planets.map(func(p): return p.name)
	t.eq(names, ["Mercury", "Venus", "Earth", "Mars", "Asteroid Belt", "Jupiter", "Saturn",
		"Uranus", "Neptune", "Kuiper Belt"], "the solar system, nothing invented")
	t.eq(sol.settlement.name, "Earth", "settlement on Earth")
	t.eq(sol.planets[sol.settlement.planet].name, "Earth", "lives on Earth")
	t.eq(sol.settlement.archetype, "core", "Earth is a core world")

func test_start_world_fixed_for_any_seed(t: Object) -> void:
	for seed_value in [1, 7, 99]:
		var w := _create(seed_value)
		var s := w.galaxy.systems[w.start_system]
		t.eq(s.id, "gamma_pavonis", "start system (seed %d)" % seed_value)
		t.eq(s.settlement.name, "Lodestar", "start settlement name (seed %d)" % seed_value)
		t.eq(s.settlement.archetype, "frontier", "start is a frontier colony (seed %d)" % seed_value)
		t.ok(s.position.length() > 25.0, "start is on the rim")

func test_settlement_bodies_fit_archetype(t: Object) -> void:
	var forced: Dictionary = _content.balance.forced_settlements
	for seed_value in [1, 2, 3, 4, 5]:
		for s in _create(seed_value).galaxy.systems:
			if s.settlement == null or forced.has(s.id):
				continue
			var st := s.settlement
			var body := "station" if st.planet < 0 else s.planets[st.planet].type
			t.ok(SettlementGen.body_weight(_content.archetypes[st.archetype], body) > 0.0,
				"%s: %s on %s" % [s.id, st.archetype, body])

func test_archetypes_follow_geography(t: Object) -> void:
	var on_gas_giants := 0
	var refineries_there := 0
	for seed_value in range(1, 21):
		for s in _create(seed_value).galaxy.systems:
			var st := s.settlement
			if st == null or st.planet < 0:
				continue
			var body := s.planets[st.planet].type
			if body == "gas_giant":
				on_gas_giants += 1
				if st.archetype == "refinery":
					refineries_there += 1
			if st.archetype == "refinery":
				t.ok(body in ["gas_giant", "ice_giant"], "refinery on a giant")
			if st.archetype == "agricultural":
				t.ok(body in ["garden", "ocean", "tidally_locked"], "farms on a living world")
			if st.archetype == "water":
				t.ok(body in ["ice", "ice_giant"], "ice harvester on ice")
	t.ok(on_gas_giants > 20, "enough gas giant settlements to judge (%d)" % on_gas_giants)
	t.ok(refineries_there > on_gas_giants * 0.6,
		"most gas giant settlements refine fuel (%d of %d)" % [refineries_there, on_gas_giants])

func test_rolled_planets_respect_companions(t: Object) -> void:
	for s in _world.galaxy.systems:
		for p in s.planets:
			if p.known:
				continue
			var host: Dictionary = s.hosts[p.host]
			t.ok(p.orbit_au <= host.outer_au and p.orbit_au >= host.inner_au,
				"%s at %.3f AU inside %s's stable zone" % [p.name, p.orbit_au, host.name])

func test_close_pairs_share_a_host(t: Object) -> void:
	var castor := _world.galaxy.system_by_id("castor")
	t.eq(castor.hosts.size(), 3, "Castor: three close pairs")
	t.ok(castor.hosts[0].inner_au > 0.0, "circumbinary planets keep clear of the pair")

func test_white_dwarf_keeps_a_belt(t: Object) -> void:
	var vm := _world.galaxy.system_by_id("van_maanens_star")
	t.ok(vm.planets.any(func(p): return p.type == "belt"), "Van Maanen's Star has debris")

func test_physics_helpers(t: Object) -> void:
	t.ok(is_equal_approx(PlanetGen.temperature(1.0, 1.0), 278.0), "Earth-like equilibrium temperature")
	t.ok(is_equal_approx(PlanetGen.habitable_zone_au(4.0), 2.0), "HZ scales with sqrt(L)")
	var rng := RandomNumberGenerator.new()
	t.eq(PlanetGen.classify(300.0, 100.0, false, "G", rng), "gas_giant", "Jupiter mass")
	t.eq(PlanetGen.classify(20.0, 100.0, false, "G", rng), "ice_giant", "Neptune mass")
	t.eq(PlanetGen.classify(1.0, 900.0, false, "G", rng), "molten", "too hot")
	t.eq(PlanetGen.classify(1.0, 260.0, true, "M", rng), "tidally_locked", "temperate + locked")

func test_names_unique_and_inhabited_share(t: Object) -> void:
	var prefixes: Array = _content.names.prefixes
	for seed_value in [1, 2, 3, 4, 5]:
		var w := _create(seed_value)
		var names := {}
		var roots := {}
		for st in w.settlements():
			names[st.name] = true
			var words := st.name.split(" ")
			roots[words[1] if words.size() > 1 and words[0] in prefixes else words[0]] = true
		t.eq(names.size(), w.settlements().size(), "settlement names unique (seed %d)" % seed_value)
		t.eq(roots.size(), w.settlements().size(), "no two names share a root (seed %d)" % seed_value)
		var share := float(w.settlements().size()) / w.galaxy.size()
		t.ok(share > 0.6 and share <= 0.95, "%.0f%% of systems settled" % (share * 100.0))

func test_robot_worlds(t: Object) -> void:
	for seed_value in [1, 2, 3]:
		var w := _create(seed_value)
		var robot_worlds := 0
		var leaves := 0
		var empty_leaves := 0
		for s in w.galaxy.systems:
			if w.galaxy.lanes_of(s.index).size() <= 2:
				leaves += 1
				if s.settlement == null:
					empty_leaves += 1
			var st := s.settlement
			if st == null or st.archetype != "robot":
				continue
			robot_worlds += 1
			t.ok(st.robots >= 100000 and st.population <= 1000, "%s: robots, few humans" % st.name)
			t.eq(st.government, "custodians", "%s run by robot custodians" % st.name)
			t.ok(SettlementGen.region_of(s.position.length(), _content.balance) != "core",
				"%s: no robot worlds in the core" % st.name)
		t.ok(robot_worlds >= 5, "seed %d has robot worlds (%d)" % [seed_value, robot_worlds])
		t.ok(empty_leaves < leaves * 0.3, "most dead-end systems are settled (%d of %d empty)" % [empty_leaves, leaves])

func test_regions(t: Object) -> void:
	var b: Dictionary = _content.balance
	t.eq(SettlementGen.region_of(4.3, b), "core", "Alpha Centauri is core")
	t.eq(SettlementGen.region_of(20.0, b), "inner", "20 ly is inner")
	t.eq(SettlementGen.region_of(40.0, b), "rim", "40 ly is rim")

func test_format(t: Object) -> void:
	t.eq(Format.population(7_200_000_000), "7.2 billion", "billions")
	t.eq(Format.population(180_000_000), "180 million", "millions")
	t.eq(Format.population(60_000), "60,000", "thousands")
	t.eq(Format.au(0.0485), "0.049 AU", "close orbit")
	t.eq(Format.spectral({"class": "M", "subclass": 5.5, "lum_class": "V"}), "M5.5 V", "spectral")

func test_orrery_layout_every_system(t: Object) -> void:
	var rect := Rect2(0, 120, 1400, 760)
	var bad := 0
	for s in _world.galaxy.systems:
		var layout := OrreryLayout.build(s, rect)
		t.eq(layout.rows.size(), s.hosts.size(), "%s: one row per host" % s.id)
		for row in layout.rows:
			if row.y < rect.position.y or row.y > rect.end.y:
				bad += 1
			var prev_right := -INF
			for b in row.bodies:
				if b.x - b.r < prev_right - 0.01 or b.x + b.r > rect.end.x or b.x - b.r < rect.position.x:
					bad += 1
				prev_right = b.x + b.r
	t.eq(bad, 0, "no body overlaps or leaves the view")
