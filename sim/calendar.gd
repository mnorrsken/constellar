class_name Calendar
## Game dates. Day 0 is 1 January of the start year; 365-day years (no leap
## days — nobody on a starship cares).

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const DAYS_PER_YEAR := 365

## {year, month (1-12), day (1-31)} for a game day number.
static func date(day: int, start_year: int) -> Dictionary:
	var year := start_year + day / DAYS_PER_YEAR
	var rest := day % DAYS_PER_YEAR
	var month := 0
	while rest >= MONTH_DAYS[month]:
		rest -= MONTH_DAYS[month]
		month += 1
	return {"year": year, "month": month + 1, "day": rest + 1}

## "12 Mar 3401"
static func format(day: int, start_year: int) -> String:
	var d := date(day, start_year)
	return "%d %s %d" % [d.day, MONTHS[d.month - 1], d.year]
