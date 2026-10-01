class_name Market
extends RefCounted
## The market of one settlement: stock, target stock and price for every
## commodity (arrays indexed like Economy.commodity_ids), plus the recipes
## that run there each day.
##
## Recipes are archetype industries (inputs -> outputs) followed by needs
## (inputs only: the population and the industries' upkeep). A recipe runs at
## the fraction its scarcest input allows, and each output slows down when its
## warehouse overflows. Price = base x (target / stock)^elasticity, clamped.
##
## Company trades (players and, later, rivals) do not move stock or prices:
## a lot costs the listed price x tonnes. Companies can buy at most the stock
## each week (`taken` counts it; the weekly tick resets it). A sale at a
## profit adds `pull` to that good here, which draws more background traffic
## in (Economy.run_traffic), so a well-used route slowly evens out.

## Index into Galaxy.systems.
var system: int
## Market size for industry (from population + robots) and for human needs.
var size: float
var human_size: float
var base_price := PackedFloat64Array()
var stock := PackedFloat64Array()
## 0 = not traded here (only when transit_rate is 0 and nothing uses it).
var target := PackedFloat64Array()
var price := PackedFloat64Array()
## Per day, at full rate: what the recipes make and use.
var supply_rate := PackedFloat64Array()
var demand_rate := PackedFloat64Array()
## Each: {in_idx: PackedInt32Array, in_amt: PackedFloat64Array,
##        out_idx: PackedInt32Array, out_amt: PackedFloat64Array} (per day).
var recipes: Array[Dictionary] = []
## Weekly price samples, oldest first, at most `history_weeks` of them.
var history: Array[PackedFloat32Array] = []
## Running events (set by WorldEvents.apply_all): output and consumption
## multipliers per commodity, a closed port (no trade), an embargo (no
## background traffic), extra tariff points (a tariff hike) and a tariff
## multiplier (0 = waived by a trade agreement).
## `banned`: 1 per good the government bans (no background traffic in it).
var supply_mult := PackedFloat64Array()
var demand_mult := PackedFloat64Array()
var closed := false
var isolated := false
var tariff_add := 0.0
var tariff_mult := 1.0
var banned := PackedByteArray()
## Bought by companies this week, per good (resets each weekly tick).
var taken := PackedFloat64Array()
## Extra background traffic wanted per good (0 = none, 1 = twice as much),
## from companies' profitable sales here; fades week by week.
var pull := PackedFloat64Array()

var _cfg: Dictionary

func _init(system_index: int, bases: PackedFloat64Array, cfg: Dictionary) -> void:
	system = system_index
	base_price = bases
	_cfg = cfg
	var n := bases.size()
	# Packed arrays are values: resize each member directly, not via a loop copy.
	stock.resize(n)
	target.resize(n)
	price.resize(n)
	supply_rate.resize(n)
	demand_rate.resize(n)
	supply_mult.resize(n)
	supply_mult.fill(1.0)
	demand_mult.resize(n)
	demand_mult.fill(1.0)
	banned.resize(n)
	taken.resize(n)
	pull.resize(n)

## Adds a recipe; amounts are per day at full rate (already scaled by size).
func add_recipe(inputs: Dictionary, outputs: Dictionary) -> void:
	var r := {
		"in_idx": PackedInt32Array(inputs.keys()), "in_amt": PackedFloat64Array(inputs.values()),
		"out_idx": PackedInt32Array(outputs.keys()), "out_amt": PackedFloat64Array(outputs.values()),
	}
	recipes.append(r)
	for k in inputs:
		demand_rate[k] += inputs[k]
	for k in outputs:
		supply_rate[k] += outputs[k]

## Sets targets from the recipes and starts every good at its target (so at
## base price). Every market keeps a small transit stock of every good, sized
## by `transit_rate`, so traders can carry goods through it.
func settle() -> void:
	var cover := float(_cfg.get("cover_days", 30.0))
	var transit := float(_cfg.get("transit_rate", 0.0)) * size * float(_cfg.get("volume_scale", 1.0))
	for c in target.size():
		var flow := maxf(maxf(demand_rate[c], supply_rate[c] * 0.5), transit)
		if flow > 0.0:
			target[c] = cover * maxf(flow, 1.0)
		stock[c] = target[c]
	refresh_prices()

func is_traded(c: int) -> bool:
	return target[c] > 0.0

