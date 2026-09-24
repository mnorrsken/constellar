class_name Company
extends RefCounted
## A merchant house: money and debt. The player is company 0; rival houses
## later are more companies using the same World commands.

var id: int
var name: String
var color: Color
## Credits.
var cash := 0.0
var loan := 0.0
var loan_max := 0.0
var interest_per_year := 0.0
## Fog of war: one byte per system, 1 = charted (name, lanes, settlement and
## market known). Charted systems stay charted.
var known := PackedByteArray()
## What the company knows of prices: system index -> {day, price
## (PackedFloat64Array by commodity index)}. Only from its own ships (and,
## later, trading posts): no source, no entry.
var prices: Dictionary = {}
## Monthly books: month index -> {category: signed amount}; and per ship:
## ship id -> {month index: {category: signed amount}}. Categories: sales,
## purchases, contracts, penalties, tariffs, fuel, docking, crew,
## maintenance, insurance, repairs, interest, ships. Besides the cash,
## both keep "cost_of_sales": what the goods sold had cost (a memo, not
## cash), so profit can count goods when they are sold (see profit()).
var ledger: Dictionary = {}
var ship_ledger: Dictionary = {}

static func from_dict(company_id: int, d: Dictionary) -> Company:
	var c := Company.new()
	c.id = company_id
	c.name = d.get("name", "House %d" % company_id)
	c.color = Color.html(str(d.get("color", "ffffff")))
	c.cash = float(d.get("cash", 0))
	c.loan = float(d.get("loan", 0))
	c.loan_max = float(d.get("loan_max", 0))
	c.interest_per_year = float(d.get("interest_per_year", 0))
	return c

## Records money in or out (negative) in the books and the cash.
func book(category: String, amount: float, month: int, ship_id := -1) -> void:
	cash += amount
	var m: Dictionary = ledger.get_or_add(month, {})
	m[category] = m.get(category, 0.0) + amount
	if ship_id >= 0:
		var s: Dictionary = ship_ledger.get_or_add(ship_id, {})
		var cats: Dictionary = s.get_or_add(month, {})
		cats[category] = cats.get(category, 0.0) + amount

## Keeps the last `months` months of books.
func trim_ledger(current_month: int, months: int) -> void:
	for m in ledger.keys():
		if m <= current_month - months:
			ledger.erase(m)
	for s in ship_ledger.values():
		for m in s.keys():
			if m <= current_month - months:
				s.erase(m)

## Notes what goods sold in a month had cost (no cash moves).
func note_cost_of_sales(amount: float, month: int, ship_id: int) -> void:
	var m: Dictionary = ledger.get_or_add(month, {})
	m.cost_of_sales = m.get("cost_of_sales", 0.0) - amount
	var cats: Dictionary = ship_ledger.get_or_add(ship_id, {}).get_or_add(month, {})
	cats.cost_of_sales = cats.get("cost_of_sales", 0.0) - amount

## Cash in minus cash out in a month (for one ship, or the whole company
## with ship_id -1).
func cash_net(month: int, ship_id := -1) -> float:
	var total := 0.0
	var cats: Dictionary = ledger.get(month, {}) if ship_id < 0 else ship_ledger.get(ship_id, {}).get(month, {})
	for k in cats:
		if k != "cost_of_sales":
			total += cats[k]
	return total

## Profit in a month: like cash_net, but goods count when they are sold
## (at what they cost) instead of when they are bought, and buying,
## refitting or selling ships ("ships") is investment, not profit. Ship or
## company.
func profit(month: int, ship_id := -1) -> float:
	var total := 0.0
	var cats: Dictionary = ledger.get(month, {}) if ship_id < 0 else ship_ledger.get(ship_id, {}).get(month, {})
	for k in cats:
		if k != "purchases" and k != "ships":
			total += cats[k]
	return total

func is_known(system_index: int) -> bool:
	return system_index < known.size() and known[system_index] != 0

func take_loan(amount: float) -> Dictionary:
	if amount <= 0.0:
		return {"ok": false, "error": "Nothing to borrow"}
	if loan + amount > loan_max:
		return {"ok": false, "error": "The bank lends at most %s" % Format.thousands(roundi(loan_max))}
	loan += amount
	cash += amount
	return {"ok": true}

func repay_loan(amount: float) -> Dictionary:
	amount = minf(amount, loan)
	if amount <= 0.0:
		return {"ok": false, "error": "No loan to repay"}
	if amount > cash:
		return {"ok": false, "error": "Not enough cash"}
	loan -= amount
	cash -= amount
	return {"ok": true}

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "cash": snappedf(cash, 0.01), "loan": snappedf(loan, 0.01)}
