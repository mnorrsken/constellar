class_name Settlement
extends RefCounted
## The one inhabited place (and market) of a star system.

var name: String
## Index into StarSystem.planets it lives on or orbits; -1 = a deep-space
## station orbiting the star itself.
var planet := -1
## True for orbital stations (around giants, in belts, or in deep space).
var is_station := false
## Economy archetype id (data/archetypes.json).
var archetype: String
## Humans. Robot worlds have a handful (or none) and count robots instead.
var population: int
var robots := 0
## 1 (primitive) .. 10 (best in the galaxy).
var tech_level: int
## Government id (data/governments.json).
var government: String
## 0 (collapse) .. 1 (rock solid).
var stability: float

func to_dict() -> Dictionary:
	return {
		"name": name, "planet": planet, "is_station": is_station, "archetype": archetype,
		"population": population, "robots": robots, "tech_level": tech_level, "government": government,
		"stability": snappedf(stability, 0.001),
	}
