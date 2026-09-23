class_name Fleet
extends RefCounted
## Every ship in the game, what they can do (specs from hulls.json and
## modules.json), where they can be bought and refitted (shipyards), and
## travel: routes limited by jump range, one day of movement per tick.
##
## Commands take the Company doing them and return {ok, error, ...}; World
## checks that the ship belongs to that company before calling in.

var ships: Array[Ship] = []

var _galaxy: Galaxy
var _hulls: Dictionary
var _modules: Dictionary
var _yards: Dictionary
var _ship_cfg: Dictionary
var _ship_names: Array
var _next_id := 0

func _init(galaxy: Galaxy, content: Dictionary) -> void:
	_galaxy = galaxy
	_hulls = content.get("hulls", {})
	_modules = content.get("modules", {})
	var balance: Dictionary = content.get("balance", {})
	_yards = balance.get("shipyards", {})
	_ship_cfg = balance.get("ships", {})
	_ship_names = content.get("names", {}).get("ship_names", [])

# --- specs -----------------------------------------------------------------------

func hull_def(ship: Ship) -> Dictionary:
	return _hulls[ship.hull]

## Light years per day, with drive tunes.
func speed(ship: Ship) -> float:
	var s := float(hull_def(ship).speed)
	for m in ship.modules:
		s *= float(_modules.get(m, {}).get("speed_mult", 1.0))
	return s

## Longest lane (ly) the ship can jump, with jump extenders.
func jump_range(ship: Ship) -> float:
	var r := float(hull_def(ship).jump_range)
	for m in ship.modules:
		r += float(_modules.get(m, {}).get("range_add", 0.0))
	return r

## {cargo class: tonnes} for this fit.
func capacity(ship: Ship) -> Dictionary:
	var out := {}
	var slot := float(hull_def(ship).slot_tonnes)
	for m in ship.modules:
		var def: Dictionary = _modules.get(m, {})
		if def.has("cargo_class"):
			out[def.cargo_class] = out.get(def.cargo_class, 0.0) + slot * float(def.capacity)
	return out

func total_capacity(ship: Ship) -> float:
	var t := 0.0
	for v in capacity(ship).values():
		t += v
	return t

func module_allowed(hull_id: String, module_id: String) -> bool:
	var allowed: Array = _hulls[hull_id].get("allowed", ["*"])
	return _modules.has(module_id) and ("*" in allowed or module_id in allowed)

## What the ship would fetch if sold: a share of hull + module prices.
func sale_value(ship: Ship) -> float:
	var v := float(hull_def(ship).price)
	for m in ship.modules:
		v += float(_modules.get(m, {}).get("price", 0))
	return v * float(_ship_cfg.get("sell_share", 0.6))

# --- shipyards ---------------------------------------------------------------------

## Industrial and high-tech worlds build ships: a shipyard archetype at
## archetype_min_tech or better, or any settlement at any_min_tech.
func is_shipyard(system_index: int) -> bool:
	var st := _galaxy.systems[system_index].settlement
	if st == null:
		return false
	if st.tech_level >= int(_yards.get("any_min_tech", 99)):
		return true
	return st.archetype in _yards.get("archetypes", []) and st.tech_level >= int(_yards.get("archetype_min_tech", 0))

## Hull ids a shipyard sells in a given year: in production and within the
## settlement's tech level.
func hulls_for_sale(system_index: int, year: int) -> Array[String]:
	var out: Array[String] = []
	if not is_shipyard(system_index):
		return out
	var tech := _galaxy.systems[system_index].settlement.tech_level
	for id in _hulls:
		var h: Dictionary = _hulls[id]
		if year >= int(h.year_from) and year <= int(h.year_to) and tech >= int(h.tech):
			out.append(id)
	return out

# --- commands ------------------------------------------------------------------------

