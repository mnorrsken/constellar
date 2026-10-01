class_name Influence
## Influence, the Foundation layer (static functions on a World, like
## Trading). Every company has a score 0..100 per system. It grows with the
## value the company brings there: goods sold (worth more when the market
## is short of them: price against base price) and contract rewards
## (freight, passengers, mail) delivered there. Points are scaled down by
## the market's size, so a small colony is easier to win than a core
## world, and every score decays a little each month. What a prestige hull
## (trait "influence_mult") brings counts for more.
##
## Tiers (balance.json "influence") unlock actions, all World commands:
## - post: open a trading post (live prices, lower docking fees there);
## - concession: sign a trade concession (lower tariffs, first pick of the
##   contract board); lost again if the score falls below "concession_keep";
## - patron: the lobby. Veto a running "vetoable" event there (a tariff
##   hike), broker peace in a "brokerable" war between two systems that
##   both have the company as patron. Events with a "patron_weight" (wars,
##   coups) are less likely where any company is patron.

enum Tier { NONE, POST, CONCESSION, PATRON }

const TIER_NAMES := ["no standing", "trading post", "trade concession", "patron"]

static func cfg(w: World) -> Dictionary:
	return w.content.balance.get("influence", {})

## The score needed for a tier.
static func threshold(w: World, t: int) -> float:
	match t:
		Tier.POST:
			return float(cfg(w).get("post", 25))
		Tier.CONCESSION:
			return float(cfg(w).get("concession", 50))
		Tier.PATRON:
			return float(cfg(w).get("patron", 75))
	return 0.0

static func of(w: World, company_id: int, i: int) -> float:
	var inf := w.companies[company_id].influence
	return inf[i] if i < inf.size() else 0.0

static func tier(w: World, company_id: int, i: int) -> int:
	var v := of(w, company_id, i)
	for t in [Tier.PATRON, Tier.CONCESSION, Tier.POST]:
		if v >= threshold(w, t):
			return t
	return Tier.NONE

static func is_patron(w: World, company_id: int, i: int) -> bool:
	return tier(w, company_id, i) == Tier.PATRON

## The company that is patron of a system (the highest score), or -1.
static func patron_of(w: World, i: int) -> int:
	var best := -1
	for c in w.companies:
		if is_patron(w, c.id, i) and (best < 0 or of(w, c.id, i) > of(w, best, i)):
			best = c.id
	return best

static func has_post(w: World, company_id: int, i: int) -> bool:
	return w.companies[company_id].posts.has(i)

static func has_concession(w: World, company_id: int, i: int) -> bool:
	return w.companies[company_id].concessions.has(i)

## Any company holds a concession at the system.
static func conceded(w: World, i: int) -> bool:
	return w.companies.any(func(c): return c.concessions.has(i))

# --- gaining and losing ------------------------------------------------------------

## The company brought `value` credits' worth to system i: goods sold
## (shortage = price / base price when sold) or a contract delivered (1).
static func gain(w: World, company_id: int, i: int, value: float, shortage := 1.0) -> void:
	var m := w.economy.market_at(i)
	if m == null or value <= 0.0:
		return
	var k := cfg(w)
	var size := maxf(m.size, float(k.get("size_min", 1.0)))
	var weight := clampf(shortage, 0.5, float(k.get("shortage_max", 3.0)))
	_store(w, company_id, i, of(w, company_id, i) + value * weight / (float(k.get("credits_per_point", 20000)) * size))

## First of the month: every score decays.
static func monthly(w: World) -> void:
	var keep := 1.0 - float(cfg(w).get("decay_per_month", 0.03))
	for c in w.companies:
		for i in c.influence.size():
			if c.influence[i] > 0.0:
				_store(w, c.id, i, c.influence[i] * keep)
	w.events.append({"type": "influence"})

## Sets a score. Reaching a tier for the first time is an event; a
## concession is lost when the score falls below "concession_keep".
static func _store(w: World, company_id: int, i: int, value: float) -> void:
	var c := w.companies[company_id]
	c.influence[i] = clampf(value, 0.0, float(cfg(w).get("max", 100)))
	var now := tier(w, company_id, i)
	if now > int(c.tiers_reached.get(i, Tier.NONE)):
		c.tiers_reached[i] = now
		w.events.append({"type": "influence_tier", "company": company_id, "system": i, "tier": now})
	if c.concessions.has(i) and c.influence[i] < float(cfg(w).get("concession_keep", 40)):
		c.concessions.erase(i)
		w.events.append({"type": "concession_lost", "company": company_id, "system": i})

# --- what the tiers give -------------------------------------------------------------

