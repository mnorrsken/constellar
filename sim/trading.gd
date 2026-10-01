class_name Trading
## Trade rules on top of World: buying and selling cargo (cargo class and
## hold space, the government's tariffs and bans, closed ports), fuel for a
## trip, docking fees, what each company knows of prices, the monthly
## books, and route orders. Static functions on
## a World so the world stays the single owner of state.
##
## Money always goes through Company.book(), so every credit lands in the
## ledger by category (and by ship where one is involved).

# --- prices and costs -----------------------------------------------------------

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("trade", {})

static func commodity_class(w: World, c: int) -> String:
	return w.content.commodities[w.economy.commodity_ids[c]].cargo_class

## The government's duty on goods sold at a system (share of the income):
## its tariff profile (governments.json "tariffs": per good or "*") plus
## any tariff hike, waived under a trade agreement, and lower for a company
## holding the trade concession there (company_id -1: the general rate).
static func tariff(w: World, system_index: int, c: int, company_id := -1) -> float:
	var st := w.galaxy.systems[system_index].settlement
	var m := w.economy.market_at(system_index)
	if st == null or m == null:
		return 0.0
	var profile: Dictionary = w.content.governments.get(st.government, {}).get("tariffs", {})
	var rate := (float(profile.get(w.economy.commodity_ids[c], profile.get("*", 0.0))) + m.tariff_add) * m.tariff_mult
	return rate * Influence.tariff_factor(w, company_id, system_index) if company_id >= 0 else rate

## Banned goods can't be bought or sold there (governments.json "bans").
static func is_banned(w: World, system_index: int, c: int) -> bool:
	var st := w.galaxy.systems[system_index].settlement
	return st != null and w.economy.commodity_ids[c] in w.content.governments.get(st.government, {}).get("bans", [])

## At the ship's port (lower at its company's trading post there).
static func docking_fee(w: World, ship: Ship) -> float:
	var t := cfg(w)
	return (float(t.get("docking_fee", 0)) + float(t.get("docking_fee_per_slot", 0)) * int(w.fleet.hull_def(ship).slots)) \
		* Influence.docking_factor(w, ship.company, ship.system)

## Tonnes of hold space of the commodity's cargo class still free (freight
## charters take their share).
static func free_space(w: World, ship: Ship, c: int) -> float:
	var cls := commodity_class(w, c)
	var used := Contracts.freight_reserved(w, ship, cls)
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
	if m and m.closed:
		m = null
	var local := minf(tonnes, m.available(fuel)) if m else 0.0
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
	if is_banned(w, ship.system, c):
		return {"ok": false, "error": "%s are banned here" % _name(w, c)}
	var company := w.companies[ship.company]
	qty = floorf(minf(qty, minf(m.available(c), free_space(w, ship, c))))
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

## Sells up to `qty` t of cargo; the government's tariff is taken from the
## income. The sale adds to the company's influence there.
static func sell(w: World, ship: Ship, c: int, qty: float) -> Dictionary:
	var check := _at_market(w, ship)
	if not check.ok:
		return check
	var m: Market = check.market
	if is_banned(w, ship.system, c):
		return {"ok": false, "error": "%s are banned here" % _name(w, c)}
	qty = minf(qty, ship.cargo.get(c, 0.0))
	if qty <= 0.0:
		return {"ok": false, "error": "No such cargo aboard"}
	var company := w.companies[ship.company]
	var shortage := m.price[c] / m.base_price[c]
	var gross := m.sell(c, qty)
	var basis: float = ship.cargo_cost.get(c, 0.0) * qty / ship.cargo[c]
	ship.cargo[c] -= qty
	ship.cargo_cost[c] = ship.cargo_cost.get(c, 0.0) - basis
	if ship.cargo[c] < 0.5:
		ship.cargo.erase(c)
		ship.cargo_cost.erase(c)
	if gross - basis - gross * tariff(w, ship.system, c, ship.company) > 0.0:
		m.add_pull(c, qty)
	company.book("sales", gross, w.month(), ship.id)
	company.note_cost_of_sales(basis, w.month(), ship.id)
	var duty := gross * tariff(w, ship.system, c, ship.company)
	if duty > 0.0:
		company.book("tariffs", -duty, w.month(), ship.id)
	Influence.gain(w, ship.company, ship.system,
		gross * float(w.fleet.hull_trait(ship.hull, "influence_mult", 1.0)), shortage)
	observe(w, ship.company, ship.system)
	w.events.append({"type": "cargo", "ship": ship.id, "company": ship.company})
	w.events.append({"type": "sale", "ship": ship.id, "company": ship.company,
		"system": ship.system, "profit": gross - duty - basis})
	return {"ok": true, "qty": qty, "income": gross - duty, "profit": gross - duty - basis}

