extends RefCounted
## Ship aging: wear, age-based maintenance, breakdowns, servicing (by hand
## and as a route stop), the notes that say why a ship is idle or losing,
## the per-ship books by category, and new hull models by year.

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

func _world() -> World:
	var w := World.create(1, _stars, _content)
	w.warm_up()
	w.companies[0].cash = 2000000.0
	return w

## A copy of the content with some aging numbers changed (and no events,
## so nothing else interferes).
func _with_aging(w: World, changes: Dictionary) -> void:
	w.content = _content.duplicate()
	w.content.balance = _content.balance.duplicate(true)
	w.content.balance.aging.merge(changes, true)
	w.content.events = {}

func _next_market(w: World) -> int:
	for lane in w.galaxy.lanes_of(w.start_system):
		if w.economy.market_at(lane.other(w.start_system)):
			return lane.other(w.start_system)
	return -1

## A charted shipyard, with the ship docked there.
func _at_yard(w: World, s: Ship) -> int:
	w.reveal_all(0)
	for m in w.economy.markets:
		if w.fleet.is_shipyard(m.system):
			s.system = m.system
			return m.system
	return -1

func test_start_ship_is_second_hand(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	t.ok(Aging.age_years(w, s) > 4.0, "the start ship has some years on it")
	t.ok(s.condition < 1.0, "and some wear")
	var fresh := w.fleet.add_ship(0, "packet", w.start_system, w.day)
	t.ok(Aging.maintenance(w, s) > Aging.maintenance(w, fresh), "older ships cost more to maintain")
	t.ok(Aging.reliability(w, s) < Aging.reliability(w, fresh), "and are less reliable")

func test_travel_wears_ships(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var idle := w.fleet.add_ship(0, "packet", w.start_system, w.day)
	var c0 := s.condition
	var i0 := idle.condition
	w.send_ship(0, s.id, _next_market(w))
	for i in 20:
		w.advance_day()
	t.ok(c0 - s.condition > i0 - idle.condition, "a ship under way wears faster than one in port")

func test_breakdown_delays_and_costs(t: Object) -> void:
	var w := _world()
	_with_aging(w, {"breakdown_per_day": 50.0, "breakdown_days": [5, 5]})  # certain
	var s := w.ships_of(0)[0]
	w.send_ship(0, s.id, _next_market(w))
	var due := s.arrival_day
	w.drain_events()
	w.advance_day()
	var broke: Array = w.drain_events().filter(func(e): return e.type == "breakdown")
	t.eq(broke.size(), 1, "it broke down")
	t.eq(s.arrival_day, due + 5, "arrival moves back by the days lost")
	t.ok(s.broken_until > w.day and "broken down" in s.note, "the note says so: %s" % s.note)
	var progress := s.leg_progress
	w.advance_day()
	t.eq(s.leg_progress, progress, "a broken-down ship does not move")
	t.ok(w.companies[0].ledger[w.month()].get("repairs", 0.0) < 0.0, "repairs paid")

func test_service_restores_up_to_an_age_cap(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	s.system = w.start_system
	t.ok(not w.service_ship(0, s.id).ok or w.fleet.is_shipyard(w.start_system), "servicing needs a shipyard")
	_at_yard(w, s)
	s.condition = 0.3
	var cash := w.companies[0].cash
	var r := w.service_ship(0, s.id)
	t.ok(r.ok, "serviced")
	t.ok(w.companies[0].cash < cash, "for a price")
	t.eq(s.status, Ship.Status.REFITTING, "in the yard for a few days")
	t.ok(is_equal_approx(s.condition, Aging.service_cap(w, s)), "back to what its age allows")
	t.ok(Aging.service_cap(w, s) < 1.0, "which is below new for an old ship")
	s.built_day = w.day - 40 * Calendar.DAYS_PER_YEAR
	t.ok(Aging.service_cap(w, s) < 0.6, "and much lower for a very old one")
	s.status = Ship.Status.DOCKED
	s.built_day = w.day
	s.condition = 1.0
	t.ok(not w.service_ship(0, s.id).ok, "nothing to do for a ship in top shape")

func test_route_stop_services_when_needed(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var yard := _at_yard(w, s)
	var other: int = w.galaxy.lanes_of(yard)[0].other(yard)
	s.condition = 0.3
	w.set_orders(0, s.id, [{"system": yard, "service": true}, {"system": other}])
	w.start_orders(0, s.id)
	t.eq(s.status, Ship.Status.REFITTING, "the route stop sends it into the yard")
	for i in 10:
		w.advance_day()
	t.ok(s.status == Ship.Status.TRAVELING or s.system == other, "then the route goes on")

func test_notes_explain_idle_ships(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var next := _next_market(w)
	var ore := w.economy.index_of("ore")
	s.modules.assign(["bulk", "bulk", "bulk"])
	w.economy.market_at(w.start_system).stock[ore] = 50.0
	w.set_orders(0, s.id, [
		{"system": w.start_system, "buy": [{"commodity": "ore", "amount": 0}], "wait_full": true},
		{"system": next, "sell_all": true},
	])
	w.start_orders(0, s.id)
	w.advance_day()
	t.ok("full load" in s.note, "waiting for a full load: %s" % s.note)
	w.stop_orders(0, s.id)
	s.modules.assign(["container", "container", "auto_trader"])
	w.companies[0].prices.erase(next)
	w.set_orders(0, s.id, [{"system": w.start_system, "auto": true}, {"system": next, "auto": true}])
	w.start_orders(0, s.id)
	t.ok("no cargo match" in s.note, "auto-trader with nothing to buy: %s" % s.note)

func test_ship_books_by_category_and_loss_reason(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var c := w.companies[0]
	w.buy_cargo(0, s.id, "machinery", 100.0)
	var m := w.month()
	var paid: float = c.ship_ledger[s.id][m].purchases
	t.ok(paid < 0.0, "purchases booked on the ship")
	t.ok(is_equal_approx(c.cash_net(m, s.id), paid), "cash out for the goods")
	t.ok(is_equal_approx(c.profit(m, s.id), 0.0), "but no profit or loss until they are sold")
	t.eq(Trading.loss_reason(c, s.id, m), "", "so nothing to explain")
	var ci := w.economy.index_of("machinery")
	s.cargo_cost[ci] *= 3.0  # as if bought far too dear
	w.sell_cargo(0, s.id, "machinery", 100.0)
	t.ok(c.profit(m, s.id) < 0.0, "sold below cost: a loss")
	t.ok(Trading.loss_reason(c, s.id, m).begins_with("price too low"), "explained: %s" % Trading.loss_reason(c, s.id, m))

func test_new_hull_models_by_year(t: Object) -> void:
	var w := _world()
	var yard := -1
	for m in w.economy.markets:
		if w.fleet.is_shipyard(m.system) and w.galaxy.systems[m.system].settlement.tech_level >= 8:
			yard = m.system
			break
	t.ok(yard >= 0, "a high-tech shipyard")
	var now := w.fleet.hulls_for_sale(yard, 3400)
	var later := w.fleet.hulls_for_sale(yard, 3427)
	t.ok(not ("leviathan_ii" in now) and "leviathan_ii" in later, "new models come out over the years")
	t.ok("packet" in now and not ("packet" in later), "and old ones go out of production")
