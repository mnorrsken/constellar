class_name Trading
## Trade rules on top of World: buying and selling cargo (cargo class and
## hold space), fuel for a trip, docking fees, what each company
## knows of prices, the monthly books, and route orders. Static functions on
## a World so the world stays the single owner of state.
##
## Money always goes through Company.book(), so every credit lands in the
## ledger by category (and by ship where one is involved).

# --- prices and costs -----------------------------------------------------------

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("trade", {})

static func commodity_class(w: World, c: int) -> String:
	return w.content.commodities[w.economy.commodity_ids[c]].cargo_class

static func docking_fee(w: World, ship: Ship) -> float:
	var t := cfg(w)
	return float(t.get("docking_fee", 0)) + float(t.get("docking_fee_per_slot", 0)) * int(w.fleet.hull_def(ship).slots)

## Tonnes of hold space of the commodity's cargo class still free.
static func free_space(w: World, ship: Ship, c: int) -> float:
	var cls := commodity_class(w, c)
	var used := 0.0
	for k in ship.cargo:
		if commodity_class(w, k) == cls:
			used += ship.cargo[k]
	return maxf(float(w.fleet.capacity(ship).get(cls, 0.0)) - used, 0.0)

## {tonnes, cost} of fuel for `length_ly`, bought where the ship is (at the
## local fuel price, what the market has) or dearer where there is no market.
static func fuel_quote(w: World, ship: Ship, length_ly: float) -> Dictionary:
	var tonnes := length_ly * float(w.fleet.hull_def(ship).get("fuel_per_ly", 0))
	var fuel := w.economy.index_of(cfg(w).get("fuel_commodity", "fuel"))
	var m := w.economy.market_at(ship.system) if ship.status == Ship.Status.DOCKED else null
	var local := minf(tonnes, m.stock[fuel]) if m else 0.0
	var cost := m.quote_buy(fuel, local) if m and local > 0.0 else 0.0
	cost += (tonnes - local) * w.economy.markets[0].base_price[fuel] * float(cfg(w).get("fuel_without_market", 1.5))
	return {"tonnes": tonnes, "local": local, "cost": cost}

## Buys the fuel (taking it from the local market) and books it.
static func pay_fuel(w: World, ship: Ship, quote: Dictionary) -> void:
	var m := w.economy.market_at(ship.system)
	if m and quote.local > 0.0:
		m.buy(w.economy.index_of(cfg(w).get("fuel_commodity", "fuel")), quote.local)
	w.companies[ship.company].book("fuel", -quote.cost, w.month(), ship.id)

# --- knowledge --------------------------------------------------------------------

## The company learns the current prices of a market it has a ship at.
static func observe(w: World, company_id: int, system_index: int) -> void:
	var m := w.economy.market_at(system_index)
	if m == null:
		return
	w.companies[company_id].prices[system_index] = {"day": w.day, "price": m.price.duplicate()}

## Weekly: every company refreshes prices where it has a ship docked.
static func observe_docked(w: World) -> void:
	for s in w.fleet.ships:
		if s.status != Ship.Status.TRAVELING:
			observe(w, s.company, s.system)

# --- trading ----------------------------------------------------------------------

## Buys up to `qty` t (limited by stock, hold space and cash).
static func buy(w: World, ship: Ship, c: int, qty: float) -> Dictionary:
	var check := _at_market(w, ship)
	if not check.ok:
		return check
	var m: Market = check.market
	var company := w.companies[ship.company]
	qty = floorf(minf(qty, minf(m.stock[c], free_space(w, ship, c))))
	if qty < 1.0:
		return {"ok": false, "error": "No %s hold space free" % commodity_class(w, c) \
			if free_space(w, ship, c) < 1.0 else "None for sale"}
	var cost := m.quote_buy(c, qty)
	var tries := 0
	while cost > company.cash and tries < 8 and qty >= 1.0:
		qty = floorf(qty * company.cash / cost * 0.98)
		cost = m.quote_buy(c, qty) if qty >= 1.0 else 0.0
		tries += 1
	if qty < 1.0 or cost > company.cash:
		return {"ok": false, "error": "Not enough cash"}
	m.buy(c, qty)
	ship.cargo[c] = ship.cargo.get(c, 0.0) + qty
	ship.cargo_cost[c] = ship.cargo_cost.get(c, 0.0) + cost
	company.book("purchases", -cost, w.month(), ship.id)
	observe(w, ship.company, ship.system)
	w.events.append({"type": "cargo", "ship": ship.id, "company": ship.company})
	return {"ok": true, "qty": qty, "cost": cost}

## Sells up to `qty` t of cargo. (No sales tax: tariffs and smuggling come
## with the government rules.)
static func sell(w: World, ship: Ship, c: int, qty: float) -> Dictionary:
	var check := _at_market(w, ship)
	if not check.ok:
		return check
	var m: Market = check.market
	qty = minf(qty, ship.cargo.get(c, 0.0))
	if qty <= 0.0:
		return {"ok": false, "error": "No such cargo aboard"}
	var company := w.companies[ship.company]
	var gross := m.sell(c, qty)
	var basis: float = ship.cargo_cost.get(c, 0.0) * qty / ship.cargo[c]
	ship.cargo[c] -= qty
	ship.cargo_cost[c] = ship.cargo_cost.get(c, 0.0) - basis
	if ship.cargo[c] < 0.5:
		ship.cargo.erase(c)
		ship.cargo_cost.erase(c)
	company.book("sales", gross, w.month(), ship.id)
	observe(w, ship.company, ship.system)
	w.events.append({"type": "cargo", "ship": ship.id, "company": ship.company})
	w.events.append({"type": "sale", "ship": ship.id, "company": ship.company,
		"system": ship.system, "profit": gross - basis})
	return {"ok": true, "qty": qty, "income": gross, "profit": gross - basis}

