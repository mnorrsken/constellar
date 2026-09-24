class_name Danger
## Lane danger (static functions on a World): the chance that a ship is hit
## each time it flies a lane. Every lane has a base danger from the
## governments at its ends (lawless places are worse, an empty system counts
## as `unsettled`); wars and pirates add to it (WorldEvents.apply_all).
## Each armour module multiplies a ship's risk by `armour_factor`.
##
## A hit is a raid (cargo and freight charters lost, a repair bill) or, with
## `destroy_share`, the loss of the ship. Insured ships pay a monthly
## premium priced from the risk they ran last month, and insurance pays for
## what was lost.

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("danger", {})

## Dictionary key of the lane between a and b.
static func key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))

## Base danger of every lane: {key: chance per crossing}.
static func base_map(w: World) -> Dictionary:
	var out := {}
	var empty := float(cfg(w).get("unsettled", 0.002))
	for lane in w.galaxy.lanes:
		var d := 0.0
		for i in [lane.a, lane.b]:
			var st := w.galaxy.systems[i].settlement
			d = maxf(d, empty if st == null else float(w.content.governments.get(st.government, {}).get("lane_danger", empty)))
		out[key(lane.a, lane.b)] = d
	return out

static func lane_danger(w: World, a: int, b: int) -> float:
	return w.danger.get(key(a, b), 0.0)

## The chance this ship is hit crossing the lane (armour counted).
static func ship_danger(w: World, ship: Ship, a: int, b: int) -> float:
	var d := lane_danger(w, a, b)
	var factor := float(cfg(w).get("armour_factor", 0.5))
	for m in ship.modules:
		if w.content.modules.get(m, {}).has("armour"):
			d *= factor
	return d

## Chance of at least one hit along a route of system indices.
static func route_risk(w: World, ship: Ship, path: PackedInt32Array) -> float:
	var safe := 1.0
	for i in range(1, path.size()):
		safe *= 1.0 - ship_danger(w, ship, path[i - 1], path[i])
	return 1.0 - safe

## Extra route cost (ly) per lane for "safest" routing.
static func penalty(w: World) -> Dictionary:
	var per := float(cfg(w).get("safe_ly_per_risk", 3000.0))
	var out := {}
	for k in w.danger:
		out[k] = w.danger[k] * per
	return out

## What the whole ship is worth (hull and modules at list price).
static func ship_value(w: World, ship: Ship) -> float:
	var v := float(w.fleet.hull_def(ship).price)
	for m in ship.modules:
		v += float(w.content.modules.get(m, {}).get("price", 0))
	return v

## Monthly premium for insuring the ship, from the risk it ran last month.
static func premium(w: World, ship: Ship) -> float:
	var k := cfg(w)
	return ship_value(w, ship) * maxf(float(k.get("insurance_min_rate", 0.002)),
		ship.risk_last_month * float(k.get("insurance_markup", 1.5)))

## A ship flew the lane a -> b: count the risk, roll for a hit. Returns
## "" (safe), "raided" or "lost".
static func cross(w: World, ship: Ship, a: int, b: int) -> String:
	var d := ship_danger(w, ship, a, b)
	ship.risk_month += d
	if d <= 0.0 or w.danger_rng.randf() >= d:
		return ""
	var lost := w.danger_rng.randf() < float(cfg(w).get("destroy_share", 0.25))
	var company := w.companies[ship.company]
	var cargo_value := 0.0
	for c in ship.cargo_cost:
		cargo_value += ship.cargo_cost[c]
	ship.cargo.clear()
	ship.cargo_cost.clear()
	for c in Contracts.active_for(w, ship):
		if lost or c.kind == "freight":
			Contracts.abandon(w, c)
	var payout := cargo_value
	var event := {"type": "lost" if lost else "raided", "ship": ship.id, "company": ship.company,
		"name": ship.name, "system": b, "from": a}
	if lost:
		payout += ship_value(w, ship)
		w.fleet.ships.erase(ship)
		w.jobs.erase(ship.id)
		WorldEvents.post_news(w, "The %s was lost near %s" % [ship.name, WorldEvents.place_name(w, b)],
			[a, b], "loss", true)
	else:
		var repairs := ship_value(w, ship) * float(cfg(w).get("raid_repair_share", 0.05))
		company.book("repairs", -repairs, w.month(), ship.id)
		payout += repairs
		event.repairs = repairs
	if ship.insured and payout > 0.0:
		company.book("insurance", payout, w.month(), ship.id)
		event.payout = payout
	event.cargo = cargo_value
	w.events.append(event)
	return event.type

## Month start: insured ships pay their premium; last month's risk rolls
## over.
static func monthly(w: World) -> void:
	for s in w.fleet.ships:
		s.risk_last_month = s.risk_month
		s.risk_month = 0.0
		if s.insured:
			w.companies[s.company].book("insurance", -premium(w, s), w.month(), s.id)
