extends RefCounted
## Companies, ships, shipyards, refits and travel (Fleet via World commands).

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

func _world() -> World:
	return World.create(1, _stars, _content)

func _shipyard(w: World, min_tech := 0, max_tech := 10) -> int:
	for s in w.galaxy.systems:
		if w.fleet.is_shipyard(s.index) and s.settlement.tech_level >= min_tech \
				and s.settlement.tech_level <= max_tech:
			return s.index
	return -1

## A hand-made triangle A-B-C (A-C direct 8 ly) with D 12 ly beyond C.
func _small_fleet() -> Array:
	var g := Galaxy.new()
	g.add_system("a", "A", Vector3(0, 0, 0))
	g.add_system("b", "B", Vector3(4, 3, 0))
	g.add_system("c", "C", Vector3(8, 0, 0))
	g.add_system("d", "D", Vector3(20, 0, 0))
	g.add_lane(0, 1)
	g.add_lane(1, 2)
	g.add_lane(0, 2)
	g.add_lane(2, 3)
	var hull := {"slots": 1, "slot_tonnes": 10, "speed": 1.0, "price": 0, "allowed": ["*"], "default_modules": []}
	var short := hull.duplicate()
	short.jump_range = 6.0
	var long := hull.duplicate()
	long.jump_range = 12.0
	var f := Fleet.new(g, {"hulls": {"short": short, "long": long}, "modules": {}})
	return [f, f.add_ship(0, "short", 0, 0), f.add_ship(0, "long", 0, 0)]

func test_start_company_and_ship(t: Object) -> void:
	var w := _world()
	var c := w.companies[0]
	t.eq(c.cash, 250000.0, "starting cash")
	t.eq(c.loan, 500000.0, "starting loan")
	var ships := w.ships_of(0)
	t.eq(ships.size(), 1, "one starting ship")
	t.eq(ships[0].name, "Wanderer", "named Wanderer")
	t.eq(ships[0].system, w.start_system, "docked at the start world")
	t.eq(w.fleet.capacity(ships[0]), {"container": 750.0}, "three container holds, 750 t")

func test_buy_at_shipyard(t: Object) -> void:
	var w := _world()
	var yard := _shipyard(w, 6)
	t.ok(yard >= 0, "some shipyard sells medium freighters")
	w.companies[0].cash = 1000000.0
	var before := w.companies[0].cash
	var r := w.buy_ship(0, "packet", yard)
	t.ok(r.ok, "bought a Packet")
	t.ok(is_equal_approx(w.companies[0].cash, before - 450000.0 - 3 * 40000.0), "paid hull + three holds")
	t.eq(r.ship.system, yard, "docked at the shipyard")
	t.eq(w.ships_of(0).size(), 2, "fleet of two")

func test_buy_refusals(t: Object) -> void:
	var w := _world()
	t.ok(not w.buy_ship(0, "packet", w.start_system).ok, "no shipyard on the rim colony")
	var yard := _shipyard(w)
	w.companies[0].cash = 1000.0
	t.ok(not w.buy_ship(0, "packet", yard).ok, "not enough cash")
	w.companies[0].cash = 1e9
	var low_tech := _shipyard(w, 0, 7)
	if low_tech >= 0:
		t.ok(not w.buy_ship(0, "leviathan", low_tech).ok, "a tech-7 yard cannot build a Leviathan")
	t.ok(not w.buy_ship(0, "hauler_ii", yard).ok, "Hauler II is not built before 3412")

