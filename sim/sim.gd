extends Node
## Sim — owns the game world and the day clock.
##
## The simulation is pure data + logic, separate from rendering. The world
## itself lives in plain `RefCounted` classes (plan §2) so it is headlessly
## testable; this autoload only wraps it, advances it one game day per tick
## and emits `Events`.

## The player's company id.
const PLAYER := 0

## Game speeds in days per second; index 0 = paused.
const SPEEDS := [0, 1, 2, 4, 8]

var world: World
## Shortcut to world.galaxy.
var galaxy: Galaxy
## Index into SPEEDS.
var speed := 1
## Pause when a player ship needs orders (arrived, out of the yard). Will be
## a menu option.
var auto_pause := true
## Player ships that arrived or left the yard and have had no new orders
## yet, oldest first.
var waiting: Array[int] = []
## Speed to resume at after an auto-pause.
var _resume_speed := 1
## Money the F2 cheat adds.
const CHEAT_CASH := 10000000.0

var _accumulator := 0.0

func _ready() -> void:
	var seed_value := int(Defs.world_content.balance.get("world_seed", 1))
	world = World.create(seed_value, Defs.stars, Defs.world_content)
	world.warm_up()
	galaxy = world.galaxy
	print("[Sim] world seed %d: %d inhabited systems, start at %s, %s" % [
		seed_value, world.settlements().size(),
		galaxy.systems[world.start_system].name if world.start_system >= 0 else "?",
		world.date_string()])

func set_speed(index: int) -> void:
	speed = clampi(index, 0, SPEEDS.size() - 1)
	if speed > 0:
		_resume_speed = speed
	_accumulator = 0.0
	Events.speed_changed.emit(speed)

## Space bar: pause, or resume at 1x.
func toggle_pause() -> void:
	set_speed(1 if speed == 0 else 0)

func _process(delta: float) -> void:
	if world == null or speed == 0:
		return
	_accumulator += delta * SPEEDS[speed]
	var steps := 0
	while _accumulator >= 1.0 and steps < 8:
		_accumulator -= 1.0
		steps += 1
		world.advance_day()
		Events.day_passed.emit(world.day)
		_flush_events()

## How far into the current day the clock is (0..1), for smooth drawing.
func day_fraction() -> float:
	return clampf(_accumulator, 0.0, 1.0) if speed > 0 else 0.0

# --- player commands (company 0) ---------------------------------------------------

func buy_ship(hull_id: String, system_index: int) -> Dictionary:
	return _run(world.buy_ship(PLAYER, hull_id, system_index))

func sell_ship(ship_id: int) -> Dictionary:
	return _run(world.sell_ship(PLAYER, ship_id))

func refit_ship(ship_id: int, modules: Array) -> Dictionary:
	return _run(world.refit_ship(PLAYER, ship_id, modules))

## Sends a ship; the game resumes (at the speed before the pause) unless
## other ships still wait for orders — then it points at the next one.
func send_ship(ship_id: int, target_system: int) -> Dictionary:
	var r := _run(world.send_ship(PLAYER, ship_id, target_system))
	if r.ok:
		_given_orders(ship_id)
	return r

## A waiting ship got orders: resume if none waits any more, else point at
## the next one.
func _given_orders(ship_id: int) -> void:
	waiting.erase(ship_id)
	if waiting.is_empty():
		if speed == 0:
			set_speed(_resume_speed)
	else:
		var next := world.fleet.get_ship(waiting[0])
		Events.attention.emit(next.id, next.destination())

func buy_cargo(ship_id: int, commodity_id: String, qty: float) -> Dictionary:
	return _run(world.buy_cargo(PLAYER, ship_id, commodity_id, qty))

func sell_cargo(ship_id: int, commodity_id: String, qty: float) -> Dictionary:
	return _run(world.sell_cargo(PLAYER, ship_id, commodity_id, qty))

func set_orders(ship_id: int, orders: Array) -> Dictionary:
	return _run(world.set_orders(PLAYER, ship_id, orders))

## Starts route orders; like a send, this may resume the game.
func start_orders(ship_id: int) -> Dictionary:
	var r := _run(world.start_orders(PLAYER, ship_id))
	if r.ok:
		_given_orders(ship_id)
	return r

func stop_orders(ship_id: int) -> Dictionary:
	return _run(world.stop_orders(PLAYER, ship_id))

## Takes a job from the board for a player ship docked at its origin.
func accept_contract(contract_id: int, ship_id: int) -> Dictionary:
	return _run(world.accept_contract(PLAYER, contract_id, ship_id))

## Gives a job up: the penalty is charged.
func abandon_contract(contract_id: int) -> Dictionary:
	return _run(world.abandon_contract(PLAYER, contract_id))

## Insures a ship (monthly premium) or cancels its insurance.
func set_insurance(ship_id: int, on: bool) -> Dictionary:
	return _run(world.set_insurance(PLAYER, ship_id, on))

## "Safest" routing around dangerous lanes, or the shortest route.
func set_routing(ship_id: int, safest: bool) -> Dictionary:
	return _run(world.set_routing(PLAYER, ship_id, safest))

## Route a player ship could fly (charted systems only); a query, no events.
func plan_route(ship_id: int, target_system: int) -> Dictionary:
	return world.plan_route(PLAYER, ship_id, target_system)

