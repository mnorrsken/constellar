extends RefCounted
## Trading: price knowledge, buying and selling, fees, the ledger, route
## orders (Trading via World commands).

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

## A world with settled markets (prices differ, as in the game).
func _world() -> World:
	var w := World.create(1, _stars, _content)
	w.warm_up()
	w.companies[0].cash = 2000000.0
	return w

## Charts everything and lets company 0 see every market's current prices.
func _all_known(w: World) -> void:
	w.reveal_all(0)
	for m in w.economy.markets:
		Trading.observe(w, 0, m.system)

## The most profitable container good between two neighbouring markets for
## a ship: [from, to, commodity index, margin per tonne].
func _best_pair(w: World, s: Ship) -> Array:
	var best := [-1, -1, -1, 0.0]
	for a in w.economy.markets:
		for lane in w.galaxy.lanes_of(a.system):
			var b := w.economy.market_at(lane.other(a.system))
			if b == null or lane.length > w.fleet.jump_range(s):
				continue
			for c in a.price.size():
				if Trading.commodity_class(w, c) != "container" or a.stock[c] < 800.0:
					continue
				var margin: float = b.price[c] - a.price[c]
				if margin > best[3]:
					best = [a.system, b.system, c, margin]
	return best

func test_prices_only_from_own_ships(t: Object) -> void:
	var w := _world()
	var sol := w.galaxy.index_of("sol")
	t.ok(not w.known_prices(0, w.start_system).is_empty(), "the start market is known")
	t.ok(w.known_prices(0, sol).is_empty(), "no ship has been to Earth: no prices")
	w.reveal_all(0)
	t.ok(w.known_prices(0, sol).is_empty(), "charting a system does not reveal its prices")
	var s := w.ships_of(0)[0]
	var next: int = w.galaxy.lanes_of(w.start_system)[0].other(w.start_system)
	w.send_ship(0, s.id, next)
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	if w.economy.market_at(next):
		var k := w.known_prices(0, next)
		t.eq(k.get("day", -1), w.day, "prices known from the arrival day")
		for i in 30:
			w.advance_day()
		t.ok(w.known_prices(0, next).day >= w.day - 7, "a docked ship keeps them fresh (weekly)")