## What selling the whole cargo here would bring, and what it cost:
## {income, cost}. No market: {income 0, cost 0}.
static func sale_quote(w: World, ship: Ship) -> Dictionary:
	var m := w.economy.market_at(ship.system)
	var income := 0.0
	var cost := 0.0
	if m == null:
		return {"income": 0.0, "cost": 0.0}
	for c in ship.cargo:
		income += m.quote_sell(c, ship.cargo[c])
		cost += ship.cargo_cost.get(c, 0.0)
	return {"income": income, "cost": cost}

static func sell_all(w: World, ship: Ship) -> void:
	for c in ship.cargo.keys():
		sell(w, ship, c, ship.cargo[c])

static func _at_market(w: World, ship: Ship) -> Dictionary:
	if ship.status != Ship.Status.DOCKED:
		return {"ok": false, "error": "The ship must be docked"}
	var m := w.economy.market_at(ship.system)
	if m == null:
		return {"ok": false, "error": "No market here"}
	return {"ok": true, "market": m}

# --- the books ----------------------------------------------------------------------

## First day of a month: crew and maintenance per ship, interest on loans.
static func monthly_costs(w: World) -> void:
	var month := w.month()
	for s in w.fleet.ships:
		var h := w.fleet.hull_def(s)
		var c := w.companies[s.company]
		c.book("crew", -float(h.get("crew_cost", 0)), month, s.id)
		c.book("maintenance", -float(h.get("maintenance", 0)), month, s.id)
	for c in w.companies:
		if c.loan > 0.0:
			c.book("interest", -c.loan * c.interest_per_year / 12.0, month)
		c.trim_ledger(month, int(cfg(w).get("ledger_months", 24)))

# --- route orders -------------------------------------------------------------------

## Runs every docked ship's route orders: at the right stop, sell then buy
## (once per visit), wait for a full load if asked (up to
## wait_full_max_days), then head for the next stop. A ship that cannot go
## on (cash, fuel, no charted route) stops its orders, and so does one whose
## cargo would sell at a loss (it keeps the cargo; restarting the route
## there sells anyway).
static func process_orders(w: World) -> void:
	for s in w.fleet.ships:
		if not s.orders_active or s.status != Ship.Status.DOCKED or s.orders.size() < 2:
			continue
		var stop: Dictionary = s.orders[s.order_index]
		if s.system != int(stop.system):
			_go(w, s, int(stop.system))
			continue
		if not s.stop_handled:
			if (stop.get("sell_all", true) or stop.get("auto", false)) and not s.cargo.is_empty():
				var q := sale_quote(w, s)
				if q.income < q.cost - 0.5 and not s.allow_loss:
					s.orders_active = false
					w.events.append({"type": "orders_stopped", "ship": s.id, "company": s.company,
						"reason": "the cargo would sell at a loss here (%s cr)" % Format.thousands(roundi(q.income - q.cost))})
					continue
				sell_all(w, s)
			s.allow_loss = false
			_load(w, s, stop)
			s.stop_handled = true
			s.wait_start = w.day
		elif stop.get("wait_full", false):
			_load(w, s, stop)
		if stop.get("wait_full", false) and not _full(w, s, stop) \
				and w.day - s.wait_start < int(cfg(w).get("wait_full_max_days", 28)):
			continue
		s.order_index = (s.order_index + 1) % s.orders.size()
		s.stop_handled = false
		_go(w, s, int(s.orders[s.order_index].system))

static func _go(w: World, s: Ship, target: int) -> void:
	var r := w.depart(s, target)
	if not r.ok:
		s.orders_active = false
		w.events.append({"type": "orders_stopped", "ship": s.id, "company": s.company, "reason": r.error})

static func _load(w: World, s: Ship, stop: Dictionary) -> void:
	if stop.get("auto", false) and "auto_trader" in s.modules:
		_auto_buy(w, s, int(s.orders[(s.order_index + 1) % s.orders.size()].system))
		return
	for b in stop.get("buy", []):
		var c := w.economy.index_of(b.commodity)
		var amount := float(b.get("amount", 0))
		var want := free_space(w, s, c) if amount <= 0.0 else maxf(amount - s.cargo.get(c, 0.0), 0.0)
		if want >= 1.0:
			buy(w, s, c, want)

## Loaded as far as this stop wants: no free space for anything it buys.
static func _full(w: World, s: Ship, stop: Dictionary) -> bool:
	if stop.get("auto", false):
		return true
	for b in stop.get("buy", []):
		var c := w.economy.index_of(b.commodity)
		var amount := float(b.get("amount", 0))
		if amount <= 0.0 and free_space(w, s, c) >= 1.0:
			return false
		if amount > 0.0 and s.cargo.get(c, 0.0) + 1.0 < amount:
			return false
	return true

## Auto-trader: for each cargo class aboard, the good with the best known
## margin at the next stop, if any is positive.
static func _auto_buy(w: World, s: Ship, next_system: int) -> void:
	var known: Dictionary = w.companies[s.company].prices.get(next_system, {})
	var m := w.economy.market_at(s.system)
	if known.is_empty() or m == null:
		return
	var best := {}  # cargo class -> [margin, commodity]
	for c in m.price.size():
		var cls := commodity_class(w, c)
		if free_space(w, s, c) < 1.0:
			continue
		var margin: float = known.price[c] - m.price[c]
		if margin > m.price[c] * 0.05 and margin > best.get(cls, [0.0])[0]:
			best[cls] = [margin, c]
	for cls in best:
		var c: int = best[cls][1]
		buy(w, s, c, free_space(w, s, c))