## F2: chart the whole map and add a lot of money.
func cheat() -> void:
	world.reveal_all(PLAYER)
	player().cash += CHEAT_CASH
	world.events.append({"type": "cash", "company": PLAYER})
	Events.notice.emit("Cheat: everything charted, +%s cr" % Format.thousands(roundi(CHEAT_CASH)))
	_flush_events()

func take_loan(amount: float) -> Dictionary:
	return _run(world.take_loan(PLAYER, amount))

func repay_loan(amount: float) -> Dictionary:
	return _run(world.repay_loan(PLAYER, amount))

func player() -> Company:
	return world.companies[PLAYER]

## Shows refusals as notices, then publishes what the command changed.
func _run(result: Dictionary) -> Dictionary:
	if not result.get("ok", false):
		Events.notice.emit(result.get("error", "Not possible"))
	_flush_events()
	return result

func _hit_notice(e: Dictionary) -> void:
	var near := WorldEvents.place_name(world, e.system)
	var insured := "  Insurance paid %s cr." % Format.thousands(roundi(e.payout)) if e.has("payout") else ""
	if e.type == "lost":
		Events.notice.emit("%s was lost with all aboard near %s.%s" % [e.name, near, insured])
	else:
		Events.notice.emit("%s was raided near %s: cargo lost, repairs %s cr.%s" % [e.name, near,
			Format.thousands(roundi(e.repairs)), insured])

func _contract_notice(e: Dictionary) -> void:
	var c := world.get_contract(e.contract)
	if c == null:
		return
	var what := c.describe(Defs.commodities.get(c.commodity, {}).get("name", ""))
	var to := galaxy.systems[c.destination].name
	match e.type:
		"contract_accepted":
			Events.notice.emit("Contract taken: %s to %s by %s" % [what, to,
				Calendar.format(c.deadline, world.start_year)])
		"contract_done":
			Events.notice.emit("Delivered %s to %s: +%s cr" % [what, to, Format.thousands(roundi(e.reward))])
		"contract_failed":
			Events.notice.emit("Contract failed: %s to %s, penalty %s cr" % [what, to,
				Format.thousands(roundi(e.penalty))])

## Turns world events into signals and player notices.
func _flush_events() -> void:
	var fleet_moved := false
	var cash_changed := {}
	var charted := {}
	var attention := []
	var profits := {}  # player ship id -> summed profit
	var contracts_moved := false
	var events_moved := false
	for e in world.drain_events():
		match e.type:
			"charted":
				charted[e.company] = true
			"cargo", "orders":
				fleet_moved = true
				cash_changed[e.company] = true
			"sale":
				if e.company == PLAYER:
					profits[e.ship] = profits.get(e.ship, 0.0) + e.profit
			"orders_stopped":
				fleet_moved = true
				var stopped := world.fleet.get_ship(e.ship)
				if stopped and stopped.company == PLAYER:
					Events.notice.emit("%s stopped its route: %s" % [stopped.name, e.reason])
					attention.append([stopped.id, stopped.destination()])
			"arrived", "refitted", "departed", "bought", "sold", "refitting":
				fleet_moved = true
				if e.type == "sold":
					waiting.erase(e.ship)
				if e.type in ["bought", "sold", "refitting"]:
					cash_changed[e.company] = true
				var ship := world.fleet.get_ship(e.ship)
				if ship and e.type in ["departed", "arrived"]:
					cash_changed[ship.company] = true  # fuel, docking fee
				# Ships on route orders need nobody's attention.
				if ship and ship.company == PLAYER and not ship.orders_active:
					if e.type == "arrived":
						var here := galaxy.systems[e.system]
						Events.notice.emit(("%s docked at %s" if here.settlement else "%s is holding at %s (no spaceport)")
							% [ship.name, here.name])
						attention.append([ship.id, e.system])
					elif e.type == "refitted":
						Events.notice.emit("%s is out of the yard" % ship.name)
						attention.append([ship.id, e.system])
			"cash":
				cash_changed[e.company] = true
			"contracts":
				contracts_moved = true
			"news":
				events_moved = events_moved or e.item.kind != "loss"
				Events.news_posted.emit(e.item)
			"raided", "lost":
				fleet_moved = true
				cash_changed[e.company] = true
				if e.company == PLAYER:
					_hit_notice(e)
					waiting.erase(e.ship)
					# Bad news pauses the game, but the ship needs no new orders.
					if auto_pause and speed != 0:
						set_speed(0)
			"contract_accepted", "contract_done", "contract_failed":
				contracts_moved = true
				fleet_moved = true  # hold space and berths changed
				if e.type != "contract_accepted":
					cash_changed[e.company] = true
				if e.company == PLAYER:
					_contract_notice(e)
					if e.type == "contract_done":
						profits[e.ship] = profits.get(e.ship, 0.0) + e.reward
	for c in charted:
		Events.charted.emit(c)
	for id in profits:
		Events.profit.emit(id, profits[id])
	if events_moved:
		Events.world_events_changed.emit()
	if contracts_moved:
		Events.contracts_changed.emit()
	if fleet_moved:
		Events.fleet_changed.emit()
	for c in cash_changed:
		Events.company_changed.emit(c)
	if not attention.is_empty():
		for a in attention:
			if not waiting.has(a[0]):
				waiting.append(a[0])
		if auto_pause and speed != 0:
			set_speed(0)
		var last: Array = attention[attention.size() - 1]
		Events.attention.emit(last[0], last[1])