func test_refit(t: Object) -> void:
	var w := _world()
	w.companies[0].cash = 5000000.0
	var yard := _shipyard(w, 6)
	var s: Ship = w.buy_ship(0, "packet", yard).ship
	var cash := w.companies[0].cash
	var r := w.refit_ship(0, s.id, ["container", "cold", "drive_tune"])
	t.ok(r.ok, "refit accepted")
	t.ok(is_equal_approx(w.companies[0].cash, cash - (70000 + 150000 - 0.5 * 2 * 40000)), "new modules paid, old sold at half")
	t.eq(s.status, Ship.Status.REFITTING, "in the yard")
	t.eq(r.days, 3 + 2 * 2, "3 days + 2 per changed slot")
	t.ok(not w.send_ship(0, s.id, w.start_system).ok, "cannot leave while refitting")
	for i in r.days:
		w.advance_day()
	t.eq(s.status, Ship.Status.DOCKED, "back in service")
	t.ok(w.drain_events().any(func(e): return e.type == "refitted"), "refitted event")
	t.ok(is_equal_approx(w.fleet.speed(s), 0.3 * 1.15), "drive tune adds 15% speed")

func test_refit_refusals(t: Object) -> void:
	var w := _world()
	w.companies[0].cash = 5000000.0
	var yard := _shipyard(w, 6)
	var courier: Ship = w.buy_ship(0, "courier", yard).ship
	t.ok(not w.refit_ship(0, courier.id, ["tank", "mail"]).ok, "couriers take no tanks")
	t.ok(not w.refit_ship(0, courier.id, ["mail"]).ok, "wrong slot count")
	t.ok(not w.refit_ship(0, courier.id, ["container", "mail"]).ok, "nothing to change")
	var start := w.ships_of(0)[0]
	var tech := w.galaxy.systems[w.start_system].settlement.tech_level
	t.ok(not w.fleet.is_shipyard(w.start_system), "the start world builds no ships")
	t.ok(w.refit_ship(0, start.id, ["bulk", "bulk", "container"]).ok, "but any port refits (simple modules)")
	start.status = Ship.Status.DOCKED
	t.ok(tech < 8, "a small colony (tech %d)" % tech)
	var r := w.refit_ship(0, start.id, ["bulk", "bulk", "jump_extender"])
	t.ok(not r.ok and "tech" in r.error, "doesn't make advanced modules: %s" % r.get("error", ""))
	t.ok(not w.buy_ship(0, "packet", w.start_system).ok, "and sells no new ships")

