class_name WorldEvent
extends RefCounted
## One running event from data/events.json: a war between two systems, a
## plague at one, pirates on a lane ... `systems` are the places it touches
## (for a lane event, the lane's two ends). Its effects hold from start_day
## until end_day (see WorldEvents.apply_all).

var id: int
## Event definition id (events.json).
var kind: String
## System indices: one for a system event, two for a pair or lane event.
var systems: Array[int] = []
## True for a lane event (pirates): the danger is on the lane between
## systems[0] and systems[1].
var on_lane := false
var start_day := 0
var end_day := 0
var headline := ""

func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "systems": systems.duplicate(), "on_lane": on_lane,
		"start_day": start_day, "end_day": end_day, "headline": headline,
	}
