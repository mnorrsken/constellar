class_name Ship
extends RefCounted
## One ship: which company owns it, its hull and fitted modules, and where it
## is — docked at a system, refitting at a shipyard, or travelling a route of
## system indices (position = current leg + light years along it).

enum Status { DOCKED, TRAVELING, REFITTING }

var id: int
var name: String
var company: int
## Hull id (data/hulls.json).
var hull: String
## One module id per hull slot (data/modules.json).
var modules: Array[String] = []
var status := Status.DOCKED
## Where it is docked or refitting; -1 while travelling.
var system := -1
## Travel: system indices from departure to destination.
var route := PackedInt32Array()
var leg := 0
var leg_progress := 0.0
var departed_day := 0
var arrival_day := 0
## Refitting until this day.
var busy_until := 0
var bought_day := 0
## Cargo: commodity index -> tonnes, and what was paid for it in total.
var cargo: Dictionary = {}
var cargo_cost: Dictionary = {}
## Route orders: looping stops, each {system, sell_all, buy: [{commodity,
## amount (0 = fill)}], wait_full, auto}. See Trading.process_orders.
var orders: Array[Dictionary] = []
var order_index := 0
var orders_active := false
## At the current stop: trades done, and the day loading started.
var stop_handled := false
var wait_start := 0
## The player restarted the route here: sell even at a loss this once.
var allow_loss := false

func cargo_tonnes() -> float:
	var t := 0.0
	for c in cargo:
		t += cargo[c]
	return t

func destination() -> int:
	return route[route.size() - 1] if status == Status.TRAVELING else system

func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "company": company, "hull": hull, "modules": modules.duplicate(),
		"status": status, "system": system, "route": Array(route), "leg": leg,
		"leg_progress": snappedf(leg_progress, 0.0001), "departed_day": departed_day,
		"arrival_day": arrival_day, "busy_until": busy_until, "bought_day": bought_day,
		"cargo": cargo.duplicate(), "orders": orders.duplicate(true), "order_index": order_index,
		"orders_active": orders_active,
	}
