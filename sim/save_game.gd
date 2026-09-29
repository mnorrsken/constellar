class_name SaveGame
## Saving and loading a World as JSON (static functions, like Trading).
##
## A save holds what changes as the game runs; everything fixed (the star
## map, planets, settlement names and archetypes, market recipes) is made
## again from the world seed, as at a new game, and the saved state is laid
## over it. Derived state (event effects on markets, tariffs, bans, lane
## danger, prices from stock) is rebuilt with WorldEvents.apply_all.
##
## Everything is written with explicit types and in its original order (JSON
## turns every number into a float and every key into a string), and floats
## exactly: a plain JSON number when it reads back unchanged, else its bits
## ("x:" + hex; Godot's JSON rounds about one double in four), and long
## float arrays as base64 of their bytes. So a loaded world saves to the
## very same text, and runs on exactly like the original.
## File: {"meta": {...}, "world": {...}}; `meta` is for the load list only.

## Bumped when the layout changes; older saves are refused.
const FORMAT := 1
const DIR := "user://saves/"

# --- World <-> data ------------------------------------------------------------------

static func to_data(w: World) -> Dictionary:
	var settlements := []
	for s in w.galaxy.systems:
		if s.settlement:
			settlements.append([s.index, s.settlement.government, _f(s.settlement.stability),
				int(s.settlement.population)])
	var markets := []
	for m in w.economy.markets:
		markets.append({"system": m.system, "stock": _f64s(m.stock),
			"history": m.history.map(func(h): return _f32s(h))})
	var jobs := []
	for ship_id in w.jobs:
		jobs.append([int(ship_id), w.jobs[ship_id].map(func(c): return c.id)])
	return {
		"format": FORMAT,
		"seed": w.world_seed,
		"systems": w.galaxy.size(),
		"lanes": w.galaxy.lanes.size(),
		"day": w.day,
		"rng": {"contracts": _rng(w.rng), "events": _rng(w.events_rng), "danger": _rng(w.danger_rng),
			"wear": _rng(w.wear_rng)},
		"settlements": settlements,
		"markets": markets,
		"companies": w.companies.map(_company),
		"next_ship_id": w.fleet._next_id,
		"ships": w.fleet.ships.map(_ship),
		"next_contract_id": w.next_contract_id,
		"contracts": w.contracts.map(_contract),
		"jobs": jobs,
		"next_event_id": w.next_event_id,
		"world_events": w.world_events.map(_event),
		"news": w.news.map(_news),
	}

## A world from saved data (null with `error` set when it can't be read).
static func from_data(d: Dictionary, stars: Dictionary, content: Dictionary, error: Array = []) -> World:
	if int(d.get("format", 0)) != FORMAT:
		error.append("This save is from another version of the game")
		return null
	var w := World.create(int(d.seed), stars, content)
	if int(d.get("systems", -1)) != w.galaxy.size() or int(d.get("lanes", -1)) != w.galaxy.lanes.size():
		error.append("This save is from another version of the star map")
		return null
	w.day = int(d.day)
	_set_rng(w.rng, d.rng.contracts)
	_set_rng(w.events_rng, d.rng.events)
	_set_rng(w.danger_rng, d.rng.danger)
	_set_rng(w.wear_rng, d.rng.wear)
	for row in d.settlements:
		var st := w.galaxy.systems[int(row[0])].settlement
		st.government = str(row[1])
		st.stability = _rf(row[2])
		st.population = int(row[3])
	for k in d.markets.size():
		var m := w.economy.markets[k]
		var md: Dictionary = d.markets[k]
		m.stock = _rf64s(md.stock)
		m.history.clear()
		for h in md.history:
			m.history.append(_rf32s(h))
	w.companies.clear()
	for cd in d.companies:
		w.companies.append(_load_company(cd))
	w.fleet.ships.clear()
	for sd in d.ships:
		w.fleet.ships.append(_load_ship(sd))
	w.fleet._next_id = int(d.next_ship_id)
	w.contracts.clear()
	var by_id := {}
	for cd in d.contracts:
		var c := _load_contract(cd)
		w.contracts.append(c)
		by_id[c.id] = c
	w.next_contract_id = int(d.next_contract_id)
	w.jobs.clear()
	for row in d.jobs:
		w.jobs[int(row[0])] = row[1].map(func(id): return by_id[int(id)])
	w.world_events.clear()
	for ed in d.world_events:
		w.world_events.append(_load_event(ed))
	w.next_event_id = int(d.next_event_id)
	w.news.clear()
	for nd in d.news:
		w.news.append(_load_news(nd))
	w.contract_cache.clear()
	WorldEvents.apply_all(w)
	w.events.clear()
	return w

