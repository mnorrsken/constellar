extends RefCounted
## Influence and goals (Milestone 10): influence from trade and contracts
## (more with a prestige hull), decay, tiers and their actions (trading post, concession, the patron's
## veto and peace), patrons making wars and coups rarer, the victory goals
## and bankruptcy.

const WarmWorld := preload("res://tests/warm_world.gd")

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

func _world() -> World:
	var w := WarmWorld.make(_stars, _content)
	w.companies[0].cash = 2000000.0
	return w

## A market next to the start world.
func _next_market(w: World) -> int:
	for lane in w.galaxy.lanes_of(w.start_system):
		if w.economy.market_at(lane.other(w.start_system)):
			return lane.other(w.start_system)
	return -1

## A second house with a ship docked at `system`.
func _rival(w: World, system: int) -> Ship:
	var c := Company.from_dict(1, {"name": "Rival", "cash": 1000000})
	c.known.resize(w.galaxy.size())
	c.known.fill(1)
	c.influence.resize(w.galaxy.size())
	w.companies.append(c)
	return w.fleet.add_ship(1, "packet", system, w.day)

## A peopled market pair joined by a lane.
func _pair(w: World) -> Array:
	for lane in w.galaxy.lanes:
		var a := w.galaxy.systems[lane.a].settlement
		var b := w.galaxy.systems[lane.b].settlement
		if a and b and a.population >= 10000 and b.population >= 10000 and a.government != "custodians" \
				and b.government != "custodians":
			return [lane.a, lane.b]
	return []

func test_selling_raises_influence_more_where_goods_are_short(t: Object) -> void:
	var w := _world()
	var here := w.start_system
	t.eq(Influence.of(w, 0, here), 0.0, "no influence at the start")
	var s := w.ships_of(0)[0]
	w.buy_cargo(0, s.id, "machinery", 200.0)
	w.sell_cargo(0, s.id, "machinery", 200.0)
	t.ok(Influence.of(w, 0, here) > 0.0, "a sale adds influence (%.2f)" % Influence.of(w, 0, here))
	var other := _next_market(w)
	Influence.gain(w, 0, other, 100000.0, 1.0)
	var normal := Influence.of(w, 0, other)
	Influence.gain(w, 0, other, 100000.0, 3.0)
	t.ok(is_equal_approx(Influence.of(w, 0, other) - normal, normal * 3.0), "goods the market is short of count three times")
	var sol := w.galaxy.index_of("sol")
	Influence.gain(w, 0, sol, 100000.0, 1.0)
	t.ok(Influence.of(w, 0, sol) < normal, "a core world is harder to win than a small one")

