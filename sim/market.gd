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
## weekly; player trades move prices at once through buy/sell).
func tick(days: int) -> void:
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
			stock[out_idx[k]] += out_amt[k] * days * rate
			used = maxf(used, rate)
		if used <= 0.0:
			continue
		for k in in_idx.size():
			stock[in_idx[k]] = maxf(stock[in_idx[k]] - in_amt[k] * days * used, 0.0)
	# Surplus above target slowly spoils or gets written off.
	var decay := 1.0 - pow(1.0 - float(_cfg.get("decay_per_day", 0.001)), days)
	for c in stock.size():
		if stock[c] > target[c]:
			stock[c] -= (stock[c] - target[c]) * decay
	refresh_prices()

func refresh_prices() -> void:
	for c in price.size():
		price[c] = price_at(c, stock[c])

## Unit price if the stock of `c` were `s`.
func price_at(c: int, s: float) -> float:
	if target[c] <= 0.0:
		return base_price[c]
	var ratio := pow(target[c] / maxf(s, target[c] * 0.01), float(_cfg.get("elasticity", 0.8)))
	return base_price[c] * clampf(ratio, float(_cfg.get("price_min", 0.25)), float(_cfg.get("price_max", 4.0)))

## Total cost of buying `qty` here: every unit is priced along the curve as
## the stock drops, so big lots cost more per unit.
func quote_buy(c: int, qty: float) -> float:
	qty = minf(qty, stock[c])
	return _integrate(c, stock[c] - qty, stock[c])

## Total income from selling `qty` here (each unit pushes the price down).
func quote_sell(c: int, qty: float) -> float:
	return _integrate(c, stock[c], stock[c] + qty)

## Buys up to `qty`; returns [amount bought, total cost].
func buy(c: int, qty: float) -> Array:
	qty = minf(qty, stock[c])
	var cost := quote_buy(c, qty)
	stock[c] -= qty
	price[c] = price_at(c, stock[c])
	return [qty, cost]

## Sells `qty`; returns the total income.
func sell(c: int, qty: float) -> float:
	var income := quote_sell(c, qty)
	stock[c] += qty
	price[c] = price_at(c, stock[c])
	return income

func record_week() -> void:
	var sample := PackedFloat32Array()
	sample.resize(price.size())
	for c in price.size():
		sample[c] = price[c]
	history.append(sample)
	if history.size() > int(_cfg.get("history_weeks", 104)):
		history.pop_front()

## Midpoint rule over stock levels [s0, s1].
func _integrate(c: int, s0: float, s1: float) -> float:
	var steps := 24
	var width := (s1 - s0) / steps
	var total := 0.0
	for i in steps:
		total += price_at(c, s0 + (i + 0.5) * width)
	return total * width
