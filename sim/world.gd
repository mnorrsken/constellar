class_name World
extends RefCounted
## The whole game world: the star map with its planets and settlements
## (generated from a seed), the calendar, the economy, the companies and
## their ships. advance_day() is the one sim tick.
##
## Everything a player (or later a rival) does is a command method here that
## takes the acting company's id and returns {ok, error, ...}. Commands and
## ticks append events ({type, ...}) that Sim drains and turns into signals.
##
## Generation is deterministic: every system draws from its own RNG streams,
## seeded from (world seed, system id, stream name). So editing one system's
## data (e.g. known_planets.json) never changes any other system.

var world_seed: int
var galaxy: Galaxy
## Index of the fixed rim start world (balance.json "start_system"), or -1.
var start_system := -1
## Days since 1 January of start_year.
var day := 0
var start_year := 3400
var economy: Economy
## The loaded data (commodities, hulls, balance ...), for the trade rules.
var content: Dictionary
var companies: Array[Company] = []
var fleet: Fleet
## Things that happened since the last drain_events().
var events: Array[Dictionary] = []
## Contract offers and accepted jobs (see Contracts); finished ones are
## dropped at the next weekly board update.
var contracts: Array[Contract] = []
## ship id -> Array of its accepted Contracts (index kept by Contracts).
var jobs: Dictionary = {}
## Contracts cache (the lanes never change): [origin, people?] ->
## destination weights, Vector2i(origin, dest) -> route length in ly.
var contract_cache: Dictionary = {}
var next_contract_id := 0
## World-level randomness, seeded from the world seed: contract offers,
## the event rolls, and hits on dangerous lanes.
var rng: RandomNumberGenerator
var events_rng: RandomNumberGenerator
var danger_rng: RandomNumberGenerator
## Running events (see WorldEvents) and the news they made, oldest first:
## {day, text, systems, kind, start}.
var world_events: Array[WorldEvent] = []
var next_event_id := 0
var news: Array[Dictionary] = []
## Lane danger: Danger.key(a, b) -> chance of a hit per crossing (base from
## the governments at the ends, plus wars and pirates).
var danger: Dictionary = {}

var _warmup_days := 0

static func create(world_seed: int, stars_data: Dictionary, content: Dictionary) -> World:
	var w := World.new()
	w.world_seed = world_seed
	w.content = content
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
	w.start_year = int(balance.get("start_year", 3400))
	w.economy = Economy.build(w.galaxy, content)
	w.fleet = Fleet.new(w.galaxy, content)
	w.rng = stream(world_seed, "world", "contracts")
	w.events_rng = stream(world_seed, "world", "events")
	w.danger_rng = stream(world_seed, "world", "danger")
	WorldEvents.apply_all(w)
	var company_cfg: Dictionary = balance.get("company", {})
	w.companies.append(Company.from_dict(0, company_cfg))
	for c in w.companies:
		c.known.resize(w.galaxy.size())
		c.known.fill(0)
		if w.start_system >= 0:
			w.reveal(c.id, w.start_system)
	w.events.clear()
	var start_ship: Dictionary = company_cfg.get("start_ship", {})
	if w.start_system >= 0 and start_ship.has("hull"):
		w.fleet.add_ship(0, start_ship.hull, w.start_system, 0, start_ship.get("name", ""))
		for c in w.companies:
			Trading.observe(w, c.id, w.start_system)
	w._warmup_days = int(balance.get("economy", {}).get("warmup_days", 0))
	Contracts.post_offers(w)
	w.events.clear()
	return w

## Lets the markets settle (balance economy.warmup_days) before the player
## arrives; the calendar stays at day 0. Called by Sim and the soak run.
func warm_up() -> void:
	for i in _warmup_days:
		economy.tick_day(i)

