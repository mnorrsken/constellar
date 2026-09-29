extends RefCounted
## Contract boards: offers, accepting, delivery, deadlines, penalties, and a
## contracts-only start that grows (Contracts via World commands).

const WarmWorld := preload("res://tests/warm_world.gd")

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

func _world() -> World:
	var w := WarmWorld.make(_stars, _content)
	return w

## A freight offer at the ship's system it can carry, to a charted place.
func _freight_offer(w: World, s: Ship) -> Contract:
	w.reveal_all(0)
	for c in Contracts.offers_at(w, s.system):
		if c.kind == "freight" and Contracts.fits(w, s, c):
			return c
	return null

## Puts the ship somewhere with a suitable freight offer.
func _ship_with_offer(w: World) -> Array:
	var s := w.ships_of(0)[0]
	w.reveal_all(0)
	for m in w.economy.markets:
		s.system = m.system
		var c := _freight_offer(w, s)
		if c:
			return [s, c]
	return [s, null]

func test_boards_have_offers(t: Object) -> void:
	var w := _world()
	var total := 0
	var kinds := {}
	for m in w.economy.markets:
		for c in Contracts.offers_at(w, m.system):
			total += 1
			kinds[c.kind] = true
			t.ok(c.reward > 0.0 and c.penalty > 0.0 and c.deadline > w.day, "offer %d has terms" % c.id)
			t.ok(c.destination != c.origin, "goes somewhere")
	t.ok(total > 100, "plenty of offers across the galaxy (%d)" % total)
	t.eq(kinds.size(), 3, "freight, passengers and mail")

func test_boards_are_deterministic(t: Object) -> void:
	var a := _world()
	var b := _world()
	t.eq(a.contracts.map(func(c): return c.to_dict()), b.contracts.map(func(c): return c.to_dict()), "same seed, same boards")

func test_accept_and_deliver(t: Object) -> void:
	var w := _world()
	var pair := _ship_with_offer(w)
	var s: Ship = pair[0]
	var c: Contract = pair[1]
	t.ok(c != null, "found a freight job")
	var free_before := Trading.free_space(w, s, w.economy.index_of(c.commodity))
	t.ok(w.accept_contract(0, c.id, s.id).ok, "accepted")
	t.ok(is_equal_approx(Trading.free_space(w, s, w.economy.index_of(c.commodity)), free_before - c.amount),
		"the charter takes hold space")
	t.ok(not w.accept_contract(0, c.id, s.id).ok, "cannot take it twice")
	var cash := w.companies[0].cash
	var sent := w.send_ship(0, s.id, c.destination)
	t.ok(sent.ok, "on its way")
	while s.status == Ship.Status.TRAVELING:
		w.advance_day()
	t.eq(c.status, Contract.Status.DONE, "delivered")
	t.ok(Contracts.active_for(w, s).is_empty(), "no longer the ship's job")
	var got: float = w.companies[0].ledger.get(w.month(), {}).get("contracts", 0.0)
	t.ok(got >= c.reward, "reward booked (%d)" % got)
	t.ok(w.companies[0].cash > cash - sent.fuel.cost, "paid")

func test_missed_deadline_costs_the_penalty(t: Object) -> void:
	var w := _world()
	var pair := _ship_with_offer(w)
	var s: Ship = pair[0]
	var c: Contract = pair[1]
	w.accept_contract(0, c.id, s.id)
	var cash := w.companies[0].cash
	while w.day <= c.deadline:
		w.advance_day()
	t.eq(c.status, Contract.Status.FAILED, "failed at the deadline")
	var pen: float = w.companies[0].ledger.get(w.month(), {}).get("penalties", 0.0)
	t.ok(pen <= -c.penalty + 0.5 or w.companies[0].cash < cash, "penalty charged")
	t.ok(Contracts.active_for(w, s).is_empty(), "the load is taken off the ship")

