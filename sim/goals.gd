class_name Goals
## Victory goals and bankruptcy (static functions on a World).
##
## A company plays in the sandbox (goal "") or toward one goal from
## balance.json "goals": "value" (company value at least `target`) or
## "prince", the Merchant Prince (patron of at least `patrons` systems).
## Checked on the first of every month, like bankruptcy: a month that ends
## with cash below zero and the loan maxed out is a month in the red, and
## `bankruptcy_months` of them in a row bankrupt the house.

static func defs(w: World) -> Dictionary:
	return w.content.balance.get("goals", {})

## Cash minus debt, plus what the ships would sell for and what their cargo
## cost.
static func company_value(w: World, company_id: int) -> float:
	var c := w.companies[company_id]
	var total := c.cash - c.loan
	for s in w.ships_of(company_id):
		total += w.fleet.sale_value(s)
		for k in s.cargo_cost:
			total += s.cargo_cost[k]
	return total

static func patron_count(w: World, company_id: int) -> int:
	var n := 0
	for i in w.galaxy.size():
		if Influence.is_patron(w, company_id, i):
			n += 1
	return n

## Where a company stands on its goal: {goal, name, current, target, done};
## goal "" = sandbox.
static func progress(w: World, company_id: int) -> Dictionary:
	var id := w.companies[company_id].goal
	var d: Dictionary = defs(w).get(id, {})
	match id:
		"value":
			var target := float(d.get("target", 0))
			var now := company_value(w, company_id)
			return {"goal": id, "name": d.get("name", id), "current": now, "target": target, "done": now >= target}
		"prince":
			var need := int(d.get("patrons", 0))
			var have := patron_count(w, company_id)
			return {"goal": id, "name": d.get("name", id), "current": have, "target": need, "done": have >= need}
	return {"goal": "", "name": "Sandbox", "current": 0, "target": 0, "done": false}

## Picks a goal ("" = sandbox); progress starts over.
static func set_goal(w: World, company_id: int, id: String) -> Dictionary:
	if id != "" and not defs(w).has(id):
		return {"ok": false, "error": "No such goal"}
	var c := w.companies[company_id]
	c.goal = id
	c.goal_day = -1
	w.events.append({"type": "goal_set", "company": company_id})
	return {"ok": true}

## First of the month (after the monthly costs): bankruptcy and goals.
static func monthly(w: World) -> void:
	var limit := int(w.content.balance.get("bankruptcy_months", 3))
	for c in w.companies:
		if c.bankrupt:
			continue
		if c.cash < 0.0 and c.loan >= c.loan_max - 0.5:
			c.months_in_red += 1
			if c.months_in_red >= limit:
				_go_bankrupt(w, c)
				continue
			w.events.append({"type": "bankruptcy_warning", "company": c.id, "months": c.months_in_red,
				"limit": limit})
		else:
			c.months_in_red = 0
		if c.goal != "" and c.goal_day < 0 and progress(w, c.id).done:
			c.goal_day = w.day
			WorldEvents.post_news(w, "%s reaches its goal: %s" % [c.name, progress(w, c.id).name], [], "goal", true)
			w.events.append({"type": "goal_reached", "company": c.id})

## The house folds: its ships stop their routes.
static func _go_bankrupt(w: World, c: Company) -> void:
	c.bankrupt = true
	for s in w.ships_of(c.id):
		s.orders_active = false
	WorldEvents.post_news(w, "%s is bankrupt: its creditors seize the books" % c.name, [], "bankrupt", true)
	w.events.append({"type": "bankrupt", "company": c.id})