## One game day: markets (weekly), events end, ships move (and may be hit
## on dangerous lanes), arrivals pay docking and learn prices, month-start
## costs and the event roll, then route orders run.
func advance_day() -> void:
	var markets_moved := economy.tick_day(day)
	day += 1
	if markets_moved:
		Trading.observe_docked(self)
		Contracts.post_offers(self)
		events.append({"type": "contracts"})
	WorldEvents.daily(self)
	for e in fleet.advance_day(day):
		var s := fleet.get_ship(e.ship)
		if s == null:
			continue  # lost earlier today
		if e.has("from") and Danger.cross(self, s, e.from, e.system) == "lost":
			continue
		events.append(e)
		if e.type == "arrived" or e.type == "passed":
			# Ships chart what they reach: the system and one jump around it.
			reveal(s.company, e.system)
		if e.type == "arrived":
			s.stop_handled = false
			Contracts.deliver(self, s, e.system)
			var port := economy.market_at(e.system)
			if port:
				if not port.closed:  # no fee while the dock workers strike
					companies[s.company].book("docking", -Trading.docking_fee(self, s), month(), s.id)
				Trading.observe(self, s.company, e.system)
	Contracts.check_deadlines(self)
	if Calendar.date(day, 0).day == 1:
		Danger.monthly(self)
		Trading.monthly_costs(self)
		WorldEvents.monthly(self)
	Trading.process_orders(self)

## Months since the start (ledger key).
func month() -> int:
	return Calendar.month_index(day)

func year() -> int:
	return start_year + day / Calendar.DAYS_PER_YEAR

func drain_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out

# --- commands (company id first) ---------------------------------------------------

func buy_ship(company_id: int, hull_id: String, system_index: int) -> Dictionary:
	var r := fleet.buy(companies[company_id], hull_id, system_index, day, year())
	if r.ok:
		events.append({"type": "bought", "ship": r.ship.id, "company": company_id})
	return r

