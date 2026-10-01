class_name Aging
## Ship wear, breakdowns and servicing (static functions on a World).
##
## Every ship has a `condition` (1 = new). It wears a little every day and
## more on every day under way. How often a travelling ship breaks down
## follows its reliability (hull reliability x condition): a breakdown
## stops it for some days and costs a repair bill. Maintenance grows with
## age. Hulls with the trait "aging_mult" wear slower or faster. Servicing
## at a shipyard brings the condition back up (dearer away from the yards
## of the hull's own builders: "foreign_service_mult"), but never
## above a cap that falls with age, so old ships keep getting worse. A ship
## on route orders that is badly worn ("auto_service_below" under its cap)
## goes to the nearest charted shipyard for a service by itself, then goes
## on with its route (Trading.process_orders).

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("aging", {})

static func age_years(w: World, ship: Ship) -> float:
	return (w.day - ship.built_day) / float(Calendar.DAYS_PER_YEAR)

## Hull reliability x condition (0..1).
static func reliability(w: World, ship: Ship) -> float:
	return float(w.fleet.hull_def(ship).get("reliability", 0.95)) * ship.condition

## Monthly maintenance, higher for older ships.
static func maintenance(w: World, ship: Ship) -> float:
	return float(w.fleet.hull_def(ship).get("maintenance", 0)) \
		* (1.0 + float(cfg(w).get("maintenance_per_year", 0.06)) * maxf(age_years(w, ship), 0.0))

## Best condition a service can bring this ship back to.
static func service_cap(w: World, ship: Ship) -> float:
	var k := cfg(w)
	return maxf(float(k.get("service_cap_min", 0.55)),
		1.0 - float(k.get("service_cap_loss_per_year", 0.02)) * maxf(age_years(w, ship), 0.0))

## {cost, days, condition (after), foreign}; cost 0 when there is nothing
## to do. `foreign`: docked where another government's yards work on it, at
## foreign_service_mult.
static func service_quote(w: World, ship: Ship) -> Dictionary:
	var cap := service_cap(w, ship)
	var gap := maxf(cap - ship.condition, 0.0)
	var foreign := ship.system >= 0 and not w.fleet.is_home_yard(ship.system, ship.hull)
	var mult := float(w.content.balance.get("shipyards", {}).get("foreign_service_mult", 1.0)) if foreign else 1.0
	return {"cost": Danger.ship_value(w, ship) * float(cfg(w).get("service_cost_share", 0.25)) * gap * mult,
		"days": int(cfg(w).get("service_days", 4)), "condition": maxf(cap, ship.condition), "foreign": foreign}

## Worth a trip to the yard: condition well below what a service gives.
static func needs_service(w: World, ship: Ship) -> bool:
	return ship.condition < service_cap(w, ship) - float(cfg(w).get("service_below", 0.1))

## Worn badly enough to break off its route for a service.
static func wants_auto_service(w: World, ship: Ship) -> bool:
	return w.day >= ship.auto_service_after \
		and ship.condition < service_cap(w, ship) - float(cfg(w).get("auto_service_below", 0.25))

## The charted shipyard the ship reaches soonest (-1 = none in range).
static func nearest_yard(w: World, ship: Ship) -> int:
	var known := w.companies[ship.company].known
	var best := -1
	var best_len := INF
	for m in w.economy.markets:
		if not w.fleet.is_shipyard(m.system) or known[m.system] == 0:
			continue
		if m.system == ship.system:
			return m.system
		var plan := w.fleet.plan_route(ship, m.system, known, w.route_penalty(ship))
		if plan.ok and plan.length < best_len:
			best_len = plan.length
			best = m.system
	return best

## A worn ship on route orders, docked: serviced here if this is a yard,
## else sent to the nearest one. True if it is handled (the route waits).
## If that fails (money, no yard in range) it keeps to its route and tries
## again after "auto_service_retry_days".
static func auto_service(w: World, ship: Ship) -> bool:
	var yard := nearest_yard(w, ship)
	var r := {"ok": false, "error": "no charted shipyard in range"}
	if yard == ship.system:
		r = service(w, ship)
		if r.ok:
			ship.note = "worn: in the yard for servicing"
			w.events.append({"type": "auto_service", "ship": ship.id, "company": ship.company, "system": yard})
			return true
	elif yard >= 0:
		r = w.depart(ship, yard)
		if r.ok:
			ship.note = "worn: going to %s for servicing" % w.galaxy.systems[yard].name
			w.events.append({"type": "auto_service_trip", "ship": ship.id, "company": ship.company, "system": yard})
			return true
	ship.auto_service_after = w.day + int(cfg(w).get("auto_service_retry_days", 30))
	w.events.append({"type": "auto_service_failed", "ship": ship.id, "company": ship.company, "reason": r.error})
	return false

## Services a ship docked at a shipyard: pays, restores the condition, and
## keeps the ship in the yard for a few days.
static func service(w: World, ship: Ship) -> Dictionary:
	if ship.status != Ship.Status.DOCKED:
		return {"ok": false, "error": "The ship must be docked"}
	if not w.fleet.is_shipyard(ship.system):
		return {"ok": false, "error": "No shipyard here"}
	var q := service_quote(w, ship)
	if q.cost < 1.0:
		return {"ok": false, "error": "%s is in as good a state as its age allows" % ship.name}
	var company := w.companies[ship.company]
	if not company.can_run(q.cost):
		return {"ok": false, "error": company.run_error("servicing", q.cost)}
	company.book("repairs", -q.cost, w.month(), ship.id)
	ship.condition = q.condition
	ship.status = Ship.Status.REFITTING
	ship.busy_until = w.day + q.days
	ship.note = "in the yard for servicing"
	w.events.append({"type": "servicing", "ship": ship.id, "company": ship.company})
	return {"ok": true, "cost": q.cost, "days": q.days}

## Daily, before ships move: wear, and breakdowns of ships under way.
static func daily(w: World) -> void:
	var k := cfg(w)
	var wear := float(k.get("wear_per_day", 0.0001))
	var travel_wear := float(k.get("wear_per_travel_day", 0.0006))
	var per_day := float(k.get("breakdown_per_day", 0.012))
	for s in w.fleet.ships:
		if s.broken_until == w.day and s.note.begins_with("broken down"):
			s.note = ""  # repaired
		var moving := s.status == Ship.Status.TRAVELING and s.broken_until <= w.day
		s.condition = maxf(s.condition - (wear + (travel_wear if moving else 0.0))
			* float(w.fleet.hull_trait(s.hull, "aging_mult", 1.0)), 0.05)
		if not moving:
			continue
		if w.wear_rng.randf() >= (1.0 - reliability(w, s)) * per_day:
			continue
		var span: Array = k.get("breakdown_days", [4, 12])
		var days := w.wear_rng.randi_range(int(span[0]), int(span[1]))
		s.broken_until = w.day + days
		s.arrival_day += days
		var bill := Danger.ship_value(w, s) * float(k.get("breakdown_repair_share", 0.01))
		w.companies[s.company].book("repairs", -bill, w.month(), s.id)
		s.note = "broken down until %s (repairs %s cr)" % [Calendar.format(s.broken_until, w.start_year),
			Format.thousands(roundi(bill))]
		w.events.append({"type": "breakdown", "ship": s.id, "company": s.company, "days": days, "repairs": bill})
