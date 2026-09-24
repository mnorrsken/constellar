extends RefCounted
## Events, governments and danger: the event data, the monthly roll, event
## effects on markets, tariffs and bans (and route orders respecting them),
## closed ports, embargoes, lane danger with "safest" routing, raids,
## losses, armour and insurance.

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

func _world() -> World:
	var w := World.create(1, _stars, _content)
	w.warm_up()
	w.companies[0].cash = 2000000.0
	return w

## A market next to the start world.
func _next_market(w: World) -> int:
	for lane in w.galaxy.lanes_of(w.start_system):
		if w.economy.market_at(lane.other(w.start_system)):
			return lane.other(w.start_system)
	return -1

## Runs the calendar a month at a time (events only, no ships or markets).
func _months(w: World, n: int) -> void:
	for i in n:
		w.day += 30
		WorldEvents.daily(w)
		WorldEvents.monthly(w)

func test_event_data(t: Object) -> void:
	var kinds: Dictionary = _content.events
	for id in ["war", "zealots", "plague", "crop_failure", "mining_strike", "labour_strike",
			"pirates", "flare", "embargo", "agreement", "festival"]:
		t.ok(kinds.has(id), "starter event %s" % id)
	for id in kinds:
		var d: Dictionary = kinds[id]
		t.ok(d.get("scope", "") in ["system", "pair", "lane"], "%s has a scope" % id)
		t.ok(float(d.get("chance_per_month", 0.0)) > 0.0, "%s can happen" % id)
		t.ok(d.get("days", []).size() == 2 and d.has("headline") and d.has("end_headline"), "%s has days and headlines" % id)
		t.ok(not d.get("effects", {}).is_empty(), "%s does something" % id)
	t.ok(_content.governments.has("zealots"), "the zealot government exists")

func test_monthly_roll_is_deterministic_and_fires(t: Object) -> void:
	var a := _world()
	var b := _world()
	_months(a, 60)
	_months(b, 60)
	t.eq(a.news.map(func(n): return n.text), b.news.map(func(n): return n.text), "same seed, same news")
	var kinds := {}
	for n in a.news:
		kinds[n.kind] = true
	t.ok(kinds.size() >= 6, "five years bring many kinds of events (%s)" % [kinds.keys()])

