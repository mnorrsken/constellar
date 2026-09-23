class_name Economy
extends RefCounted
## All markets and the background traffic between them.
##
## Every settlement gets a Market built from its archetype's industries and
## needs (archetypes.json) plus population needs (balance.json), scaled by
## market size and balance volume_scale (so stocks run to thousands of
## tonnes). Markets update once every update_days (a week): production,
## consumption, then abstract NPC traders move goods between markets up to
## max_hops lanes apart, from cheap to dear, when the price gap beats the
## friction and distance costs. That keeps prices from drifting to extremes;
## real rival companies will take over part of this job later.

## Commodity ids in index order (commodities.json order).
var commodity_ids: PackedStringArray
var markets: Array[Market] = []
## system index -> Market
var by_system: Dictionary = {}
## [market a, market b, route length in ly] for every pair of markets up to
## traffic.max_hops lanes apart (through any systems), shortest route.
var links: Array = []

var _cfg: Dictionary

static func build(galaxy: Galaxy, content: Dictionary) -> Economy:
	var e := Economy.new()
	e._cfg = content.balance.get("economy", {})
	e.commodity_ids = PackedStringArray(content.commodities.keys())
	var bases := PackedFloat64Array()
	for id in e.commodity_ids:
		bases.append(float(content.commodities[id].base_price))
	for s in galaxy.systems:
		if s.settlement == null:
			continue
		var m := Market.new(s.index, bases, e._cfg)
		e._add_recipes(m, s.settlement, content.archetypes[s.settlement.archetype])
		m.settle()
		e.markets.append(m)
		e.by_system[s.index] = m
	e._build_links(galaxy, int(e._cfg.get("traffic", {}).get("max_hops", 1)))
	return e

func _build_links(galaxy: Galaxy, max_hops: int) -> void:
	var best := {}  # Vector2i(a, b) with a < b -> shortest length
	for m in markets:
		# Shortest distance to every system within max_hops lanes.
		var dist := {m.system: 0.0}
		var frontier := [m.system]
		for hop in max_hops:
			var next := []
			for u in frontier:
				for lane in galaxy.lanes_of(u):
					var v: int = lane.other(u)
					var d: float = dist[u] + lane.length
					if d < dist.get(v, INF):
						dist[v] = d
						next.append(v)
			frontier = next
		for v in dist:
			if v != m.system and by_system.has(v):
				var key := Vector2i(mini(m.system, v), maxi(m.system, v))
				best[key] = minf(best.get(key, INF), dist[v])
	var keys := best.keys()
	keys.sort()
	for key in keys:
		links.append([by_system[key.x], by_system[key.y], best[key]])

func index_of(commodity_id: String) -> int:
	return commodity_ids.find(commodity_id)

func market_at(system_index: int) -> Market:
	return by_system.get(system_index)

## Called every game day; the markets move once every update_days (the last
## day of each week): production and consumption, traffic, price history.
func tick_day(day: int) -> void:
	var every := int(_cfg.get("update_days", 7))
	if (day + 1) % every != 0:
		return
	for m in markets:
		m.tick(every)
	run_traffic()
	for m in markets:
		m.record_week()

## Moves goods along market links toward higher prices.
func run_traffic() -> void:
	var t: Dictionary = _cfg.get("traffic", {})
	var friction := float(t.get("friction", 0.12))
	var per_ly := float(t.get("per_ly", 0.01))
	var capacity := float(t.get("capacity", 60.0)) * float(_cfg.get("volume_scale", 1.0))
	var max_share := float(t.get("max_share", 0.25))
	var full := float(_cfg.get("overstock_start", 1.0))
	for link in links:
		var ends := [[link[0], link[1]], [link[1], link[0]]]
		var cost := 1.0 + friction + per_ly * float(link[2])
		for pair in ends:
			var from: Market = pair[0]
			var to: Market = pair[1]
			var cap := capacity * minf(from.size, to.size)
			for c in commodity_ids.size():
				if not to.is_traded(c) or from.stock[c] <= 0.0:
					continue
				var gap := to.price[c] / from.price[c] - cost
				if gap <= 0.0:
					continue
				var amount := minf(cap * gap, from.stock[c] * max_share)
				amount = minf(amount, maxf(to.target[c] * full - to.stock[c], 0.0))
				if amount <= 0.0:
					continue
				from.stock[c] -= amount
				to.stock[c] += amount
		link[0].refresh_prices()
		link[1].refresh_prices()

## Market size from a head count: log10(n) - offset, clamped.
func size_of(count: float, minimum: float) -> float:
	var offset := float(_cfg.get("size_log_offset", 2.0))
	return clampf(log(maxf(count, 1.0)) / log(10.0) - offset, minimum, float(_cfg.get("size_max", 8.0)))

func _add_recipes(m: Market, st: Settlement, arch: Dictionary) -> void:
	m.size = size_of(st.population + st.robots, float(_cfg.get("size_min", 0.5)))
	m.human_size = size_of(st.population, 0.0)
	for r in arch.get("industries", []):
		m.add_recipe(_scaled(r.get("in", {}), m.size), _scaled(r.get("out", {}), m.size))
	var needs: Dictionary = arch.get("needs", {})
	if needs.has("*"):
		var every := {}
		for id in commodity_ids:
			every[id] = needs["*"]
		needs = every
	if not needs.is_empty():
		m.add_recipe(_scaled(needs, m.size), {})
	if m.human_size > 0.0:
		m.add_recipe(_scaled(_cfg.get("population_needs", {}), m.human_size), {})

## {commodity id: per-size rate} -> {commodity index: tonnes per day}
func _scaled(rates: Dictionary, factor: float) -> Dictionary:
	var out := {}
	for id in rates:
		var c := index_of(id)
		if c < 0:
			push_warning("[Economy] unknown commodity '%s'" % id)
			continue
		out[c] = float(rates[id]) * factor * float(_cfg.get("volume_scale", 1.0))
	return out
