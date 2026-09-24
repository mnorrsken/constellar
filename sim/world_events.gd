class_name WorldEvents
## The event engine (static functions on a World, like Trading).
##
## Once a month every event in data/events.json gets its `chance_per_month`
## to happen somewhere: the places that meet its `where` conditions are
## weighted (by war-likeness, instability, size or lawlessness) and one is
## picked. An event's lasting effects (supply/demand multipliers, closed
## port, embargo, tariffs waived, lane danger) hold while it runs and are
## rebuilt from all running events by apply_all(); one-off effects
## (government change, stability, population) happen when it starts.
## Every start and end posts a headline to the news.

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("events", {})

static func def_of(w: World, kind: String) -> Dictionary:
	return w.content.get("events", {}).get(kind, {})

# --- the monthly roll -----------------------------------------------------------------

## First of the month: stability drifts back toward each government's
## base, then every event rolls its chance.
static func monthly(w: World) -> void:
	var drift := float(cfg(w).get("stability_drift", 0.03))
	for s in w.galaxy.systems:
		var st := s.settlement
		if st:
			var base := float(w.content.governments.get(st.government, {}).get("stability", 0.6))
			st.stability += (base - st.stability) * drift
	for kind in w.content.get("events", {}):
		var d: Dictionary = w.content.events[kind]
		if w.events_rng.randf() >= float(d.get("chance_per_month", 0.0)):
			continue
		var options := candidates(w, kind)
		if options.is_empty():
			continue
		var weights := {}
		for k in options.size():
			weights[k] = options[k][2]
		var pick: Array = options[Contracts._weighted_with(w.events_rng, weights)]
		start(w, kind, pick[0], pick[1])

## Daily: events past their end day stop.
static func daily(w: World) -> void:
	var ended := false
	for ev in w.world_events.duplicate():
		if ev.end_day <= w.day:
			w.world_events.erase(ev)
			var d := def_of(w, ev.kind)
			post_news(w, _fill(w, d.get("end_headline", ""), ev.systems), ev.systems, ev.kind, false)
			ended = true
	if ended:
		apply_all(w)

## Where an event could happen now: [[systems], on_lane, weight], weight > 0.
static func candidates(w: World, kind: String) -> Array:
	var d := def_of(w, kind)
	var out := []
	match d.get("scope", "system"):
		"system":
			for s in w.galaxy.systems:
				if _fits(w, d, s.index):
					out.append([[s.index], false, _weight(w, d, [s.index])])
		"pair":
			for lane in w.galaxy.lanes:
				if _fits(w, d, lane.a) and _fits(w, d, lane.b):
					out.append([[lane.a, lane.b], false, _weight(w, d, [lane.a, lane.b])])
		"lane":
			for lane in w.galaxy.lanes:
				if _lane_fits(w, d, lane):
					out.append([[lane.a, lane.b], true, _weight(w, d, [lane.a, lane.b])])
	var free := []
	for o in out:
		if o[2] > 0.0 and not _busy(w, kind, o[0]):
			free.append(o)
	return free

## A system meets the `where` conditions (and has room for one more event).
static func _fits(w: World, d: Dictionary, i: int) -> bool:
	var st := w.galaxy.systems[i].settlement
	var where: Dictionary = d.get("where", {})
	if st == null or w.economy.market_at(i) == null:
		return false
	if st.population < int(where.get("min_population", 0)):
		return false
	if where.has("archetypes") and not (st.archetype in where.archetypes):
		return false
	if st.government in where.get("not_governments", []):
		return false
	if st.stability > float(where.get("max_stability", 1.0)):
		return false
	if where.has("star_class"):
		var any := false
		for star in w.galaxy.systems[i].stars:
			if str(star.get("class", "")) == where.star_class:
				any = true
		if not any:
			return false
	return active_at(w, i).size() < int(cfg(w).get("max_per_system", 2))

static func _lane_fits(w: World, d: Dictionary, lane: Lane) -> bool:
	if d.get("where", {}).get("market", false):
		return w.economy.market_at(lane.a) != null or w.economy.market_at(lane.b) != null
	return true

## The same event already runs there (or on that lane).
static func _busy(w: World, kind: String, systems: Array) -> bool:
	for ev in w.world_events:
		if ev.kind == kind and ev.systems.any(func(s): return s in systems):
			return true
	return false

