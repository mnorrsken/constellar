class_name Planet
extends RefCounted
## One body in a star system: a planet or an asteroid belt.

var name: String
## Index into StarSystem.hosts: the star (or close pair) it orbits.
var host: int
var orbit_au: float
## Earth masses; 0 for belts.
var mass_earth: float
## Planet type id (data/planet_types.json).
var type: String
## Equilibrium temperature in kelvin.
var temperature_k: float
var tidally_locked := false
## True for real, catalogued planets (data/known_planets.json).
var known := false

func is_giant() -> bool:
	return type == "gas_giant" or type == "ice_giant"

func to_dict() -> Dictionary:
	return {
		"name": name, "host": host, "orbit_au": snappedf(orbit_au, 0.0001),
		"mass_earth": snappedf(mass_earth, 0.001), "type": type,
		"temperature_k": roundi(temperature_k), "tidally_locked": tidally_locked, "known": known,
	}