## The world as save text (without meta), for comparing two worlds.
static func to_json(w: World) -> String:
	return JSON.stringify(to_data(w), "", false, true)

# --- files -----------------------------------------------------------------------------

## Writes a save file; `meta` shows in the load list. {ok, path} or {ok,
## error}.
static func write(w: World, path: String, meta: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]}
	f.store_string(JSON.stringify({"meta": meta, "world": to_data(w)}, "", false, true))
	f.close()
	return {"ok": true, "path": path}

## Reads a save file: {ok, world, meta} or {ok, error}.
static func read(path: String, stars: Dictionary, content: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "No such save"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not parsed.has("world"):
		return {"ok": false, "error": "The save file is damaged"}
	var error := []
	var w := from_data(parsed.world, stars, content, error)
	if w == null:
		return {"ok": false, "error": error[0] if not error.is_empty() else "Can't load this save"}
	return {"ok": true, "world": w, "meta": parsed.get("meta", {})}

## The save files in `dir`, newest first: [{path, name, modified, meta}].
static func list(dir := DIR) -> Array:
	var out := []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for file in da.get_files():
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var meta := {}
		var head: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if head is Dictionary:
			meta = head.get("meta", {})
		out.append({"path": path, "name": file.get_basename(), "modified": FileAccess.get_modified_time(path),
			"meta": meta})
	out.sort_custom(func(a, b): return a.modified > b.modified)
	return out

## A file-safe save name ("My game 2" -> "my_game_2").
static func file_name(name: String) -> String:
	var out := ""
	for ch in name.strip_edges().to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out if out.replace("_", "") != "" else "save"

# --- parts ------------------------------------------------------------------------------

## A float, exactly: a JSON number if it reads back unchanged, else "x:" and
## the hex of its 8 bytes.
static func _f(x: float) -> Variant:
	if JSON.stringify(x, "", false, true).to_float() == x:
		return x
	return "x:" + PackedFloat64Array([x]).to_byte_array().hex_encode()

static func _rf(v: Variant) -> float:
	if v is String and v.begins_with("x:"):
		return v.substr(2).hex_decode().to_float64_array()[0]
	return float(v)

## Float arrays as base64 of their bytes (exact, and small).
static func _f64s(a: Variant) -> String:
	return Marshalls.raw_to_base64(PackedFloat64Array(a).to_byte_array())

static func _rf64s(v: Variant) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(str(v)).to_float64_array()

static func _f32s(a: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())

static func _rf32s(v: Variant) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(str(v)).to_float32_array()

## Seed and state as strings: 64-bit integers don't survive JSON numbers.
static func _rng(r: RandomNumberGenerator) -> Array:
	return [str(r.seed), str(r.state)]

static func _set_rng(r: RandomNumberGenerator, v: Array) -> void:
	r.seed = str(v[0]).to_int()
	r.state = str(v[1]).to_int()

## {int key: value} as ordered [[key, value]] pairs.
static func _pairs(d: Dictionary, value: Callable) -> Array:
	var out := []
	for k in d:
		out.append([int(k), value.call(d[k])])
	return out

static func _company(c: Company) -> Dictionary:
	var prices := []
	for i in c.prices:
		prices.append([int(i), int(c.prices[i].day), _f64s(c.prices[i].price)])
	var ledger := func(book: Dictionary) -> Array:
		var out := []
		for m in book:
			var cats := []
			for k in book[m]:
				cats.append([str(k), _f(book[m][k])])
			out.append([int(m), cats])
		return out
	var ship_ledger := []
	for id in c.ship_ledger:
		ship_ledger.append([int(id), ledger.call(c.ship_ledger[id])])
	var known := ""
	for b in c.known:
		known += "1" if b != 0 else "0"
	return {
		"id": c.id, "name": c.name, "color": c.color.to_html(), "cash": _f(c.cash), "loan": _f(c.loan),
		"loan_max": _f(c.loan_max), "interest_per_year": _f(c.interest_per_year),
		"overdraft": _f(c.overdraft), "known": known, "prices": prices,
		"ledger": ledger.call(c.ledger), "ship_ledger": ship_ledger, "influence": _f64s(c.influence),
		"posts": _pairs(c.posts, func(v): return bool(v)), "concessions": _pairs(c.concessions, func(v): return bool(v)),
		"tiers_reached": _pairs(c.tiers_reached, func(v): return int(v)),
		"goal": c.goal, "goal_day": c.goal_day, "months_in_red": c.months_in_red, "bankrupt": c.bankrupt,
	}

static func _load_company(d: Dictionary) -> Company:
	var c := Company.new()
	c.id = int(d.id)
	c.name = str(d.name)
	c.color = Color.html(str(d.color))
	c.cash = _rf(d.cash)
	c.loan = _rf(d.loan)
	c.loan_max = _rf(d.loan_max)
	c.interest_per_year = _rf(d.interest_per_year)
	c.overdraft = _rf(d.overdraft)
	var known: String = d.known
	c.known.resize(known.length())
	for i in known.length():
		c.known[i] = 1 if known[i] == "1" else 0
	for row in d.prices:
		c.prices[int(row[0])] = {"day": int(row[1]), "price": _rf64s(row[2])}
	var ledger := func(rows: Array) -> Dictionary:
		var out := {}
		for row in rows:
			var cats := {}
			for cat in row[1]:
				cats[str(cat[0])] = _rf(cat[1])
			out[int(row[0])] = cats
		return out
	c.ledger = ledger.call(d.ledger)
	for row in d.ship_ledger:
		c.ship_ledger[int(row[0])] = ledger.call(row[1])
	c.influence = _rf64s(d.influence)
	for row in d.posts:
		c.posts[int(row[0])] = bool(row[1])
	for row in d.concessions:
		c.concessions[int(row[0])] = bool(row[1])
	for row in d.tiers_reached:
		c.tiers_reached[int(row[0])] = int(row[1])
	c.goal = str(d.goal)
	c.goal_day = int(d.goal_day)
	c.months_in_red = int(d.months_in_red)
	c.bankrupt = bool(d.bankrupt)
	return c

## A route stop with fixed types: system int, buy amounts float (exact),
## flags bool. `loading`: read from a save instead of writing one.
static func _stop(s: Dictionary, loading := false) -> Dictionary:
	var out := {}
	for k in s:
		match k:
			"system":
				out[k] = int(s[k])
			"buy":
				out[k] = s[k].map(func(b):
					var amount: Variant = b.get("amount", 0.0)
					return {"commodity": str(b.commodity), "amount": _rf(amount) if loading else _f(float(amount))})
			_:
				out[k] = bool(s[k])
	return out

static func _ship(s: Ship) -> Dictionary:
	return {
		"id": s.id, "name": s.name, "company": s.company, "hull": s.hull, "modules": Array(s.modules),
		"status": int(s.status), "system": s.system, "route": Array(s.route), "leg": s.leg,
		"leg_progress": _f(s.leg_progress), "departed_day": s.departed_day, "arrival_day": s.arrival_day,
		"busy_until": s.busy_until, "bought_day": s.bought_day, "built_day": s.built_day,
		"condition": _f(s.condition), "broken_until": s.broken_until,
		"auto_service_after": s.auto_service_after, "month_days": s.month_days,
		"month_days_under_way": s.month_days_under_way, "note": s.note,
		"cargo": _pairs(s.cargo, _f), "cargo_cost": _pairs(s.cargo_cost, _f),
		"orders": s.orders.map(_stop), "order_index": s.order_index, "orders_active": s.orders_active,
		"stop_handled": s.stop_handled, "wait_start": s.wait_start, "allow_loss": s.allow_loss,
		"insured": s.insured, "safe_routing": s.safe_routing, "risk_month": _f(s.risk_month),
		"risk_last_month": _f(s.risk_last_month),
	}

static func _load_ship(d: Dictionary) -> Ship:
	var s := Ship.new()
	s.id = int(d.id)
	s.name = str(d.name)
	s.company = int(d.company)
	s.hull = str(d.hull)
	s.modules.assign(d.modules.map(func(m): return str(m)))
	s.status = int(d.status) as Ship.Status
	s.system = int(d.system)
	s.route = PackedInt32Array(d.route.map(func(i): return int(i)))
	s.leg = int(d.leg)
	s.leg_progress = _rf(d.leg_progress)
	s.departed_day = int(d.departed_day)
	s.arrival_day = int(d.arrival_day)
	s.busy_until = int(d.busy_until)
	s.bought_day = int(d.bought_day)
	s.built_day = int(d.built_day)
	s.condition = _rf(d.condition)
	s.broken_until = int(d.broken_until)
	s.auto_service_after = int(d.auto_service_after)
	s.month_days = int(d.month_days)
	s.month_days_under_way = int(d.month_days_under_way)
	s.note = str(d.note)
	for row in d.cargo:
		s.cargo[int(row[0])] = _rf(row[1])
	for row in d.cargo_cost:
		s.cargo_cost[int(row[0])] = _rf(row[1])
	s.orders.assign(d.orders.map(func(o): return _stop(o, true)))
	s.order_index = int(d.order_index)
	s.orders_active = bool(d.orders_active)
	s.stop_handled = bool(d.stop_handled)
	s.wait_start = int(d.wait_start)
	s.allow_loss = bool(d.allow_loss)
	s.insured = bool(d.insured)
	s.safe_routing = bool(d.safe_routing)
	s.risk_month = _rf(d.risk_month)
	s.risk_last_month = _rf(d.risk_last_month)
	return s

static func _contract(c: Contract) -> Dictionary:
	return {
		"id": c.id, "kind": c.kind, "origin": c.origin, "destination": c.destination, "commodity": c.commodity,
		"luxury": c.luxury, "amount": c.amount, "reward": _f(c.reward), "penalty": _f(c.penalty),
		"deadline": c.deadline, "offered_until": c.offered_until, "reserved_until": c.reserved_until,
		"express": c.express, "accepted_day": c.accepted_day, "status": int(c.status), "company": c.company,
		"ship": c.ship,
	}

static func _load_contract(d: Dictionary) -> Contract:
	var c := Contract.new()
	c.id = int(d.id)
	c.kind = str(d.kind)
	c.origin = int(d.origin)
	c.destination = int(d.destination)
	c.commodity = str(d.commodity)
	c.luxury = bool(d.luxury)
	c.amount = int(d.amount)
	c.reward = _rf(d.reward)
	c.penalty = _rf(d.penalty)
	c.deadline = int(d.deadline)
	c.offered_until = int(d.offered_until)
	c.reserved_until = int(d.reserved_until)
	c.express = bool(d.express)
	c.accepted_day = int(d.accepted_day)
	c.status = int(d.status) as Contract.Status
	c.company = int(d.company)
	c.ship = int(d.ship)
	return c

static func _event(e: WorldEvent) -> Dictionary:
	return {"id": e.id, "kind": e.kind, "systems": Array(e.systems), "on_lane": e.on_lane,
		"start_day": e.start_day, "end_day": e.end_day, "headline": e.headline}

static func _load_event(d: Dictionary) -> WorldEvent:
	var e := WorldEvent.new()
	e.id = int(d.id)
	e.kind = str(d.kind)
	e.systems.assign(d.systems.map(func(i): return int(i)))
	e.on_lane = bool(d.on_lane)
	e.start_day = int(d.start_day)
	e.end_day = int(d.end_day)
	e.headline = str(d.headline)
	return e

static func _news(n: Dictionary) -> Dictionary:
	return {"day": int(n.day), "text": str(n.text), "systems": n.systems.map(func(i): return int(i)),
		"kind": str(n.kind), "start": bool(n.start)}

static func _load_news(d: Dictionary) -> Dictionary:
	return _news(d)