func test_buy_checks_class_space_and_cash(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var electronics := w.economy.index_of("electronics")
	var cash := w.companies[0].cash
	var r := w.buy_cargo(0, s.id, "electronics", 100.0)
	t.ok(r.ok and r.qty == 100.0, "bought 100 t")
	t.ok(is_equal_approx(w.companies[0].cash, cash - r.cost), "paid for it")
	t.eq(s.cargo[electronics], 100.0, "in the hold")
	t.ok(not w.buy_cargo(0, s.id, "fuel", 10.0).ok, "no tank for liquid cargo")
	var big := w.buy_cargo(0, s.id, "consumer_goods", 5000.0)
	t.ok(big.ok and big.qty <= 650.0, "limited to the free container space (%d t)" % big.qty)
	w.companies[0].cash = 1000.0
	t.ok(not w.buy_cargo(0, s.id, "robots", 1.0).ok or s.cargo_tonnes() <= 750.0, "cash and space limits hold")

func test_sale_pays_the_market_price(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	w.buy_cargo(0, s.id, "machinery", 200.0)
	var cash := w.companies[0].cash
	var r := w.sell_cargo(0, s.id, "machinery", 200.0)
	t.ok(r.ok, "sold")
	t.ok(is_equal_approx(w.companies[0].cash, cash + r.income), "cash in = the sale (no tax)")
	t.ok(absf(r.profit) < r.income * 0.01, "selling back at once returns what was paid (no tax, no spread)")
	t.ok(s.cargo.is_empty(), "hold empty")

func test_fuel_and_docking_fees(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var next := -1
	for lane in w.galaxy.lanes_of(w.start_system):
		if w.economy.market_at(lane.other(w.start_system)):
			next = lane.other(w.start_system)
	var cash := w.companies[0].cash
	var r := w.send_ship(0, s.id, next)
	t.ok(r.ok, "under way")
	t.ok(r.fuel.tonnes > 0.0 and is_equal_approx(w.companies[0].cash, cash - r.fuel.cost), "fuel bought at departure")
	t.ok(is_equal_approx(r.fuel.tonnes, w.galaxy.path_length(r.path) * 4.0), "4 t per ly for a Packet")
	var before := w.companies[0].cash
	var month := w.month()
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	var docking: float = w.companies[0].ledger.get(w.month(), {}).get("docking", 0.0)
	t.ok(is_equal_approx(docking, -Trading.docking_fee(w, s)), "docking fee booked on arrival")
	t.ok(w.companies[0].cash < before, "fees came out of cash")
	t.ok(month >= 0, "ledger month")

func test_monthly_costs(t: Object) -> void:
	var w := _world()
	while w.day < 31:
		w.advance_day()
	var feb: Dictionary = w.companies[0].ledger.get(w.month(), {})
	t.eq(feb.get("crew", 0.0), -4000.0, "Packet crew")
	t.eq(feb.get("maintenance", 0.0), -3000.0, "Packet maintenance")
	t.ok(is_equal_approx(feb.get("interest", 0.0), -500000.0 * 0.06 / 12.0), "a month of 6% interest")

func test_manual_trade_loop_makes_money(t: Object) -> void:
	var w := _world()
	_all_known(w)
	var s := w.ships_of(0)[0]
	var best := _best_pair(w, s)
	t.ok(best[0] >= 0, "a profitable neighbour pair exists (%.1f cr/t)" % best[3])
	s.system = best[0]
	var cid: String = w.economy.commodity_ids[best[2]]
	var bought := w.buy_cargo(0, s.id, cid, 750.0)
	t.ok(bought.ok, "loaded %d t of %s" % [bought.get("qty", 0), cid])
	var sent := w.send_ship(0, s.id, best[1])
	t.ok(sent.ok, "sent")
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	var sold := w.sell_cargo(0, s.id, cid, 750.0)
	t.ok(sold.ok, "sold")
	var net := 0.0
	for m in w.companies[0].ledger.values():
		for cat in ["purchases", "sales", "fuel", "docking"]:
			net += m.get(cat, 0.0)
	t.ok(net > 0.0, "the trip made money after fuel and fees (%d cr)" % net)

func test_two_stop_route_runs_five_years(t: Object) -> void:
	var w := _world()
	_all_known(w)
	var s := w.ships_of(0)[0]
	var best := _best_pair(w, s)
	s.system = best[0]
	var cid: String = w.economy.commodity_ids[best[2]]
	var orders := [
		{"system": best[0], "sell_all": true, "buy": [{"commodity": cid, "amount": 0}]},
		{"system": best[1], "sell_all": true, "buy": []},
	]
	t.ok(w.set_orders(0, s.id, orders).ok, "orders set")
	t.ok(w.start_orders(0, s.id).ok, "orders running")
	t.eq(s.status, Ship.Status.TRAVELING, "left at once")
	var arrivals := 0
	for d in 5 * 365:
		w.advance_day()
		for e in w.drain_events():
			if e.type == "arrived" and e.ship == s.id:
				arrivals += 1
	t.ok(s.orders_active, "still running after 5 years")
	t.ok(arrivals >= 20, "made %d stops" % arrivals)
	t.ok(not is_nan(w.companies[0].cash), "books intact")

func test_wait_for_full_load(t: Object) -> void:
	var w := _world()
	_all_known(w)
	var s := w.ships_of(0)[0]
	var next: int = w.galaxy.lanes_of(w.start_system)[0].other(w.start_system)
	var m := w.economy.market_at(w.start_system)
	var c := w.economy.index_of("ore")
	s.modules.assign(["bulk", "bulk", "bulk"])
	m.stock[c] = 100.0  # far less than a full load
	w.set_orders(0, s.id, [
		{"system": w.start_system, "buy": [{"commodity": "ore", "amount": 0}], "wait_full": true},
		{"system": next, "sell_all": true},
	])
	w.start_orders(0, s.id)
	t.eq(s.status, Ship.Status.DOCKED, "waiting for a full load")
	for i in 5:
		w.advance_day()
	t.eq(s.status, Ship.Status.DOCKED, "still waiting after 5 days")
	for i in 30:
		w.advance_day()
	t.ok(s.status == Ship.Status.TRAVELING or s.system == next, "gives up after the wait limit and sails")

func test_auto_trader(t: Object) -> void:
	var w := _world()
	_all_known(w)
	var s := w.ships_of(0)[0]
	var best := _best_pair(w, s)
	s.system = best[0]
	s.modules.assign(["container", "container", "auto_trader"])
	w.set_orders(0, s.id, [
		{"system": best[0], "auto": true},
		{"system": best[1], "auto": true},
	])
	w.start_orders(0, s.id)
	t.ok(not s.cargo.is_empty(), "auto-trader loaded something with a known margin")
	var c: int = s.cargo.keys()[0]
	var here := w.economy.market_at(best[0])
	var there: Dictionary = w.known_prices(0, best[1])
	t.ok(there.price[c] > here.price_at(c, here.stock[c] + s.cargo[c]),
		"it bought something worth more at the next stop")

func test_order_refusals(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var sol := w.galaxy.index_of("sol")
	t.ok(not w.set_orders(0, s.id, [{"system": w.start_system}, {"system": sol}]).ok, "uncharted stop refused")
	w.set_orders(0, s.id, [{"system": w.start_system}])
	t.ok(not w.start_orders(0, s.id).ok, "one stop is not a route")
	var next: int = w.galaxy.lanes_of(w.start_system)[0].other(w.start_system)
	w.set_orders(0, s.id, [{"system": w.start_system}, {"system": next}])
	w.start_orders(0, s.id)
	w.advance_day()
	var back := w.send_ship(0, s.id, w.start_system)
	t.ok(not s.orders_active or not back.ok, "a manual send takes the ship off its orders")

func test_sale_reports_profit_against_cost(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var bought := w.buy_cargo(0, s.id, "machinery", 300.0)
	var c := w.economy.index_of("machinery")
	s.cargo_cost[c] = bought.cost * 0.5  # as if bought cheaply elsewhere
	w.drain_events()
	var r := w.sell_cargo(0, s.id, "machinery", 300.0)
	t.ok(is_equal_approx(r.profit, r.income - bought.cost * 0.5), "profit = sale - what this ship paid")
	var sale: Array = w.drain_events().filter(func(e): return e.type == "sale")
	t.eq(sale.size(), 1, "one sale event")
	t.ok(is_equal_approx(sale[0].profit, r.profit), "the event carries the profit")

func test_route_stops_before_selling_at_a_loss(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var next := -1
	for lane in w.galaxy.lanes_of(w.start_system):
		if w.economy.market_at(lane.other(w.start_system)):
			next = lane.other(w.start_system)
	w.buy_cargo(0, s.id, "machinery", 300.0)
	var c := w.economy.index_of("machinery")
	s.cargo_cost[c] *= 10.0  # paid far too much
	w.set_orders(0, s.id, [{"system": next, "sell_all": true}, {"system": w.start_system, "sell_all": true}])
	w.start_orders(0, s.id)
	w.drain_events()
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	var stopped: Array = w.drain_events().filter(func(e): return e.type == "orders_stopped")
	t.ok(not s.orders_active, "route stopped")
	t.eq(s.cargo.get(c, 0.0), 300.0, "cargo kept")
	t.ok(stopped.size() == 1 and "loss" in stopped[0].reason, "told why: %s" % [stopped])
	t.ok(w.start_orders(0, s.id).ok, "restarted by the owner")
	t.ok(s.cargo.is_empty() or s.status == Ship.Status.TRAVELING, "sells anyway and moves on")