func test_war_makes_lanes_dangerous_and_safest_routing_avoids_them(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	var s := w.ships_of(0)[0]
	# A lane between two peopled worlds that can also be reached another way.
	var lane: Lane = null
	for l in w.galaxy.lanes:
		var ok := l.length <= w.fleet.jump_range(s) and WorldEvents._fits(w, _content.events.war, l.a) \
			and WorldEvents._fits(w, _content.events.war, l.b)
		if ok and not w.galaxy.find_path(l.a, l.b, w.fleet.jump_range(s), PackedByteArray(),
				{Danger.key(l.a, l.b): 1e6}).is_empty():
			lane = l
			break
	t.ok(lane != null, "found a lane with a way around")
	var before := Danger.lane_danger(w, lane.a, lane.b)
	WorldEvents.start(w, "war", [lane.a, lane.b])
	t.ok(Danger.lane_danger(w, lane.a, lane.b) >= before + 0.12, "the lane between them is dangerous")
	s.system = lane.a
	var fast := w.plan_route(0, s.id, lane.b)
	t.eq(Array(fast.path), [lane.a, lane.b], "the fastest route takes the war lane")
	w.set_routing(0, s.id, true)
	var safe := w.plan_route(0, s.id, lane.b)
	t.ok(safe.ok and safe.path.size() > 2, "the safest route goes around")
	t.ok(safe.risk < fast.risk, "and runs less risk (%.3f < %.3f)" % [safe.risk, fast.risk])
	var weapons := w.economy.index_of("weapons")
	var m := w.economy.market_at(lane.a)
	var p0: float = m.price[weapons]
	for i in 28:
		w.advance_day()
	t.ok(m.price[weapons] > p0 * 1.05, "weapons get dear (%d -> %d)" % [p0, m.price[weapons]])
	t.ok(w.news.any(func(n): return n.kind == "war"), "the war is in the news")

func test_zealots_bring_tariffs_and_bans_and_routes_respect_them(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var home := w.start_system
	var next := _next_market(w)
	s.modules.assign(["container", "secure", "secure"])
	t.ok(w.buy_cargo(0, s.id, "atomics", 40.0).ok, "atomics are legal before the takeover")
	t.ok(w.buy_cargo(0, s.id, "luxuries", 40.0).ok, "and luxuries")
	WorldEvents.start(w, "zealots", [home])
	var st := w.galaxy.systems[home].settlement
	t.eq(st.government, "zealots", "the zealots rule")
	var lux := w.economy.index_of("luxuries")
	var atomics := w.economy.index_of("atomics")
	t.ok(is_equal_approx(Trading.tariff(w, home, lux), 0.3), "30% tariff on luxuries")
	t.ok(Trading.is_banned(w, home, atomics), "atomics banned")
	t.ok(not w.buy_cargo(0, s.id, "atomics", 10.0).ok, "no atomics for sale")
	t.ok(not w.sell_cargo(0, s.id, "atomics", 10.0).ok, "and none may be sold")
	var r := w.sell_cargo(0, s.id, "luxuries", 20.0)
	var duty: float = w.companies[0].ledger[w.month()].get("tariffs", 0.0)
	t.ok(r.ok and duty < 0.0, "selling luxuries pays duty (%d)" % duty)
	t.ok(is_equal_approx(-duty, (r.income - duty) * 0.3), "30% of the sale")
	t.ok(w.buy_cargo(0, s.id, "machinery", 100.0).ok, "machinery is fine")
	var carried: float = s.cargo[atomics]
	w.set_orders(0, s.id, [
		{"system": home, "sell_all": true, "buy": [{"commodity": "atomics", "amount": 0}]},
		{"system": next, "sell_all": true},
	])
	w.start_orders(0, s.id)
	t.eq(s.cargo.get(atomics, 0.0), carried, "the route neither sells nor buys banned atomics")
	t.ok(not s.cargo.has(w.economy.index_of("machinery")), "it sold the rest")
	t.eq(s.status, Ship.Status.TRAVELING, "and went on")

func test_closed_port(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var ev := WorldEvents.start(w, "labour_strike", [w.start_system])
	var r := w.buy_cargo(0, s.id, "machinery", 10.0)
	t.ok(not r.ok and "closed" in r.error, "no trade while the port is closed")
	w.set_orders(0, s.id, [
		{"system": w.start_system, "sell_all": true, "buy": [{"commodity": "machinery", "amount": 100}]},
		{"system": _next_market(w), "sell_all": true},
	])
	w.start_orders(0, s.id)
	t.eq(s.status, Ship.Status.DOCKED, "a route waits at a closed port")
	while w.day < ev.end_day:
		w.advance_day()
	w.advance_day()
	t.ok(not w.economy.market_at(w.start_system).closed, "the strike ends")
	t.ok(s.status == Ship.Status.TRAVELING and s.cargo.has(w.economy.index_of("machinery")), "then it loads and sails")

func test_embargo_stops_traffic(t: Object) -> void:
	var w := _world()
	var m := w.economy.market_at(w.start_system)
	WorldEvents.start(w, "embargo", [w.start_system])
	t.ok(m.isolated, "embargoed")
	var before := m.stock.duplicate()
	w.economy.run_traffic()
	t.eq(m.stock, before, "no background traders call")

func test_event_ends_and_its_effects_go(t: Object) -> void:
	var w := _world()
	var m := w.economy.market_at(w.start_system)
	var lux := w.economy.index_of("luxuries")
	var ev := WorldEvents.start(w, "festival", [w.start_system])
	t.ok(m.demand_mult[lux] > 1.0, "festival wants luxuries")
	t.eq(WorldEvents.active_at(w, w.start_system).size(), 1, "one event there")
	w.day = ev.end_day
	WorldEvents.daily(w)
	t.eq(m.demand_mult[lux], 1.0, "back to normal")
	t.ok(w.world_events.is_empty(), "nothing running")
	t.ok(w.news.size() == 2 and not w.news[1].start, "start and end in the news")

func test_raids_losses_and_insurance(t: Object) -> void:
	var w := _world()
	w.content = _content.duplicate()
	w.content.events = {}  # no new events to rebuild the lane dangers
	var s := w.ships_of(0)[0]
	var next := _next_market(w)
	w.set_insurance(0, s.id, true)
	w.buy_cargo(0, s.id, "machinery", 200.0)
	var paid: float = s.cargo_cost.values()[0]
	var path: PackedInt32Array = w.plan_route(0, s.id, next).path
	for i in range(1, path.size()):
		w.danger[Danger.key(path[i - 1], path[i])] = 1.0  # a certain hit
	t.ok(w.send_ship(0, s.id, next).ok, "sent")
	var hit := {}
	for i in 60:
		w.advance_day()
		for e in w.drain_events():
			if e.type in ["raided", "lost"]:
				hit = e
		if not hit.is_empty():
			break
	t.ok(not hit.is_empty(), "the ship was hit")
	if hit.is_empty():
		return
	var books: Dictionary = w.companies[0].ledger[w.month()]
	t.ok(books.get("insurance", 0.0) >= paid, "insurance paid for the cargo (%d)" % books.get("insurance", 0.0))
	if hit.type == "lost":
		t.ok(w.fleet.get_ship(s.id) == null, "a lost ship is gone")
		t.ok(books.insurance >= paid + Danger.ship_value(w, s) - 1.0, "and its value paid out")
	else:
		t.ok(s.cargo.is_empty(), "raiders took the cargo")
		t.ok(books.get("repairs", 0.0) < 0.0, "and there is a repair bill")

func test_armour_and_premium(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var next := _next_market(w)
	w.danger[Danger.key(w.start_system, next)] = 0.1
	var bare := Danger.ship_danger(w, s, w.start_system, next)
	s.modules.assign(["container", "container", "armour"])
	t.ok(is_equal_approx(Danger.ship_danger(w, s, w.start_system, next), bare * 0.5), "armour halves the risk")
	var calm := Danger.premium(w, s)
	s.risk_last_month = 0.2
	t.ok(Danger.premium(w, s) > calm * 5.0, "a risky month makes insurance dear")
	s.insured = true
	var cash := w.companies[0].cash
	Danger.monthly(w)
	t.ok(w.companies[0].cash < cash, "the premium is paid monthly")