## Docking fee multiplier: lower at the company's trading posts.
static func docking_factor(w: World, company_id: int, i: int) -> float:
	return 1.0 - float(cfg(w).get("post_docking_discount", 0.5)) if has_post(w, company_id, i) else 1.0

## Tariff multiplier: lower under the company's trade concession.
static func tariff_factor(w: World, company_id: int, i: int) -> float:
	return float(cfg(w).get("concession_tariff_share", 0.5)) if has_concession(w, company_id, i) else 1.0

## Weekly (when markets move): live prices at every trading post.
static func observe_posts(w: World) -> void:
	for c in w.companies:
		for i in c.posts:
			Trading.observe(w, c.id, i)

# --- commands --------------------------------------------------------------------------

static func open_post(w: World, company_id: int, i: int) -> Dictionary:
	var c := w.companies[company_id]
	if w.economy.market_at(i) == null:
		return {"ok": false, "error": "No market here"}
	if c.posts.has(i):
		return {"ok": false, "error": "You already have a trading post here"}
	var need := _needs(w, company_id, i, Tier.POST)
	if need != "":
		return {"ok": false, "error": need}
	var cost := float(cfg(w).get("post_cost", 150000))
	if c.cash < cost:
		return {"ok": false, "error": "A trading post costs %s cr" % Format.thousands(roundi(cost))}
	c.book("influence", -cost, w.month())
	c.posts[i] = true
	Trading.observe(w, company_id, i)
	w.events.append({"type": "post_opened", "company": company_id, "system": i})
	return {"ok": true}

static func sign_concession(w: World, company_id: int, i: int) -> Dictionary:
	var c := w.companies[company_id]
	if w.economy.market_at(i) == null:
		return {"ok": false, "error": "No market here"}
	if c.concessions.has(i):
		return {"ok": false, "error": "You already hold the concession here"}
	var need := _needs(w, company_id, i, Tier.CONCESSION)
	if need != "":
		return {"ok": false, "error": need}
	var cost := float(cfg(w).get("concession_cost", 400000))
	if c.cash < cost:
		return {"ok": false, "error": "The concession costs %s cr" % Format.thousands(roundi(cost))}
	c.book("influence", -cost, w.month())
	c.concessions[i] = true
	w.events.append({"type": "concession_signed", "company": company_id, "system": i})
	return {"ok": true}

## The patron's lobby blocks a running vetoable event (a tariff hike).
static func veto(w: World, company_id: int, ev: WorldEvent) -> Dictionary:
	if not WorldEvents.def_of(w, ev.kind).get("vetoable", false):
		return {"ok": false, "error": "That can't be vetoed"}
	for i in ev.systems:
		if not is_patron(w, company_id, i):
			return {"ok": false, "error": "Only the patron of %s can veto it" % WorldEvents.place_name(w, i)}
	var cost := float(cfg(w).get("veto_cost", 15))
	for i in ev.systems:
		_store(w, company_id, i, of(w, company_id, i) - cost)
	var what: String = WorldEvents.def_of(w, ev.kind).get("name", ev.kind).to_lower()
	WorldEvents.stop(w, ev, "%s's lobby blocks the %s at %s" % [w.companies[company_id].name, what,
		WorldEvents.place_name(w, ev.systems[0])])
	w.events.append({"type": "vetoed", "company": company_id, "system": ev.systems[0]})
	return {"ok": true}

## A war between two systems that both have the company as patron ends.
static func broker_peace(w: World, company_id: int, ev: WorldEvent) -> Dictionary:
	if not WorldEvents.def_of(w, ev.kind).get("brokerable", false):
		return {"ok": false, "error": "There is no war to end"}
	for i in ev.systems:
		if not is_patron(w, company_id, i):
			return {"ok": false, "error": "Both sides must depend on you: you are not patron of %s" %
				WorldEvents.place_name(w, i)}
	var cost := float(cfg(w).get("peace_cost", 20))
	for i in ev.systems:
		_store(w, company_id, i, of(w, company_id, i) - cost)
	WorldEvents.stop(w, ev, "%s brokers peace between %s and %s" % [w.companies[company_id].name,
		WorldEvents.place_name(w, ev.systems[0]), WorldEvents.place_name(w, ev.systems[1])])
	w.events.append({"type": "peace", "company": company_id, "system": ev.systems[0]})
	return {"ok": true}

## Why the company can't use a tier's action here yet ("" = it can).
static func _needs(w: World, company_id: int, i: int, t: int) -> String:
	if tier(w, company_id, i) >= t:
		return ""
	return "Needs influence %d here (you have %d)" % [roundi(threshold(w, t)), floori(of(w, company_id, i))]
