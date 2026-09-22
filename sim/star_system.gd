class_name StarSystem
extends RefCounted
## One star system: a position and one or more stars. Planets and the
## settlement arrive in Milestone 3.

## Position in Galaxy.systems.
var index: int
var id: String
var name: String
## Galactic coordinates in light years (see GalaxyCoords).
var position: Vector3
## Brightest first. Each: name, spect, class, subclass, lum_class,
## luminosity (L☉, bolometric estimate), mass (M☉).
var stars: Array[Dictionary] = []

func is_multiple() -> bool:
	return stars.size() > 1

func primary() -> Dictionary:
	return stars[0] if not stars.is_empty() else {}