## Adds a ship with the hull's default fit, no checks (start ships, tests).
func add_ship(company: int, hull_id: String, system_index: int, day: int, ship_name := "") -> Ship:
	var s := Ship.new()
	s.id = _next_id
	_next_id += 1
	s.company = company
	s.hull = hull_id
	s.modules.assign(_hulls[hull_id].get("default_modules", []))
	s.system = system_index
	s.bought_day = day
	s.name = ship_name if ship_name != "" else _next_name()
	ships.append(s)
	return s

func buy(company: Company, hull_id: String, system_index: int, day: int, year: int) -> Dictionary:
	if not is_shipyard(system_index):
		return {"ok": false, "error": "No shipyard here"}
	if not _hulls.has(hull_id) or not (hull_id in hulls_for_sale(system_index, year)):
		return {"ok": false, "error": "This shipyard does not build that hull"}
	var price := float(_hulls[hull_id].price)
	for m in _hulls[hull_id].get("default_modules", []):
		price += float(_modules[m].price)
	if company.cash < price:
		return {"ok": false, "error": "Not enough cash (%s needed)" % Format.thousands(roundi(price))}
	company.cash -= price
	var s := add_ship(company.id, hull_id, system_index, day)
	return {"ok": true, "ship": s, "cost": price}

func sell(company: Company, ship: Ship) -> Dictionary:
	if ship.status != Ship.Status.DOCKED or not is_shipyard(ship.system):
		return {"ok": false, "error": "Ships can only be sold docked at a shipyard"}
	var income := sale_value(ship)
	company.cash += income
	ships.erase(ship)
	return {"ok": true, "income": income}

## Replaces the fit. New modules are paid in full, removed ones sold at
## module_resale; the ship is out of service for a few days.
func refit(company: Company, ship: Ship, new_modules: Array, day: int) -> Dictionary:
	if ship.status != Ship.Status.DOCKED:
		return {"ok": false, "error": "The ship must be docked"}
	if not is_shipyard(ship.system):
		return {"ok": false, "error": "No shipyard here"}
	var slots := int(hull_def(ship).slots)
	if new_modules.size() != slots:
		return {"ok": false, "error": "This hull has %d slots" % slots}
	for m in new_modules:
		if not module_allowed(ship.hull, m):
			return {"ok": false, "error": "%s cannot be fitted to this hull" % _modules.get(m, {}).get("name", m)}
	var quote := refit_quote(ship, new_modules)
	if quote.changed == 0:
		return {"ok": false, "error": "Nothing to change"}
	if company.cash < quote.cost:
		return {"ok": false, "error": "Not enough cash (%s needed)" % Format.thousands(roundi(quote.cost))}
	company.cash -= quote.cost
	ship.modules.assign(new_modules)
	ship.status = Ship.Status.REFITTING
	ship.busy_until = day + quote.days
	return {"ok": true, "cost": quote.cost, "days": quote.days}

## {cost, days, changed} for refitting to `new_modules` (slot by slot).
func refit_quote(ship: Ship, new_modules: Array) -> Dictionary:
	var resale := float(_ship_cfg.get("module_resale", 0.5))
	var cost := 0.0
	var changed := 0
	for i in new_modules.size():
		var old: String = ship.modules[i] if i < ship.modules.size() else ""
		if new_modules[i] == old:
			continue
		changed += 1
		cost += float(_modules.get(new_modules[i], {}).get("price", 0))
		if old != "":
			cost -= float(_modules.get(old, {}).get("price", 0)) * resale
	var days := int(_ship_cfg.get("refit_days_base", 3)) + int(_ship_cfg.get("refit_days_per_slot", 2)) * changed
	return {"cost": maxf(cost, 0.0), "days": days, "changed": changed}

## Shortest route the ship can fly to `target`: {ok, path, length, days}
## or {ok: false, error}. With `known` (a company's charted systems) the
## route may only use charted systems.
func plan_route(ship: Ship, target: int, known := PackedByteArray()) -> Dictionary:
	var from := ship.destination()
	if target == from:
		return {"ok": false, "error": "Already there"}
	if not known.is_empty() and known[target] == 0:
		return {"ok": false, "error": "Uncharted system: send a ship within one jump to chart it"}
	var range_ly := jump_range(ship)
	var path := _galaxy.find_path(from, target, range_ly, known)
	if path.is_empty():
		if not _galaxy.find_path(from, target, INF, known).is_empty():
			return {"ok": false, "error": "Out of range: the route needs jumps longer than %.1f ly" % range_ly}
		return {"ok": false, "error": "No charted route"}
	var length := _galaxy.path_length(path)
	return {"ok": true, "path": path, "length": length, "days": travel_days(length, speed(ship))}

