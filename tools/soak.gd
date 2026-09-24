extends SceneTree
## Economy soak run: builds the world and runs it for years with nobody
## trading, then reports how healthy the markets stayed.
##
##   godot --headless --path . --script res://tools/soak.gd [-- years=20 seed=1]
##   (or `make soak`)
##
## For every market and traded commodity it samples the price each week.
## Fails (exit 1) if more than economy.soak.max_clamp_share of all samples sit
## at the price clamps, or any stock ends above max_stock_ratio x its target
## (runaway stock). Also prints a per-commodity table and total supply vs
## demand, which is what you tune archetypes.json against.
##
## Events run as in a game. Every event in events.json must fire at least
## once and, at least once, visibly move the prices it acts on (5% or more
## in the expected direction while it runs; an embargo, a closed port or
## a new ban: any good concerned 5% either way);
## otherwise the run fails too.

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var content := Content.load_world_content("res://data/")
	var stars := Content.load_object("res://data/stars.json")
	var soak: Dictionary = content.balance.economy.get("soak", {})
	var years := int(args.get("years", soak.get("years", 20)))
	var seed_value := int(args.get("seed", content.balance.get("world_seed", 1)))
	var t0 := Time.get_ticks_msec()
	var w := World.create(seed_value, stars, content)
	w.warm_up()
	var e := w.economy
	var n := e.commodity_ids.size()

	# Potential supply vs demand at full rates.
	var supply := PackedFloat64Array()
	var demand := PackedFloat64Array()
	supply.resize(n)
	demand.resize(n)
	for m in e.markets:
		for c in n:
			supply[c] += m.supply_rate[c]
			demand[c] += m.demand_rate[c]

	var samples := PackedInt32Array()
	var at_min := PackedInt32Array()
	var at_max := PackedInt32Array()
	var ratio_sum := PackedFloat64Array()
	samples.resize(n)
	at_min.resize(n)
	at_max.resize(n)
	ratio_sum.resize(n)
	var lo := float(content.balance.economy.price_min)
	var hi := float(content.balance.economy.price_max)
	var days := years * Calendar.DAYS_PER_YEAR
	var fired := {}    # event kind -> times started
	var visible := {}  # event kind -> times it moved prices
	var watch := {}    # event id -> [kind, checks [[market, c, direction, start price]], seen]
	for d in days:
		# Prices from before today, the baseline for events starting today
		# (their effects reach the prices at once).
		var before := {}
		for m in e.markets:
			before[m] = m.price.duplicate()
		w.advance_day()
		for ev in w.world_events:
			if not watch.has(ev.id):
				fired[ev.kind] = fired.get(ev.kind, 0) + 1
				watch[ev.id] = [ev.kind, _checks(w, ev, before), false]
		if w.day % 7 == 0:
			for id in watch:
				var entry: Array = watch[id]
				if entry[2]:
					continue
				for chk in entry[1]:
					var r: float = chk[0].price[chk[1]] / chk[3]
					if (chk[2] > 0 and r >= 1.05) or (chk[2] < 0 and r <= 0.95) or (chk[2] == 0 and absf(r - 1.0) >= 0.05):
						entry[2] = true
						visible[entry[0]] = visible.get(entry[0], 0) + 1
						break
			# Finished events stop being watched.
			var running := {}
			for ev in w.world_events:
				running[ev.id] = true
			for id in watch.keys():
				if not running.has(id) and not watch[id][2]:
					watch[id][2] = true
		if w.day % 7 == 0:
			for m in e.markets:
				for c in n:
					if not m.is_traded(c):
						continue
					var r := m.price[c] / m.base_price[c]
					samples[c] += 1
					ratio_sum[c] += r
					if r <= lo * 1.001:
						at_min[c] += 1
					elif r >= hi * 0.999:
						at_max[c] += 1

	var total := 0
	var clamped := 0
	print("\n%-15s %9s %9s %6s %7s %7s" % ["commodity", "supply/d", "demand/d", "avg", "at min", "at max"])
	for c in n:
		total += samples[c]
		clamped += at_min[c] + at_max[c]
		var s := maxi(samples[c], 1)
		print("%-15s %9.0f %9.0f %6.2f %6.1f%% %6.1f%%" % [e.commodity_ids[c], supply[c], demand[c],
			ratio_sum[c] / s, 100.0 * at_min[c] / s, 100.0 * at_max[c] / s])
	var worst := 0.0
	var worst_at := ""
	for m in e.markets:
		for c in n:
			if m.is_traded(c) and m.stock[c] / m.target[c] > worst:
				worst = m.stock[c] / m.target[c]
				worst_at = "%s %s" % [w.galaxy.systems[m.system].name, e.commodity_ids[c]]
	var share := float(clamped) / maxi(total, 1)
	var max_share := float(soak.get("max_clamp_share", 0.1))
	var max_ratio := float(soak.get("max_stock_ratio", 4.0))
	print("\n%d years, seed %d, %d markets, %.1f s" % [years, seed_value, e.markets.size(),
		(Time.get_ticks_msec() - t0) / 1000.0])
	print("samples at a price clamp: %.1f%% (limit %.0f%%)" % [share * 100.0, max_share * 100.0])
	print("highest stock / target: %.2f at %s (limit %.1f)" % [worst, worst_at, max_ratio])
	var events_ok := true
	print("\n%-15s %6s %8s" % ["event", "fired", "visible"])
	for kind in content.events:
		print("%-15s %6d %8d" % [kind, fired.get(kind, 0), visible.get(kind, 0)])
		if visible.get(kind, 0) == 0:
			events_ok = false
	print("every event fired with a visible market effect: %s" % ("yes" if events_ok else "NO"))
	var ok := share <= max_share and worst <= max_ratio and events_ok
	print("SOAK %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

## What to watch for one event: each affected market's goods named in its
## supply/demand effects with the direction the price should go (+1 up,
## -1 down), or every traded good either way (0) for an embargo or a
## closed port, and banned goods either way.
func _checks(w: World, ev: WorldEvent, before: Dictionary) -> Array:
	var fx: Dictionary = WorldEvents.def_of(w, ev.kind).get("effects", {})
	var out := []
	for i in ev.systems:
		var m := w.economy.market_at(i)
		if m == null:
			continue
		for part in [["supply", -1], ["demand", 1]]:
			var mults: Dictionary = fx.get(part[0], {})
			for id in mults:
				var dir: int = part[1] * (1 if float(mults[id]) > 1.0 else -1)
				var goods := range(m.price.size()) if id == "*" else [w.economy.index_of(id)]
				for c in goods:
					if m.is_traded(c) and (id != "*" or m.supply_rate[c] > 0.0):
						out.append([m, c, dir, before[m][c]])
		for c in m.price.size():
			if m.is_traded(c) and (fx.get("isolated", false) or fx.get("closed", false) or m.banned[c]):
				out.append([m, c, 0, before[m][c]])
	return out