## What selling the whole cargo here would bring after tariffs, and what it
## cost: {income, cost}. Banned goods stay aboard and don't count. No
## market: {income 0, cost 0}.
static func sale_quote(w: World, ship: Ship) -> Dictionary:
	var m := w.economy.market_at(ship.system)
	var income := 0.0
	var cost := 0.0
	if m == null:
		return {"income": 0.0, "cost": 0.0}
	for c in ship.cargo:
		if is_banned(w, ship.system, c):
			continue
		income += m.quote_sell(c, ship.cargo[c]) * (1.0 - tariff(w, ship.system, c, ship.company))
		cost += ship.cargo_cost.get(c, 0.0)
	return {"income": income, "cost": cost}

## Sells everything that may be sold here (banned goods stay aboard).
static func sell_all(w: World, ship: Ship) -> void:
	for c in ship.cargo.keys():
		if not is_banned(w, ship.system, c):
			sell(w, ship, c, ship.cargo[c])

static func _at_market(w: World, ship: Ship) -> Dictionary:
	if ship.status != Ship.Status.DOCKED:
		return {"ok": false, "error": "The ship must be docked"}
	var m := w.economy.market_at(ship.system)
	if m == null:
		return {"ok": false, "error": "No market here"}
	if m.closed:
		return {"ok": false, "error": "The port is closed"}
	return {"ok": true, "market": m}

static func _name(w: World, c: int) -> String:
	return w.content.commodities[w.economy.commodity_ids[c]].name

# --- the books ----------------------------------------------------------------------

## First day of a month: crew and maintenance per ship for the share of
## last month it spent under way (a ship in port costs nothing), interest
## on loans.
static func monthly_costs(w: World) -> void:
	var month := w.month()
	for s in w.fleet.ships:
		var h := w.fleet.hull_def(s)
		var c := w.companies[s.company]
		var share := float(s.month_days_under_way) / float(s.month_days) if s.month_days > 0 else 0.0
		s.month_days = 0
		s.month_days_under_way = 0
		if share <= 0.0:
			continue
		c.book("crew", -float(h.get("crew_cost", 0)) * share, month, s.id)
		c.book("maintenance", -Aging.maintenance(w, s) * share, month, s.id)
	for c in w.companies:
		if c.loan > 0.0:
			c.book("interest", -c.loan * c.interest_per_year / 12.0, month)
		c.trim_ledger(month, int(cfg(w).get("ledger_months", 24)))

## Why a ship made a loss in a month, from its books (empty if it didn't).
## Goods count when sold (Company.profit).
static func loss_reason(company: Company, ship_id: int, month: int) -> String:
	var cats: Dictionary = company.ship_ledger.get(ship_id, {}).get(month, {})
	if company.profit(month, ship_id) >= 0.0 or cats.is_empty():
		return ""
	var sales: float = cats.get("sales", 0.0) + cats.get("tariffs", 0.0)
	var cost: float = -cats.get("cost_of_sales", 0.0)
	var income: float = sales + cats.get("contracts", 0.0) + maxf(cats.get("insurance", 0.0), 0.0)
	var worst := ""
	for k in cats:
		if cats[k] < 0.0 and not (k in ["purchases", "cost_of_sales", "ships"]) and (worst == "" or cats[k] < cats[worst]):
			worst = k
	if sales > 0.0 and sales < cost:
		return "price too low: sold for %s less than it cost" % Format.thousands(roundi(cost - sales))
	if income <= 0.0:
		return "earned nothing: no sales or contracts"
	if worst == "repairs":
		return "repairs ate the profit (%s cr)" % Format.thousands(roundi(-cats.repairs))
	return "running costs above income (most: %s)" % worst

# --- route orders -------------------------------------------------------------------