static func travel_days(length: float, ly_per_day: float) -> int:
	return maxi(1, ceili((length - 1e-6) / ly_per_day))

func send(ship: Ship, target: int, day: int, known := PackedByteArray()) -> Dictionary:
	if ship.status == Ship.Status.REFITTING:
		return {"ok": false, "error": "The ship is being refitted"}
	if ship.status == Ship.Status.TRAVELING:
		return {"ok": false, "error": "The ship is already under way"}
	var plan := plan_route(ship, target, known)
	if not plan.ok:
		return plan
	ship.status = Ship.Status.TRAVELING
	ship.route = plan.path
	ship.leg = 0
	ship.leg_progress = 0.0
	ship.system = -1
	ship.departed_day = day
	ship.arrival_day = day + plan.days
	return {"ok": true, "arrival_day": ship.arrival_day, "path": plan.path}

# --- time ----------------------------------------------------------------------------

## Moves every ship one day; `new_day` is the day being entered. Returns
## events: {type: "arrived"|"passed"|"refitted", ship, system} ("passed" =
## went through a system on the way).
func advance_day(new_day: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for s in ships:
		match s.status:
			Ship.Status.REFITTING:
				if new_day >= s.busy_until:
					s.status = Ship.Status.DOCKED
					events.append({"type": "refitted", "ship": s.id, "system": s.system})
			Ship.Status.TRAVELING:
				_move(s, speed(s), events)
	return events

## Moves a ship `ly` along its route, adding passed/arrived events.
func _move(s: Ship, ly: float, events: Array[Dictionary]) -> void:
	var remaining := ly
	while remaining > 0.0:
		var left := _galaxy.distance(s.route[s.leg], s.route[s.leg + 1]) - s.leg_progress
		if remaining + 1e-9 < left:
			s.leg_progress += remaining
			return
		remaining -= left
		s.leg += 1
		s.leg_progress = 0.0
		if s.leg >= s.route.size() - 1:
			s.status = Ship.Status.DOCKED
			s.system = s.route[s.route.size() - 1]
			s.route = PackedInt32Array()
			s.leg = 0
			events.append({"type": "arrived", "ship": s.id, "system": s.system})
			return
		events.append({"type": "passed", "ship": s.id, "system": s.route[s.leg]})

## Galactic position of a travelling ship `extra_ly` beyond where the sim
## has it (the renderer passes speed x day fraction for smooth motion), and
## the unit direction it is heading. Docked ships: their system, Vector3.ZERO.
func route_point(s: Ship, extra_ly: float) -> Array:
	if s.status != Ship.Status.TRAVELING:
		return [_galaxy.systems[s.system].position, Vector3.ZERO]
	var leg := s.leg
	var along := s.leg_progress + extra_ly
	while leg < s.route.size() - 2 and along > _galaxy.distance(s.route[leg], s.route[leg + 1]):
		along -= _galaxy.distance(s.route[leg], s.route[leg + 1])
		leg += 1
	var a := _galaxy.systems[s.route[leg]].position
	var b := _galaxy.systems[s.route[leg + 1]].position
	var t := clampf(along / maxf(a.distance_to(b), 1e-6), 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]

func get_ship(ship_id: int) -> Ship:
	for s in ships:
		if s.id == ship_id:
			return s
	return null

func _next_name() -> String:
	var used := {}
	for s in ships:
		used[s.name] = true
	for n in _ship_names:
		if not used.has(n):
			return n
	var k := ships.size() + 1
	while used.has("Ship %d" % k):
		k += 1
	return "Ship %d" % k