func test_delivered_contracts_raise_influence(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	var s := w.ships_of(0)[0]
	var job: Contract = null
	for c in Contracts.offers_at(w, w.start_system):
		if Contracts.fits(w, s, c):
			job = c
			break
	t.ok(job != null, "a job that fits")
	t.ok(w.accept_contract(0, job.id, s.id).ok, "taken")
	var before := Influence.of(w, 0, job.destination)
	Contracts.deliver(w, s, job.destination)
	t.ok(Influence.of(w, 0, job.destination) > before, "delivering it adds influence at the destination")

func test_prestige_hulls_win_more_influence(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var here := w.start_system
	w.buy_cargo(0, s.id, "machinery", 100.0)
	w.sell_cargo(0, s.id, "machinery", 100.0)
	var plain := Influence.of(w, 0, here)
	var other := _world()
	var herald := other.ships_of(0)[0]
	herald.hull = "barque"
	other.buy_cargo(0, herald.id, "machinery", 100.0)
	other.sell_cargo(0, herald.id, "machinery", 100.0)
	t.ok(is_equal_approx(Influence.of(other, 0, here), plain * 1.2), "a feudal Barque's sales count 20% more")

func test_influence_decays_every_month(t: Object) -> void:
	var w := _world()
	var i := _next_market(w)
	w.companies[0].influence[i] = 50.0
	Influence.monthly(w)
	t.ok(is_equal_approx(Influence.of(w, 0, i), 50.0 * (1.0 - float(Influence.cfg(w).decay_per_month))), "decays")
	for m in 240:
		Influence.monthly(w)
	t.ok(Influence.of(w, 0, i) < 1.0, "fades to nothing without trade")

## Acceptance: long-term trade with a system raises its tier and unlocks
## the matching action (the trading post).
func test_long_term_trade_raises_the_tier_and_unlocks_a_trading_post(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	for m in w.economy.markets:
		Trading.observe(w, 0, m.system)
	var s := w.ships_of(0)[0]
	# The best container run between two neighbouring markets, judged on a
	# full load (prices move as it is bought and sold).
	var best := [-1, -1, -1, 0.0]
	for a in w.economy.markets:
		for lane in w.galaxy.lanes_of(a.system):
			var b := w.economy.market_at(lane.other(a.system))
			if b == null or lane.length > w.fleet.jump_range(s):
				continue
			for c in a.price.size():
				if Trading.commodity_class(w, c) != "container" or a.stock[c] < 800.0:
					continue
				var margin := b.quote_sell(c, 750.0) * (1.0 - Trading.tariff(w, b.system, c)) - a.quote_buy(c, 750.0)
				if margin > best[3]:
					best = [a.system, b.system, c, margin]
	var there: int = best[1]
	t.eq(w.open_trading_post(0, there).error, "Needs influence 25 here (you have 0)", "no post without influence")
	s.system = best[0]
	w.set_orders(0, s.id, [
		{"system": best[0], "sell_all": true, "buy": [{"commodity": w.economy.commodity_ids[best[2]], "amount": 0}]},
		{"system": there, "sell_all": true, "buy": []}])
	w.start_orders(0, s.id)
	var tiers := []
	for d in 3 * 365:
		w.advance_day()
		for e in w.drain_events():
			if e.type == "influence_tier" and e.system == there:
				tiers.append(e.tier)
	t.ok(Influence.tier(w, 0, there) >= Influence.Tier.POST, "three years of trade: influence %.1f" % Influence.of(w, 0, there))
	t.ok(Influence.Tier.POST in tiers, "reaching the tier was news once (%s)" % [tiers])
	t.ok(w.open_trading_post(0, there).ok, "the trading post opens")
	t.ok(Influence.has_post(w, 0, there), "and is there")
	t.ok(not w.sign_concession(0, there).ok or Influence.tier(w, 0, there) >= Influence.Tier.CONCESSION,
		"a concession needs the next tier")

func test_trading_post_gives_live_prices_and_lower_fees(t: Object) -> void:
	var w := _world()
	var i := _next_market(w)
	var s := w.ships_of(0)[0]
	w.companies[0].influence[i] = 30.0
	var cash := w.companies[0].cash
	t.ok(w.open_trading_post(0, i).ok, "opened")
	t.ok(is_equal_approx(w.companies[0].cash, cash - float(Influence.cfg(w).post_cost)), "paid for")
	t.eq(w.known_prices(0, i).day, w.day, "prices known at once")
	s.system = i
	var fee := Trading.docking_fee(w, s)
	s.system = w.start_system
	t.ok(is_equal_approx(fee, Trading.docking_fee(w, s) * 0.5), "half the docking fee there")
	for d in 14:
		w.advance_day()
	t.ok(w.known_prices(0, i).day > 7, "prices keep coming in with no ship there (day %d)" % w.known_prices(0, i).day)
	t.ok(not w.open_trading_post(0, i).ok, "only one post per system")

func test_concession_halves_tariffs_gives_first_pick_and_can_be_lost(t: Object) -> void:
	var w := _world()
	var i := -1
	for m in w.economy.markets:
		var st := w.galaxy.systems[m.system].settlement
		if float(_content.governments[st.government].get("tariffs", {}).get("*", 0.0)) > 0.0 and st.population > 100000:
			i = m.system
			break
	var c := 0
	t.ok(Trading.tariff(w, i, c) > 0.0, "a system with tariffs")
	w.companies[0].influence[i] = 45.0
	t.ok(not w.sign_concession(0, i).ok, "needs the concession tier")
	w.companies[0].influence[i] = 55.0
	t.ok(w.sign_concession(0, i).ok, "signed")
	t.ok(is_equal_approx(Trading.tariff(w, i, c, 0), Trading.tariff(w, i, c) * 0.5), "half the tariff for the holder")
	var rival := _rival(w, i)
	w.day += 7
	Contracts.post_offers(w)
	var offers := Contracts.offers_at(w, i).filter(func(o): return o.reserved_until > w.day)
	t.ok(not offers.is_empty(), "new offers there are reserved")
	var r := w.accept_contract(1, offers[0].id, rival.id)
	t.ok(not r.ok and "concession" in r.error, "a rival can't take one yet: %s" % r.get("error", ""))
	w.companies[0].influence[i] = 45.0
	Influence.monthly(w)
	t.ok(Influence.has_concession(w, 0, i), "kept while the score stays above concession_keep")
	w.companies[0].influence[i] = 39.0
	Influence.monthly(w)
	t.ok(not Influence.has_concession(w, 0, i), "lost below it")

## Acceptance: a patron can veto a tariff event.
func test_patron_vetoes_a_tariff_hike(t: Object) -> void:
	var w := _world()
	var i := _next_market(w)
	var c := w.economy.index_of("machinery")
	var before := Trading.tariff(w, i, c)
	var ev := WorldEvents.start(w, "tariff_hike", [i])
	t.ok(is_equal_approx(Trading.tariff(w, i, c), before + 0.1), "the hike adds ten points")
	var r := w.veto_event(0, ev.id)
	t.ok(not r.ok and "patron" in r.error, "only a patron may veto: %s" % r.get("error", ""))
	w.companies[0].influence[i] = 80.0
	t.ok(w.veto_event(0, ev.id).ok, "the patron vetoes it")
	t.ok(not ev in w.world_events, "the hike is over")
	t.ok(is_equal_approx(Trading.tariff(w, i, c), before), "tariffs are back")
	t.ok(is_equal_approx(Influence.of(w, 0, i), 80.0 - float(Influence.cfg(w).veto_cost)), "it cost influence")
	t.ok("lobby" in w.news[w.news.size() - 1].text, "it made the news")
	var fest := WorldEvents.start(w, "festival", [i])
	t.ok(not w.veto_event(0, fest.id).ok, "not every event can be vetoed")

func test_patrons_make_wars_and_coups_rarer(t: Object) -> void:
	var w := _world()
	var weight := func(kind: String, i: int) -> float:
		for o in WorldEvents.candidates(w, kind):
			if i in o[0]:
				return o[2]
		return 0.0
	# A system where both a coup and a war could start.
	var i := -1
	for o in WorldEvents.candidates(w, "zealots"):
		if weight.call("war", o[0][0]) > 0.0:
			i = o[0][0]
			break
	t.ok(i >= 0, "somewhere a coup or a war could happen")
	var coup: float = weight.call("zealots", i)
	var war: float = weight.call("war", i)
	var plague: float = weight.call("plague", i)
	w.companies[0].influence[i] = 80.0
	t.ok(is_equal_approx(weight.call("zealots", i), coup * 0.3), "a coup is less likely with a patron")
	t.ok(is_equal_approx(weight.call("war", i), war * 0.3), "and so is a war")
	t.ok(is_equal_approx(weight.call("plague", i), plague), "other events are unchanged")

func test_patron_of_both_sides_brokers_peace(t: Object) -> void:
	var w := _world()
	var pair := _pair(w)
	var ev := WorldEvents.start(w, "war", pair)
	w.companies[0].influence[pair[0]] = 90.0
	var r := w.broker_peace(0, ev.id)
	t.ok(not r.ok and "Both sides" in r.error, "one side is not enough: %s" % r.get("error", ""))
	w.companies[0].influence[pair[1]] = 90.0
	t.ok(w.broker_peace(0, ev.id).ok, "peace")
	t.ok(not ev in w.world_events, "the war is over")
	t.ok("peace" in w.news[w.news.size() - 1].text, "it made the news")

## Acceptance: each victory goal can be reached.
func test_company_value_goal(t: Object) -> void:
	var w := _world()
	t.ok(not w.set_goal(0, "fame").ok, "unknown goals are refused")
	t.ok(w.set_goal(0, "value").ok, "goal set")
	Goals.monthly(w)
	t.eq(w.companies[0].goal_day, -1, "not there yet (%d)" % Goals.company_value(w, 0))
	w.companies[0].cash = 30000000.0
	w.drain_events()
	Goals.monthly(w)
	t.eq(w.companies[0].goal_day, w.day, "reached")
	t.ok(w.drain_events().any(func(e): return e.type == "goal_reached"), "an event for the UI")
	Goals.monthly(w)
	t.ok(not w.drain_events().any(func(e): return e.type == "goal_reached"), "only once")

func test_merchant_prince_goal(t: Object) -> void:
	var w := _world()
	w.set_goal(0, "prince")
	var need := int(Goals.defs(w).prince.patrons)
	var markets := w.economy.markets
	for k in need - 1:
		w.companies[0].influence[markets[k].system] = 80.0
	Goals.monthly(w)
	t.eq(Goals.progress(w, 0).current, need - 1, "patron of %d" % (need - 1))
	t.eq(w.companies[0].goal_day, -1, "one short")
	w.companies[0].influence[markets[need].system] = 80.0
	Goals.monthly(w)
	t.ok(Goals.progress(w, 0).done and w.companies[0].goal_day >= 0, "Merchant Prince")

## Acceptance: bankruptcy can be reached (through the real monthly tick).
func test_bankruptcy_after_three_months_in_the_red(t: Object) -> void:
	var w := _world()
	var c := w.companies[0]
	var s := w.ships_of(0)[0]
	s.orders_active = true
	c.loan = c.loan_max
	c.cash = -100000.0
	var warnings := 0
	var bankrupt := false
	for d in 100:
		w.advance_day()
		for e in w.drain_events():
			warnings += 1 if e.type == "bankruptcy_warning" else 0
			bankrupt = bankrupt or e.type == "bankrupt"
	t.eq(warnings, 2, "two warnings")
	t.ok(bankrupt and c.bankrupt, "bankrupt after the third month")
	t.ok(not s.orders_active, "its ships stop")
	var w2 := _world()
	var c2 := w2.companies[0]
	c2.loan = c2.loan_max
	c2.cash = -100.0
	Goals.monthly(w2)
	Goals.monthly(w2)
	c2.cash = 1000.0
	Goals.monthly(w2)
	t.eq(c2.months_in_red, 0, "a month with cash resets the count")
	c2.cash = -100.0
	c2.loan = 0.0
	Goals.monthly(w2)
	t.eq(c2.months_in_red, 0, "no count while the bank would still lend")