func test_abandon(t: Object) -> void:
	var w := _world()
	var pair := _ship_with_offer(w)
	var s: Ship = pair[0]
	var c: Contract = pair[1]
	w.accept_contract(0, c.id, s.id)
	var cash := w.companies[0].cash
	t.ok(w.abandon_contract(0, c.id).ok, "abandoned")
	t.ok(is_equal_approx(w.companies[0].cash, cash - c.penalty), "penalty paid")
	t.eq(c.status, Contract.Status.FAILED, "failed")

func test_accept_refusals(t: Object) -> void:
	var w := _world()
	var s := w.ships_of(0)[0]
	var others := Contracts.offers_at(w, w.galaxy.index_of("sol"))
	t.ok(not others.is_empty(), "Earth has offers")
	t.ok(not w.accept_contract(0, others[0].id, s.id).ok, "the ship must be docked at the origin")
	var pax: Array = Contracts.offers_at(w, s.system).filter(func(c): return c.kind == "passengers")
	w.reveal_all(0)
	for c in pax:
		t.ok(not w.accept_contract(0, c.id, s.id).ok, "no cabins, no passengers")
	var berths := Contracts.free_berths(w, s)
	t.eq(berths.economy + berths.luxury, 0, "a freighter has no berths")
	s.modules.assign(["cabins", "suites", "mail"])
	berths = Contracts.free_berths(w, s)
	t.eq(berths.economy, 40, "40 economy berths")
	t.eq(berths.luxury, 8, "8 luxury suites")
	t.eq(Contracts.free_mail(w, s), 20, "20 sacks per mail bay")

func test_contracts_only_start_grows(t: Object) -> void:
	var w := _world()
	var c := w.companies[0]
	var worth := func() -> float:
		var v := c.cash
		for s in w.ships_of(0):
			v += w.fleet.sale_value(s)
		return v
	var start: float = worth.call()
	var failed := 0
	var done := 0
	for d in 4 * 365:
		for s in w.ships_of(0):
			_bot(w, s)
		w.advance_day()
		for e in w.drain_events():
			if e.type == "contract_failed":
				failed += 1
			elif e.type == "contract_done":
				done += 1
		for s in w.ships_of(0):
			if s.status == Ship.Status.DOCKED and c.cash > 650000.0 and w.fleet.is_shipyard(s.system):
				w.buy_ship(0, "packet", s.system)
	t.ok(w.ships_of(0).size() >= 2, "bought a second ship from contract income (%d ships)" % w.ships_of(0).size())
	t.ok(worth.call() > start, "and the house is worth more than at the start (%d > %d)" % [worth.call(), start])
	# Breakdowns can make a ship late now and then.
	t.ok(failed * 10 <= done, "few jobs failed (%d of %d)" % [failed, failed + done])

## Contracts only: take the best job here plus others to the same place, go;
## with nothing to do, move to the charted neighbour with most offers. A
## worn ship with no jobs gets serviced at a shipyard.
func _bot(w: World, s: Ship) -> void:
	if s.status != Ship.Status.DOCKED:
		return
	var mine := Contracts.active_for(w, s)
	if mine.is_empty() and w.fleet.is_shipyard(s.system) and Aging.needs_service(w, s):
		w.service_ship(0, s.id)
		return
	if mine.is_empty():
		var offers := Contracts.offers_at(w, s.system).filter(
			func(o): return w.companies[0].is_known(o.destination) and Contracts.fits(w, s, o))
		offers.sort_custom(func(a, b): return a.reward > b.reward)
		if not offers.is_empty():
			var dest: int = offers[0].destination
			for o in offers:
				if o.destination == dest and Contracts.fits(w, s, o):
					w.accept_contract(0, o.id, s.id)
		mine = Contracts.active_for(w, s)
	if not mine.is_empty():
		mine.sort_custom(func(a, b): return a.deadline < b.deadline)
		w.send_ship(0, s.id, mine[0].destination)
		return
	var best := -1
	var most := -1
	for lane in w.galaxy.lanes_of(s.system):
		var v: int = lane.other(s.system)
		if w.economy.market_at(v) and w.companies[0].is_known(v):
			var n := Contracts.offers_at(w, v).size()
			if n > most:
				most = n
				best = v
	if best >= 0:
		w.send_ship(0, s.id, best)

