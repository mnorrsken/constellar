class_name Contracts
## The contract boards (static functions on a World, like Trading).
##
## Weekly, every market posts new offers in proportion to its size: freight
## charters for goods it exports (to markets that need them), passenger
## groups (people travel between big, near places) and mail. Rewards grow
## with the load and the route length; deadlines allow a slow ship plus some
## slack. Rewards grow a little faster than the distance (a light year of a
## long job pays more), and express jobs (mail, luxury passengers, goods
## marked "express") pay a bonus for arriving early. A company accepts an
## offer for one of its ships docked at the
## origin with room for it; arriving at the destination pays the reward
## (and adds to the company's influence there); passing the deadline (or
## abandoning the job) costs the penalty and the load is taken off the ship.
## New offers at a market where a company holds the trade concession are
## reserved for concession holders for the first days (first pick). Every
## open board always has at least one plain (not express) container job to
## a neighbouring port, which any ship docked there has charted.

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
		var reserved := w.day + int(Influence.cfg(w).get("first_pick_days", 7)) if Influence.conceded(w, m.system) else -1
		for i in n:
			var c := _new_offer(w, m)
			if c:
				c.reserved_until = reserved
				w.contracts.append(c)
		ensure_plain(w, m)

## Posts a plain container job to a neighbouring port if the board has
## none left (weekly, and when one is taken).
static func ensure_plain(w: World, m: Market) -> void:
	if m.closed:
		return
	for c in offers_at(w, m.system):
		if c.kind == "freight" and not c.express and w.content.commodities[c.commodity].cargo_class == "container" \
				and w.galaxy.lanes_of(m.system).any(func(l): return l.other(m.system) == c.destination):
			return
	for attempt in 10:
		var c := _new_offer(w, m, true)
		if c:
			w.contracts.append(c)
			return

## A new offer at a market; `plain`: a container job, not express, to a
## neighbouring port.
static func _new_offer(w: World, m: Market, plain := false) -> Contract:
	var k := cfg(w)
	var st := w.galaxy.systems[m.system].settlement
	var weights: Dictionary = k.get("kinds", {"freight": 1.0}).duplicate()
	if st.population < 1000:
		weights.erase("passengers")  # robot worlds: nobody to travel
	var kind: String = "freight" if plain else _weighted(w, weights)
	var dest := _neighbour_port(w, m) if plain else _destination(w, m, kind)
	if dest < 0:
		return null
	var route := Vector2i(m.system, dest)
	var length: float = w.contract_cache.get(route, -1.0)
	if length < 0.0:
		length = w.galaxy.path_length(w.galaxy.find_path(m.system, dest))
		w.contract_cache[route] = length
	# Long jobs pay more per light year.
	var dist := pow(length, float(k.get("distance_exponent", 1.0)))
	var c := Contract.new()
	c.id = w.next_contract_id
	w.next_contract_id += 1
	c.kind = kind
	c.origin = m.system
	c.destination = dest
	match kind:
		"freight":
			c.commodity = _export_of(w, m, plain)
			var ci := w.economy.index_of(c.commodity)
			if Trading.is_banned(w, m.system, ci) or Trading.is_banned(w, dest, ci):
				return null
			var t: Array = k.get("freight_tonnes", [100, 600])
			c.amount = roundi(w.rng.randf_range(t[0], t[1]) / 10.0) * 10
			c.reward = float(k.get("freight_base", 5000)) + c.amount * dist * float(k.get("freight_rate", 4.0))
			c.express = w.content.commodities[c.commodity].get("express", false)
		"passengers":
			var g: Array = k.get("pax_group", [8, 60])
			c.luxury = w.rng.randf() < float(k.get("lux_share", 0.25))
			c.amount = w.rng.randi_range(int(g[0]), int(g[1]))
			if c.luxury:
				c.amount = maxi(1, c.amount / 5)
			c.reward = c.amount * dist * float(k.get("lux_rate" if c.luxury else "pax_rate", 60))
			c.express = c.luxury
		"mail":
			var s: Array = k.get("mail_sacks", [4, 20])
			c.amount = w.rng.randi_range(int(s[0]), int(s[1]))
			c.reward = c.amount * dist * float(k.get("mail_rate", 160))
			c.express = true
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

## A random market one lane away (-1 = none).
static func _neighbour_port(w: World, m: Market) -> int:
	var ports := []
	for lane in w.galaxy.lanes_of(m.system):
		if w.economy.market_at(lane.other(m.system)):
			ports.append(lane.other(m.system))
	return -1 if ports.is_empty() else ports[w.rng.randi_range(0, ports.size() - 1)]

## The client's cargo: a cargo class by freight_classes, then a good of that
## class the market has (its exports first). `plain`: a container good that
## isn't express.
static func _export_of(w: World, m: Market, plain := false) -> String:
	var cls: String = "container" if plain else _weighted(w, cfg(w).get("freight_classes", {"container": 1.0}))
	var weights := {}
	for c in m.price.size():
		if Trading.commodity_class(w, c) != cls:
			continue
		if plain and w.content.commodities[w.economy.commodity_ids[c]].get("express", false):
			continue
		if m.supply_rate[c] > m.demand_rate[c]:
			weights[c] = 3.0
		elif m.stock[c] > 0.0:
			weights[c] = 1.0
	if weights.is_empty():
		if plain:
			return w.economy.commodity_ids[w.economy.index_of("machinery")]
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
	if w.day < c.reserved_until and not Influence.has_concession(w, company_id, c.origin):
		return {"ok": false, "error": "Reserved for the concession holder until %s" % Calendar.format(c.reserved_until, w.start_year)}
	if not w.companies[company_id].is_known(c.destination):
		return {"ok": false, "error": "The destination is uncharted"}
	if not fits(w, ship, c):
		return {"ok": false, "error": "%s has no room for %s" % [ship.name, c.describe()]}
	c.status = Contract.Status.ACCEPTED
	c.accepted_day = w.day
	c.company = company_id
	c.ship = ship.id
	w.jobs.get_or_add(ship.id, []).append(c)
	ensure_plain(w, w.economy.market_at(c.origin))
	w.events.append({"type": "contract_accepted", "company": company_id, "ship": ship.id, "contract": c.id})
	return {"ok": true}

## The bonus an express job earns if delivered on `day`: up to
## express_bonus x reward, by the share of the allowed time left.
static func early_bonus(w: World, c: Contract, day: int) -> float:
	if not c.express or c.accepted_day < 0 or c.deadline <= c.accepted_day:
		return 0.0
	var left := clampf(float(c.deadline - day) / float(c.deadline - c.accepted_day), 0.0, 1.0)
	return roundf(c.reward * float(cfg(w).get("express_bonus", 0.0)) * left / 100.0) * 100.0

## A ship arrived: deliver every job of its that ends here.
static func deliver(w: World, ship: Ship, system_index: int) -> void:
	for c in active_for(w, ship):
		if c.destination != system_index:
			continue
		c.status = Contract.Status.DONE
		w.jobs[ship.id].erase(c)
		var bonus := early_bonus(w, c, w.day)
		w.companies[c.company].book("contracts", c.reward + bonus, w.month(), ship.id)
		Influence.gain(w, c.company, system_index, (c.reward + bonus) * float(Influence.cfg(w).get("contract_weight", 1.0))
			* float(w.fleet.hull_trait(ship.hull, "influence_mult", 1.0)))
		w.events.append({"type": "contract_done", "company": c.company, "ship": ship.id, "contract": c.id,
			"reward": c.reward + bonus, "bonus": bonus, "system": system_index})

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
