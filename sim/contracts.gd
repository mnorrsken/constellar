class_name Contracts
## The contract boards (static functions on a World, like Trading).
##
## Weekly, every market posts new offers in proportion to its size: freight
## charters for goods it exports (to markets that need them), passenger
## groups (people travel between big, near places) and mail. Rewards grow
## with the load and the route length; deadlines allow a slow ship plus some
## slack. A company accepts an offer for one of its ships docked at the
## origin with room for it; arriving at the destination pays the reward;
## passing the deadline (or abandoning the job) costs the penalty and the
## load is taken off the ship.

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("contracts", {})

# --- capacity ------------------------------------------------------------------------

## Tonnes of a cargo class taken by the ship's freight charters.
static func freight_reserved(w: World, ship: Ship, cargo_class: String) -> float:
	var t := 0.0
	for c in active_for(w, ship):
		if c.kind == "freight" and w.content.commodities[c.commodity].cargo_class == cargo_class:
			t += c.amount
	return t

## Free passenger berths: {economy, luxury}.
static func free_berths(w: World, ship: Ship) -> Dictionary:
	var free := {"economy": 0, "luxury": 0}
	for m in ship.modules:
		var def: Dictionary = w.content.modules.get(m, {})
		if def.has("passengers"):
			free["luxury" if def.get("luxury", false) else "economy"] += int(def.passengers)
	for c in active_for(w, ship):
		if c.kind == "passengers":
			free["luxury" if c.luxury else "economy"] -= c.amount
	return free

static func free_mail(w: World, ship: Ship) -> int:
	var sacks := 0
	for m in ship.modules:
		sacks += int(w.content.modules.get(m, {}).get("mail", 0)) * int(cfg(w).get("mail_per_bay", 20))
	for c in active_for(w, ship):
		if c.kind == "mail":
			sacks -= c.amount
	return sacks

## Whether the ship has room for the contract's load.
static func fits(w: World, ship: Ship, c: Contract) -> bool:
	match c.kind:
		"freight":
			return Trading.free_space(w, ship, w.economy.index_of(c.commodity)) >= c.amount
		"passengers":
			return free_berths(w, ship)["luxury" if c.luxury else "economy"] >= c.amount
	return free_mail(w, ship) >= c.amount

static func active_for(w: World, ship: Ship) -> Array[Contract]:
	var out: Array[Contract] = []
	out.assign(w.jobs.get(ship.id, []))
	return out

## Open offers on a market's board.
static func offers_at(w: World, system_index: int) -> Array[Contract]:
	var out: Array[Contract] = []
	for c in w.contracts:
		if c.status == Contract.Status.OFFERED and c.origin == system_index:
			out.append(c)
	return out

# --- the board ------------------------------------------------------------------------

## Weekly: drops expired offers and posts new ones at every market.
static func post_offers(w: World) -> void:
	var k := cfg(w)
	w.contracts = w.contracts.filter(func(c): return c.status == Contract.Status.ACCEPTED \
		or (c.status == Contract.Status.OFFERED and c.offered_until > w.day))
	var open := {}  # origin -> open offers
	for c in w.contracts:
		if c.status == Contract.Status.OFFERED:
			open[c.origin] = open.get(c.origin, 0) + 1
	for m in w.economy.markets:
		if m.closed:
			continue
		var open_here: int = open.get(m.system, 0)
		var room := int(k.get("max_offers", 12)) - open_here
		var n := mini(room, roundi(m.size * float(k.get("offers_per_size", 0.7)) * w.rng.randf_range(0.5, 1.5)))
		for i in n:
			var c := _new_offer(w, m)
			if c:
				w.contracts.append(c)

static func _new_offer(w: World, m: Market) -> Contract:
	var k := cfg(w)
	var st := w.galaxy.systems[m.system].settlement
	var weights: Dictionary = k.get("kinds", {"freight": 1.0}).duplicate()
	if st.population < 1000:
		weights.erase("passengers")  # robot worlds: nobody to travel
	var kind: String = _weighted(w, weights)
	var dest := _destination(w, m, kind)
	if dest < 0:
		return null
	var route := Vector2i(m.system, dest)
	var length: float = w.contract_cache.get(route, -1.0)
	if length < 0.0:
		length = w.galaxy.path_length(w.galaxy.find_path(m.system, dest))
		w.contract_cache[route] = length
	var c := Contract.new()
	c.id = w.next_contract_id
	w.next_contract_id += 1
	c.kind = kind
	c.origin = m.system
	c.destination = dest
	match kind:
		"freight":
			c.commodity = _export_of(w, m)
			var ci := w.economy.index_of(c.commodity)
			if Trading.is_banned(w, m.system, ci) or Trading.is_banned(w, dest, ci):
				return null
			var t: Array = k.get("freight_tonnes", [100, 600])
			c.amount = roundi(w.rng.randf_range(t[0], t[1]) / 10.0) * 10
			c.reward = float(k.get("freight_base", 5000)) + c.amount * length * float(k.get("freight_rate", 4.0))
		"passengers":
			var g: Array = k.get("pax_group", [8, 60])
			c.luxury = w.rng.randf() < float(k.get("lux_share", 0.25))
			c.amount = w.rng.randi_range(int(g[0]), int(g[1]))
			if c.luxury:
				c.amount = maxi(1, c.amount / 5)
			c.reward = c.amount * length * float(k.get("lux_rate" if c.luxury else "pax_rate", 60))
		"mail":
			var s: Array = k.get("mail_sacks", [4, 20])
			c.amount = w.rng.randi_range(int(s[0]), int(s[1]))
			c.reward = c.amount * length * float(k.get("mail_rate", 160))
	c.reward = roundf(c.reward / 100.0) * 100.0
	c.penalty = roundf(c.reward * float(k.get("penalty_share", 0.3)) / 100.0) * 100.0
	var days := Fleet.travel_days(length, float(k.get("deadline_speed", 0.25)))
	var slack := float(k.get("deadline_slack", 1.4)) * (0.6 if kind == "mail" else 1.0)
	c.deadline = w.day + ceili(days * maxf(slack, 1.05)) + int(k.get("deadline_buffer", 10))
	c.offered_until = w.day + 7 * int(k.get("offer_weeks", 3))
	return c

