class_name Contract
extends RefCounted
## One job on a market's contract board: carry freight (the client's own
## cargo, loaded free), a group of passengers or mail sacks from `origin` to
## `destination` by `deadline`. Delivered on time = `reward`; missed =
## `penalty` and the job is taken away.

enum Status { OFFERED, ACCEPTED, DONE, FAILED }

var id: int
## "freight", "passengers" or "mail".
var kind: String
var origin: int
var destination: int
## Freight: commodity id; passengers: "" (see luxury).
var commodity := ""
var luxury := false
## Tonnes, passengers or sacks.
var amount := 0
var reward := 0.0
var penalty := 0.0
var deadline := 0
## Offered until this day (then it disappears from the board).
var offered_until := 0
var status := Status.OFFERED
var company := -1
var ship := -1

## "400 t Machinery", "32 luxury passengers", "12 mail sacks".
func describe(commodity_name := "") -> String:
	match kind:
		"freight":
			return "%s t %s" % [Format.thousands(amount), commodity_name if commodity_name != "" else commodity]
		"passengers":
			return "%d %spassenger%s" % [amount, "luxury " if luxury else "", "" if amount == 1 else "s"]
	return "%d mail sack%s" % [amount, "" if amount == 1 else "s"]

func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "origin": origin, "destination": destination, "commodity": commodity,
		"luxury": luxury, "amount": amount, "reward": snappedf(reward, 0.01), "penalty": snappedf(penalty, 0.01),
		"deadline": deadline, "offered_until": offered_until, "status": status, "company": company, "ship": ship,
	}