## `days` of production and consumption in one step (the economy updates
## weekly). Companies may buy the new stock again, and the pull fades.
func tick(days: int) -> void:
	taken.fill(0.0)
	var keep := pow(1.0 - float(_cfg.get("traffic", {}).get("pull_decay_per_day", 0.0)), days)
	for c in pull.size():
		pull[c] *= keep
	var start := float(_cfg.get("overstock_start", 1.0))
	var stop := float(_cfg.get("overstock_stop", 2.0))
	for r in recipes:
		var ratio := 1.0
		var in_idx: PackedInt32Array = r.in_idx
		var in_amt: PackedFloat64Array = r.in_amt
		var out_idx: PackedInt32Array = r.out_idx
		var out_amt: PackedFloat64Array = r.out_amt
		for k in in_idx.size():
			ratio = minf(ratio, stock[in_idx[k]] / (in_amt[k] * days))
		# Each output slows down on its own as its warehouse fills; inputs are
		# used for the busiest output.
		var used := 0.0 if out_idx.size() > 0 else ratio
		for k in out_idx.size():
			var fill := stock[out_idx[k]] / target[out_idx[k]]
			var rate := ratio * clampf((stop - fill) / (stop - start), 0.0, 1.0)
			stock[out_idx[k]] += out_amt[k] * days * rate * supply_mult[out_idx[k]]
			used = maxf(used, rate)
		if used <= 0.0:
			continue
		for k in in_idx.size():
			stock[in_idx[k]] = maxf(stock[in_idx[k]] - in_amt[k] * days * used, 0.0)
	# Events wanting more than the recipes use (a war wants weapons). Less
	# demand (zealots shun luxuries) lowers the wanted stock in price_at.
	var cover := float(_cfg.get("cover_days", 30.0))
	for c in stock.size():
		if demand_mult[c] > 1.0:
			var extra := (demand_mult[c] - 1.0) * maxf(demand_rate[c], target[c] / cover) * days
			stock[c] = maxf(stock[c] - extra, 0.0)
	# Surplus above target slowly spoils or gets written off.
	var decay := 1.0 - pow(1.0 - float(_cfg.get("decay_per_day", 0.001)), days)
	for c in stock.size():
		if stock[c] > target[c]:
			stock[c] -= (stock[c] - target[c]) * decay
	refresh_prices()

func refresh_prices() -> void:
	for c in price.size():
		price[c] = price_at(c, stock[c])

## Unit price if the stock of `c` were `s`. An event cutting demand
## (demand_mult < 1) cuts the wanted stock with it.
func price_at(c: int, s: float) -> float:
	if target[c] <= 0.0:
		return base_price[c]
	var wanted := target[c] * minf(demand_mult[c], 1.0)
	var ratio := pow(wanted / maxf(s, target[c] * 0.01), float(_cfg.get("elasticity", 0.8)))
	return base_price[c] * clampf(ratio, float(_cfg.get("price_min", 0.25)), float(_cfg.get("price_max", 4.0)))

## What companies can still buy of `c` this week.
func available(c: int) -> float:
	return maxf(stock[c] - taken[c], 0.0)

## Total cost of buying `qty` here (up to what is available) at the
## listed price.
func quote_buy(c: int, qty: float) -> float:
	return minf(qty, available(c)) * price[c]

## Total income from selling `qty` here at the listed price.
func quote_sell(c: int, qty: float) -> float:
	return qty * price[c]

## Buys up to `qty` (what is available); returns [amount bought, total
## cost]. The stock and price stay as they are.
func buy(c: int, qty: float) -> Array:
	qty = minf(qty, available(c))
	taken[c] += qty
	return [qty, qty * price[c]]

## Sells `qty`; returns the total income. The stock and price stay.
func sell(c: int, qty: float) -> float:
	return qty * price[c]

## A company sold `qty` of `c` here at a profit: background traders bring
## a little more of it (pull grows with the lot against the target stock).
func add_pull(c: int, qty: float) -> void:
	if target[c] <= 0.0:
		return
	var t: Dictionary = _cfg.get("traffic", {})
	pull[c] = minf(pull[c] + float(t.get("sale_pull", 0.0)) * qty / target[c], float(t.get("pull_max", 0.0)))

func record_week() -> void:
	var sample := PackedFloat32Array()
	sample.resize(price.size())
	for c in price.size():
		sample[c] = price[c]
	history.append(sample)
	if history.size() > int(_cfg.get("history_weeks", 104)):
		history.pop_front()