## Where the job goes: freight to a market short of the good, people and
## mail to bigger places nearby; within max_hops lanes.
static func _destination(w: World, m: Market, kind: String) -> int:
	var people := kind == "passengers" or kind == "mail"
	var key := [m.system, people]
	if not w.contract_cache.has(key):
		w.contract_cache[key] = _destination_weights(w, m, people)
	var weights: Dictionary = w.contract_cache[key]
	if weights.is_empty():
		return -1
	return _weighted(w, weights)

static func _destination_weights(w: World, m: Market, people: bool) -> Dictionary:
	var hops := int(cfg(w).get("max_hops", 5))
	var reach := {m.system: 0}
	var frontier := [m.system]
	for h in hops:
		var next := []
		for u in frontier:
			for lane in w.galaxy.lanes_of(u):
				var v: int = lane.other(u)
				if not reach.has(v):
					reach[v] = h + 1
					next.append(v)
		frontier = next
	var weights := {}
	for v in reach:
		var dm := w.economy.market_at(v)
		if v == m.system or dm == null:
			continue
		var weight := 1.0 / float(reach[v])
		if people:
			weight *= dm.human_size + 0.5
		weights[v] = weight
	return weights

## The client's cargo: a cargo class by freight_classes, then a good of that
## class the market has (its exports first).
static func _export_of(w: World, m: Market) -> String:
	var cls: String = _weighted(w, cfg(w).get("freight_classes", {"container": 1.0}))
	var weights := {}
	for c in m.price.size():
		if Trading.commodity_class(w, c) != cls:
			continue
		if m.supply_rate[c] > m.demand_rate[c]:
			weights[c] = 3.0
		elif m.stock[c] > 0.0:
			weights[c] = 1.0
	if weights.is_empty():
		weights[w.rng.randi_range(0, m.price.size() - 1)] = 1.0
	return w.economy.commodity_ids[_weighted(w, weights)]

static func _weighted(w: World, weights: Dictionary) -> Variant:
	return _weighted_with(w.rng, weights)

static func _weighted_with(rng: RandomNumberGenerator, weights: Dictionary) -> Variant:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	var last: Variant = null
	for k in weights:
		last = k
		r -= weights[k]
		if r < 0.0:
			return k
	return last

# --- jobs ------------------------------------------------------------------------------

static func accept(w: World, company_id: int, c: Contract, ship: Ship) -> Dictionary:
	if c.status != Contract.Status.OFFERED or c.offered_until <= w.day:
		return {"ok": false, "error": "This offer is gone"}
	if ship.status != Ship.Status.DOCKED or ship.system != c.origin:
		return {"ok": false, "error": "The ship must be docked here"}
	if w.economy.market_at(c.origin).closed:
		return {"ok": false, "error": "The port is closed"}
	if not w.companies[company_id].is_known(c.destination):
		return {"ok": false, "error": "The destination is uncharted"}
	if not fits(w, ship, c):
		return {"ok": false, "error": "%s has no room for %s" % [ship.name, c.describe()]}
	c.status = Contract.Status.ACCEPTED
	c.company = company_id
	c.ship = ship.id
	w.jobs.get_or_add(ship.id, []).append(c)
	w.events.append({"type": "contract_accepted", "company": company_id, "ship": ship.id, "contract": c.id})
	return {"ok": true}

## A ship arrived: deliver every job of its that ends here.
static func deliver(w: World, ship: Ship, system_index: int) -> void:
	for c in active_for(w, ship):
		if c.destination != system_index:
			continue
		c.status = Contract.Status.DONE
		w.jobs[ship.id].erase(c)
		w.companies[c.company].book("contracts", c.reward, w.month(), ship.id)
		w.events.append({"type": "contract_done", "company": c.company, "ship": ship.id, "contract": c.id,
			"reward": c.reward, "system": system_index})

## Daily: jobs past their deadline fail; the penalty is charged and the load
## taken off the ship.
static func check_deadlines(w: World) -> void:
	for list in w.jobs.values():
		for c in list.duplicate():
			if w.day > c.deadline:
				_fail(w, c)

static func abandon(w: World, c: Contract) -> Dictionary:
	if c.status != Contract.Status.ACCEPTED:
		return {"ok": false, "error": "Not an active contract"}
	_fail(w, c)
	return {"ok": true}

static func _fail(w: World, c: Contract) -> void:
	c.status = Contract.Status.FAILED
	w.jobs.get(c.ship, []).erase(c)
	w.companies[c.company].book("penalties", -c.penalty, w.month(), c.ship)
	w.events.append({"type": "contract_failed", "company": c.company, "ship": c.ship, "contract": c.id,
		"penalty": c.penalty})