## Runs every docked ship's route orders: at the right stop, sell then buy
## (once per visit), wait for a full load if asked (up to
## wait_full_max_days), then head for the next stop. A ship that cannot go
## on (cash, fuel, no charted route) stops its orders, and so does one whose
## cargo would sell at a loss (it keeps the cargo; restarting the route
## there sells anyway). A badly worn ship first goes for a service
## (Aging.auto_service), then carries on. Banned goods are neither bought nor sold; at a
## closed port the ship waits until it reopens.
static func process_orders(w: World) -> void:
	for s in w.fleet.ships:
		if not s.orders_active or s.status != Ship.Status.DOCKED or s.orders.size() < 2:
			continue
		if Aging.wants_auto_service(w, s) and Aging.auto_service(w, s):
			continue
		var stop: Dictionary = s.orders[s.order_index]
		if s.system != int(stop.system):
			_go(w, s, int(stop.system))
			continue
		var port := w.economy.market_at(s.system)
		if port and port.closed:
			s.note = "waiting: the port is closed"
			continue
		if not s.stop_handled:
			if (stop.get("sell_all", true) or stop.get("auto", false)) and not s.cargo.is_empty():
				var q := sale_quote(w, s)
				if q.income < q.cost - 0.5 and not s.allow_loss:
					s.orders_active = false
					var why := "price too low: the cargo would sell at a loss here (%s cr)" % Format.thousands(roundi(q.income - q.cost))
					s.note = "route stopped: " + why
					w.events.append({"type": "orders_stopped", "ship": s.id, "company": s.company, "reason": why})
					continue
				sell_all(w, s)
			s.allow_loss = false
			s.note = ""
			_load(w, s, stop)
			s.stop_handled = true
			s.wait_start = w.day
			if stop.get("service", false) and w.fleet.is_shipyard(s.system) and Aging.needs_service(w, s):
				if Aging.service(w, s).ok:
					continue  # in the yard; the route goes on when it is out
		elif stop.get("wait_full", false):
			_load(w, s, stop)
		var max_wait := int(cfg(w).get("wait_full_max_days", 28))
		if stop.get("wait_full", false) and not _full(w, s, stop) and w.day - s.wait_start < max_wait:
			s.note = "waiting for a full load (day %d of %d)" % [w.day - s.wait_start + 1, max_wait]
			continue
		s.order_index = (s.order_index + 1) % s.orders.size()
		s.stop_handled = false
		_go(w, s, int(s.orders[s.order_index].system))

static func _go(w: World, s: Ship, target: int) -> void:
	var r := w.depart(s, target)
	if not r.ok:
		s.orders_active = false
		s.note = "route stopped: " + r.error
		w.events.append({"type": "orders_stopped", "ship": s.id, "company": s.company, "reason": r.error})

static func _load(w: World, s: Ship, stop: Dictionary) -> void:
	if stop.get("auto", false) and "auto_trader" in s.modules:
		_auto_buy(w, s, int(s.orders[(s.order_index + 1) % s.orders.size()].system))
		return
	for b in stop.get("buy", []):
		var c := w.economy.index_of(b.commodity)
		if is_banned(w, s.system, c):
			s.note = "no cargo: %s are banned here" % _name(w, c)
			continue
		var amount := float(b.get("amount", 0))
		var want := free_space(w, s, c) if amount <= 0.0 else maxf(amount - s.cargo.get(c, 0.0), 0.0)
		if want >= 1.0:
			var r := buy(w, s, c, want)
			if not r.ok:
				s.note = "no cargo: %s (%s)" % [r.error.to_lower(), _name(w, c)]

## Loaded as far as this stop wants: no free space for anything it buys.
static func _full(w: World, s: Ship, stop: Dictionary) -> bool:
	if stop.get("auto", false):
		return true
	for b in stop.get("buy", []):
		var c := w.economy.index_of(b.commodity)
		if is_banned(w, s.system, c):
			continue
		var amount := float(b.get("amount", 0))
		if amount <= 0.0 and free_space(w, s, c) >= 1.0:
			return false
		if amount > 0.0 and s.cargo.get(c, 0.0) + 1.0 < amount:
			return false
	return true

## Auto-trader: for each cargo class aboard, the good with the best known
## margin (after the next stop's tariff) at the next stop, if any is
## positive; goods banned here or there are skipped.
static func _auto_buy(w: World, s: Ship, next_system: int) -> void:
	var known: Dictionary = w.companies[s.company].prices.get(next_system, {})
	var m := w.economy.market_at(s.system)
	if known.is_empty() or m == null:
		s.note = "no cargo match: no known prices at the next stop"
		return
	var best := {}  # cargo class -> [margin, commodity]
	for c in m.price.size():
		var cls := commodity_class(w, c)
		if free_space(w, s, c) < 1.0 or is_banned(w, s.system, c) or is_banned(w, next_system, c):
			continue
		var margin: float = known.price[c] * (1.0 - tariff(w, next_system, c, s.company)) - m.price[c]
		if margin > m.price[c] * 0.05 and margin > best.get(cls, [0.0])[0]:
			best[cls] = [margin, c]
	if best.is_empty():
		s.note = "no cargo match: nothing here sells for more at %s" % w.galaxy.systems[next_system].name
	for cls in best:
		var c: int = best[cls][1]
		buy(w, s, c, free_space(w, s, c))