func sell_ship(company_id: int, ship_id: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	if s.status != Ship.Status.DOCKED or not fleet.is_shipyard(s.system):
		return fleet.sell(companies[company_id], s, day)  # the refusal
	# Its jobs can't be done any more: they fail with their penalties.
	for c in Contracts.active_for(self, s):
		Contracts.abandon(self, c)
	var r := fleet.sell(companies[company_id], s, day)
	if r.ok:
		events.append({"type": "sold", "ship": ship_id, "company": company_id})
	return r

func refit_ship(company_id: int, ship_id: int, modules: Array) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	var r := fleet.refit(companies[company_id], s, modules, day)
	if r.ok:
		events.append({"type": "refitting", "ship": ship_id, "company": company_id})
	return r

## Where a company's ship could fly, over charted systems only.
func plan_route(company_id: int, ship_id: int, target_system: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	var plan := fleet.plan_route(s, target_system, companies[company_id].known, route_penalty(s))
	if plan.ok:
		plan.risk = Danger.route_risk(self, s, plan.path)
	return plan

## Extra lane costs for the ship's routing: dangerous lanes for "safest".
func route_penalty(s: Ship) -> Dictionary:
	return Danger.penalty(self) if s.safe_routing else {}

## Sends a ship by hand (this stops its route orders).
func send_ship(company_id: int, ship_id: int, target_system: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	var r := depart(s, target_system)
	if r.ok:
		s.orders_active = false
	return r

## Buys fuel for the trip and sends the ship over its company's charted
## systems. Used by send_ship and by route orders.
func depart(s: Ship, target_system: int) -> Dictionary:
	var known := companies[s.company].known
	if s.status != Ship.Status.DOCKED:
		return fleet.send(s, target_system, day, known)  # the refusal
	var penalty := route_penalty(s)
	var plan := fleet.plan_route(s, target_system, known, penalty)
	if not plan.ok:
		return plan
	var fuel := Trading.fuel_quote(self, s, plan.length)
	if companies[s.company].cash < fuel.cost:
		return {"ok": false, "error": "Not enough cash for fuel (%s cr)" % Format.thousands(roundi(fuel.cost))}
	Trading.pay_fuel(self, s, fuel)
	var r := fleet.send(s, target_system, day, known, penalty)
	if r.ok:
		r.fuel = fuel
		events.append({"type": "departed", "ship": s.id, "company": s.company})
	return r

func buy_cargo(company_id: int, ship_id: int, commodity_id: String, qty: float) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	return Trading.buy(self, s, economy.index_of(commodity_id), qty)

func sell_cargo(company_id: int, ship_id: int, commodity_id: String, qty: float) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	return Trading.sell(self, s, economy.index_of(commodity_id), qty)

## Replaces a ship's route orders (stops must be charted); they are off
## until start_orders.
func set_orders(company_id: int, ship_id: int, orders: Array) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	for stop in orders:
		if not companies[company_id].is_known(int(stop.system)):
			return {"ok": false, "error": "Stops must be charted systems"}
	s.orders.assign(orders)
	s.order_index = 0
	s.stop_handled = false
	s.orders_active = false
	events.append({"type": "orders", "ship": ship_id, "company": company_id})
	return {"ok": true}

func start_orders(company_id: int, ship_id: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	if s.orders.size() < 2:
		return {"ok": false, "error": "A route needs at least two stops"}
	# Restarting where the route stopped over a loss: the owner accepts it.
	s.allow_loss = s.status == Ship.Status.DOCKED and s.system == int(s.orders[s.order_index].system)
	s.orders_active = true
	events.append({"type": "orders", "ship": ship_id, "company": company_id})
	Trading.process_orders(self)
	return {"ok": true}

func stop_orders(company_id: int, ship_id: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	s.orders_active = false
	events.append({"type": "orders", "ship": ship_id, "company": company_id})
	return {"ok": true}

func accept_contract(company_id: int, contract_id: int, ship_id: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	var c := get_contract(contract_id)
	if s == null or c == null:
		return {"ok": false, "error": "No such ship or contract"}
	return Contracts.accept(self, company_id, c, s)

func abandon_contract(company_id: int, contract_id: int) -> Dictionary:
	var c := get_contract(contract_id)
	if c == null or c.company != company_id:
		return {"ok": false, "error": "Not your contract"}
	return Contracts.abandon(self, c)

func get_contract(contract_id: int) -> Contract:
	for c in contracts:
		if c.id == contract_id:
			return c
	return null

## A company's accepted, unfinished jobs.
func contracts_of(company_id: int) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in contracts:
		if c.company == company_id and c.status == Contract.Status.ACCEPTED:
			out.append(c)
	return out

## Insures a ship (monthly premium) or cancels its insurance.
func set_insurance(company_id: int, ship_id: int, on: bool) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	s.insured = on
	events.append({"type": "orders", "ship": ship_id, "company": company_id})
	return {"ok": true}

## "Safest" routing (around dangerous lanes) or the shortest route.
func set_routing(company_id: int, ship_id: int, safest: bool) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	s.safe_routing = safest
	events.append({"type": "orders", "ship": ship_id, "company": company_id})
	return {"ok": true}

## What a company knows of a market: {day, price} or {} (never seen).
func known_prices(company_id: int, system_index: int) -> Dictionary:
	return companies[company_id].prices.get(system_index, {})

func take_loan(company_id: int, amount: float) -> Dictionary:
	var r := companies[company_id].take_loan(amount)
	if r.ok:
		events.append({"type": "cash", "company": company_id})
	return r

func repay_loan(company_id: int, amount: float) -> Dictionary:
	var r := companies[company_id].repay_loan(amount)
	if r.ok:
		events.append({"type": "cash", "company": company_id})
	return r

## Charts a system and every system one jump from it, for good.
func reveal(company_id: int, system_index: int) -> void:
	var c := companies[company_id]
	var new := PackedInt32Array()
	for i in [system_index] + galaxy.lanes_of(system_index).map(func(l): return l.other(system_index)):
		if c.known[i] == 0:
			c.known[i] = 1
			new.append(i)
	if not new.is_empty():
		events.append({"type": "charted", "company": company_id, "systems": new})

## Charts everything (cheat).
func reveal_all(company_id: int) -> void:
	companies[company_id].known.fill(1)
	events.append({"type": "charted", "company": company_id, "systems": PackedInt32Array()})

## Ships of one company.
func ships_of(company_id: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in fleet.ships:
		if s.company == company_id:
			out.append(s)
	return out

func _own_ship(company_id: int, ship_id: int) -> Ship:
	var s := fleet.get_ship(ship_id)
	return s if s != null and s.company == company_id else null

func date_string() -> String:
	return Calendar.format(day, start_year)

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