func test_express_jobs_pay_a_bonus_for_early_delivery(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	var kinds := {}
	for c in w.contracts:
		kinds[c.kind + ("_express" if c.express else "")] = true
	t.ok(kinds.has("mail_express") and not kinds.has("mail"), "all mail is express")
	t.ok(kinds.has("freight") and kinds.has("freight_express"), "some freight is express, some not")
	var mail: Contract = null
	var plain: Contract = null
	for c in w.contracts:
		if c.kind == "mail" and mail == null:
			mail = c
		if c.kind == "freight" and not c.express and plain == null:
			plain = c
	mail.accepted_day = w.day
	plain.accepted_day = w.day
	var half := w.day + (mail.deadline - w.day) / 2
	var full := Contracts.early_bonus(w, mail, w.day)
	t.ok(is_equal_approx(full, roundf(mail.reward * 0.5 / 100.0) * 100.0), "at once: half the reward on top")
	t.ok(Contracts.early_bonus(w, mail, half) < full and Contracts.early_bonus(w, mail, half) > 0.0, "less when later")
	t.eq(Contracts.early_bonus(w, mail, mail.deadline), 0.0, "nothing at the deadline")
	t.eq(Contracts.early_bonus(w, plain, w.day), 0.0, "ordinary freight has no bonus")
	# Delivered early through the real delivery: the bonus is paid and booked.
	var s := w.ships_of(0)[0]
	s.system = mail.origin
	s.modules.assign(["mail", "mail", "mail"])
	mail.accepted_day = -1
	t.ok(w.accept_contract(0, mail.id, s.id).ok, "mail taken")
	var cash := w.companies[0].cash
	w.day += 5
	Contracts.deliver(w, s, mail.destination)
	var done: Array = w.drain_events().filter(func(e): return e.type == "contract_done")
	t.ok(done.size() == 1 and done[0].bonus > 0.0, "paid a bonus: %s" % [done])
	t.ok(is_equal_approx(w.companies[0].cash - cash, mail.reward + done[0].bonus), "reward plus bonus booked")

func test_long_jobs_pay_more_per_light_year(t: Object) -> void:
	var w := _world()
	var short := {}
	var long := {}
	for c in w.contracts:
		if c.kind != "mail":
			continue
		var ly := w.galaxy.path_length(w.galaxy.find_path(c.origin, c.destination))
		var per := c.reward / (c.amount * ly)
		if ly < 10.0:
			short[per] = true
		elif ly > 30.0:
			long[per] = true
	t.ok(not short.is_empty() and not long.is_empty(), "short and long mail jobs")
	var avg := func(d: Dictionary) -> float:
		var sum := 0.0
		for k in d:
			sum += k
		return sum / d.size()
	t.ok(avg.call(long) > avg.call(short) * 1.2, "a long job's light year pays more (%.0f vs %.0f per sack and ly)" % [avg.call(long), avg.call(short)])

## Every open board keeps a plain (not express) container job to a
## neighbouring port, even right after one is taken.
func test_every_board_has_a_plain_job_next_door(t: Object) -> void:
	var w := _world()
	w.reveal_all(0)
	var plain := func(i: int) -> Contract:
		for c in Contracts.offers_at(w, i):
			if c.kind == "freight" and not c.express and _content.commodities[c.commodity].cargo_class == "container" \
					and w.galaxy.lanes_of(i).any(func(l): return l.other(i) == c.destination):
				return c
		return null
	var missing := []
	for m in w.economy.markets:
		var has_neighbour := w.galaxy.lanes_of(m.system).any(func(l): return w.economy.market_at(l.other(m.system)) != null)
		if not m.closed and has_neighbour and plain.call(m.system) == null:
			missing.append(w.galaxy.systems[m.system].name)
	t.eq(missing, [], "every open board has one")
	var s := w.ships_of(0)[0]
	var job: Contract = plain.call(s.system)
	t.ok(Contracts.fits(w, s, job), "the start ship can take it")
	t.ok(w.accept_contract(0, job.id, s.id).ok, "taken")
	t.ok(plain.call(s.system) != null, "and another one is up at once")