static func _weight(w: World, d: Dictionary, systems: Array) -> float:
	match d.get("weight", ""):
		"war":
			var war := 0.0
			var stab := 0.0
			for i in systems:
				var st := w.galaxy.systems[i].settlement
				war += float(w.content.governments.get(st.government, {}).get("war", 1.0))
				stab += st.stability
			return war * maxf(1.3 - stab / systems.size(), 0.0)
		"instability":
			return 1.0 - w.galaxy.systems[systems[0]].settlement.stability + 0.05
		"size":
			var size := 0.0
			for i in systems:
				size += w.economy.market_at(i).human_size
			return size
		"lawless":
			var stab := 0.0
			for i in systems:
				var st := w.galaxy.systems[i].settlement
				stab += st.stability if st else 0.3
			return 1.5 - stab / systems.size()
	return 1.0

# --- starting and ending --------------------------------------------------------------

## Starts an event now (the monthly roll uses this; tests force events with
## it). Returns the running event.
static func start(w: World, kind: String, systems: Array, on_lane := false) -> WorldEvent:
	var d := def_of(w, kind)
	var ev := WorldEvent.new()
	ev.id = w.next_event_id
	w.next_event_id += 1
	ev.kind = kind
	ev.systems.assign(systems)
	ev.on_lane = on_lane
	ev.start_day = w.day
	var days: Array = d.get("days", [30, 30])
	ev.end_day = w.day + w.events_rng.randi_range(int(days[0]), int(days[1]))
	var fx: Dictionary = d.get("effects", {})
	for i in systems:
		var st := w.galaxy.systems[i].settlement
		if st == null:
			continue
		if fx.has("government"):
			st.government = fx.government
			st.stability = float(w.content.governments.get(st.government, {}).get("stability", 0.5))
		st.stability = clampf(st.stability + float(fx.get("stability", 0.0)), 0.02, 0.98)
		st.population = roundi(st.population * float(fx.get("population", 1.0)))
	ev.headline = _fill(w, d.get("headline", d.get("name", kind)), systems)
	w.world_events.append(ev)
	post_news(w, ev.headline, systems, kind, true)
	apply_all(w)
	return ev

## Rebuilds every market's event state and the lane dangers from the
## running events.
static func apply_all(w: World) -> void:
	for m in w.economy.markets:
		m.supply_mult.fill(1.0)
		m.demand_mult.fill(1.0)
		m.closed = false
		m.isolated = false
		m.tariff_mult = 1.0
		for c in m.banned.size():
			m.banned[c] = 1 if Trading.is_banned(w, m.system, c) else 0
	w.danger = Danger.base_map(w)
	var cap := float(Danger.cfg(w).get("max", 0.5))
	for ev in w.world_events:
		var fx: Dictionary = def_of(w, ev.kind).get("effects", {})
		for i in ev.systems:
			var m := w.economy.market_at(i)
			if m == null:
				continue
			_multiply(w, m.supply_mult, fx.get("supply", {}))
			_multiply(w, m.demand_mult, fx.get("demand", {}))
			m.closed = m.closed or fx.get("closed", false)
			m.isolated = m.isolated or fx.get("isolated", false)
			if fx.get("tariffs_waived", false):
				m.tariff_mult = 0.0
		if ev.systems.size() == 2 and fx.has("lane_danger"):
			var key := Danger.key(ev.systems[0], ev.systems[1])
			w.danger[key] = minf(w.danger.get(key, 0.0) + float(fx.lane_danger), cap)
		if fx.has("zone_danger"):
			for i in ev.systems:
				for lane in w.galaxy.lanes_of(i):
					var key := Danger.key(lane.a, lane.b)
					w.danger[key] = minf(w.danger.get(key, 0.0) + float(fx.zone_danger), cap)
	for m in w.economy.markets:
		m.refresh_prices()

static func _multiply(w: World, into: PackedFloat64Array, by: Dictionary) -> void:
	for id in by:
		if id == "*":
			for c in into.size():
				into[c] *= float(by[id])
		else:
			var c := w.economy.index_of(id)
			if c >= 0:
				into[c] *= float(by[id])

# --- queries and news -----------------------------------------------------------------

## Running events touching a system.
static func active_at(w: World, i: int) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for ev in w.world_events:
		if i in ev.systems:
			out.append(ev)
	return out

## A place's name for headlines: the settlement, else the star system.
static func place_name(w: World, i: int) -> String:
	var s := w.galaxy.systems[i]
	return s.settlement.name if s.settlement else s.name

static func post_news(w: World, text: String, systems: Array, kind: String, starting: bool) -> void:
	var item := {"day": w.day, "text": text, "systems": systems.duplicate(), "kind": kind, "start": starting}
	w.news.append(item)
	var most := int(cfg(w).get("news_max", 300))
	if w.news.size() > most:
		w.news = w.news.slice(w.news.size() - most)
	w.events.append({"type": "news", "item": item})

static func _fill(w: World, template: String, systems: Array) -> String:
	var text := template.replace("{a}", place_name(w, systems[0]))
	if systems.size() > 1:
		text = text.replace("{b}", place_name(w, systems[1]))
	return text
