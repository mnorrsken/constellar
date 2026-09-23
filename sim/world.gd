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
var companies: Array[Company] = []
var fleet: Fleet
## Things that happened since the last drain_events().
var events: Array[Dictionary] = []

var _warmup_days := 0

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
	w.start_year = int(balance.get("start_year", 3400))
	w.economy = Economy.build(w.galaxy, content)
	w.fleet = Fleet.new(w.galaxy, content)
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
	w._warmup_days = int(balance.get("economy", {}).get("warmup_days", 0))
	return w

## Lets the markets settle (balance economy.warmup_days) before the player
## arrives; the calendar stays at day 0. Called by Sim and the soak run.
func warm_up() -> void:
	for i in _warmup_days:
		economy.tick_day(i)

## One game day.
func advance_day() -> void:
	economy.tick_day(day)
	day += 1
	var moved := fleet.advance_day(day)
	events.append_array(moved)
	# Ships chart what they reach: the system itself and one jump around it.
	for e in moved:
		if e.type == "arrived" or e.type == "passed":
			reveal(fleet.get_ship(e.ship).company, e.system)

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
	var r := fleet.sell(companies[company_id], s)
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
	return fleet.plan_route(s, target_system, companies[company_id].known)

func send_ship(company_id: int, ship_id: int, target_system: int) -> Dictionary:
	var s := _own_ship(company_id, ship_id)
	if s == null:
		return {"ok": false, "error": "Not your ship"}
	var r := fleet.send(s, target_system, day, companies[company_id].known)
	if r.ok:
		events.append({"type": "departed", "ship": ship_id, "company": company_id})
	return r

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