func test_travel_arrives_on_predicted_day(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	var s := w.ships_of(0)[0]
	# Somewhere at least three lanes away.
	var target := -1
	for sys in w.galaxy.systems:
		var plan := w.fleet.plan_route(s, sys.index)
		if plan.ok and plan.path.size() >= 4:
			target = sys.index
			break
	t.ok(target >= 0, "found a destination three lanes out")
	var r := w.send_ship(0, s.id, target)
	t.ok(r.ok, "under way")
	var arrival: int = r.arrival_day
	t.ok(arrival > w.day, "arrives in the future")
	while w.day < arrival - 1:
		w.advance_day()
	t.eq(s.status, Ship.Status.TRAVELING, "still travelling the day before")
	w.drain_events()
	w.advance_day()
	t.eq(w.day, arrival, "the predicted day")
	t.eq(s.status, Ship.Status.DOCKED, "docked on arrival")
	t.eq(s.system, target, "at the destination")
	t.ok(w.drain_events().any(func(e): return e.type == "arrived" and e.ship == s.id), "arrived event")

func test_short_range_routes_around_or_refuses(t: Object) -> void:
	var parts := _small_fleet()
	var f: Fleet = parts[0]
	var short: Ship = parts[1]
	var long: Ship = parts[2]
	var plan := f.plan_route(short, 2)
	t.eq(plan.path, PackedInt32Array([0, 1, 2]), "6 ly range goes around the 8 ly lane")
	t.eq(f.plan_route(long, 2).path, PackedInt32Array([0, 2]), "12 ly range takes it")
	var far := f.plan_route(short, 3)
	t.ok(not far.ok and "Out of range" in far.error, "the 12 ly jump to D is out of range: %s" % far.get("error"))
	t.ok(f.plan_route(long, 3).ok, "long range reaches D")

func test_travel_days_and_positions(t: Object) -> void:
	var parts := _small_fleet()
	var f: Fleet = parts[0]
	var s: Ship = parts[2]
	t.eq(Fleet.travel_days(8.0, 1.0), 8, "8 ly at 1 ly/day")
	t.eq(Fleet.travel_days(8.1, 1.0), 9, "any part of a day counts")
	f.send(s, 2, 0)
	f.advance_day(1)
	f.advance_day(2)
	var at: Array = f.route_point(s, 0.0)
	t.ok(at[0].is_equal_approx(Vector3(2, 0, 0)), "2 ly along the A-C lane")
	var ahead: Array = f.route_point(s, 0.5)
	t.ok(ahead[0].is_equal_approx(Vector3(2.5, 0, 0)), "half a day further for smooth drawing")
	t.ok(at[1].is_equal_approx(Vector3.RIGHT), "heading toward C")

func test_jump_extender(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	s.modules.assign(["container", "container", "jump_extender"])
	t.eq(w.fleet.jump_range(s), 14.0, "12 + 2 ly")

func test_only_own_ships(t: Object) -> void:
	var w := _world()
	var other := w.fleet.add_ship(1, "packet", w.start_system, 0)
	t.ok(not w.send_ship(0, other.id, 0).ok, "cannot send another house's ship")
	t.ok(not w.sell_ship(0, other.id).ok, "cannot sell it either")

func test_sell_and_unique_ids(t: Object) -> void:
	var w := _world()
	w.companies[0].cash = 5000000.0
	var yard := _shipyard(w, 6)
	var a: Ship = w.buy_ship(0, "packet", yard).ship
	var cash := w.companies[0].cash
	t.ok(w.sell_ship(0, a.id).ok, "sold at the yard")
	t.ok(w.companies[0].cash > cash, "got money back")
	var b: Ship = w.buy_ship(0, "packet", yard).ship
	t.ok(b.id != a.id, "a new ship never reuses an old id")

func test_loans(t: Object) -> void:
	var w := _world()
	t.ok(not w.take_loan(0, 2000000.0).ok, "the bank has a limit")
	t.ok(w.take_loan(0, 500000.0).ok, "borrow more")
	t.eq(w.companies[0].loan, 1000000.0, "loan grew")
	t.ok(w.repay_loan(0, 200000.0).ok, "repay part")
	t.eq(w.companies[0].loan, 800000.0, "loan shrank")

func test_fog_of_war_start(t: Object) -> void:
	var w := _world()
	var c := w.companies[0]
	t.ok(c.is_known(w.start_system), "the start world is charted")
	for lane in w.galaxy.lanes_of(w.start_system):
		t.ok(c.is_known(lane.other(w.start_system)), "one jump out is charted")
	t.ok(not c.is_known(w.galaxy.index_of("sol")), "Sol is far off and uncharted")
	var r := w.send_ship(0, w.ships_of(0)[0].id, w.galaxy.index_of("sol"))
	t.ok(not r.ok and "Uncharted" in r.error, "cannot plot a course to an uncharted system")

func test_travel_charts_the_way(t: Object) -> void:
	var w := _world()
	var c := w.companies[0]
	var s := w.ships_of(0)[0]
	var next: int = w.galaxy.lanes_of(w.start_system)[0].other(w.start_system)
	var beyond := -1
	for lane in w.galaxy.lanes_of(next):
		if not c.is_known(lane.other(next)):
			beyond = lane.other(next)
	t.ok(beyond >= 0, "something uncharted lies beyond the neighbour")
	var r := w.send_ship(0, s.id, next)
	t.ok(r.ok, "neighbour is charted, so reachable")
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	t.ok(c.is_known(beyond), "arriving charted one jump further")
	t.ok(w.drain_events().any(func(e): return e.type == "charted"), "charted event")

func test_routes_use_charted_systems_only(t: Object) -> void:
	var parts := _small_fleet()
	var f: Fleet = parts[0]
	var long: Ship = parts[2]
	var known := PackedByteArray([1, 1, 1, 0])
	t.eq(f.plan_route(long, 2, known).path, PackedInt32Array([0, 2]), "charted route works")
	known = PackedByteArray([1, 1, 0, 1])
	t.ok(not f.plan_route(long, 3, known).ok, "no route through an uncharted system")
