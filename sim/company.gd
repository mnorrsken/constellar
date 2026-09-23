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
## ship id -> {month index: net}. Categories: sales, purchases,
## fuel, docking, crew, maintenance, interest, ships.
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
		s[month] = s.get(month, 0.0) + amount

## Keeps the last `months` months of books.
func trim_ledger(current_month: int, months: int) -> void:
	for m in ledger.keys():
		if m <= current_month - months:
			ledger.erase(m)
	for s in ship_ledger.values():
		for m in s.keys():
			if m <= current_month - months:
				s.erase(m)

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
