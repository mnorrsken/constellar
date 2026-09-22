class_name StarSystem
extends RefCounted
## One star system: a position, one or more stars, the planets generated
## around them (PlanetGen) and at most one settlement (SettlementGen).

## Position in Galaxy.systems.
var index: int
var id: String
var name: String
## Galactic coordinates in light years (see GalaxyCoords).
var position: Vector3
## Brightest first. Each: name, spect, class, subclass, lum_class,
## luminosity (L☉, bolometric estimate), mass (M☉).
var stars: Array[Dictionary] = []
## What planets orbit: single stars, or close pairs merged into one host.
## Each: name, stars (Array of star indices), luminosity, mass, class,
## lum_class, inner_au, outer_au (stable orbit zone). Brightest first.
var hosts: Array[Dictionary] = []
## Sorted by host, then orbit.
var planets: Array[Planet] = []
## Null if nobody lives here.
var settlement: Settlement

func is_multiple() -> bool:
	return stars.size() > 1

func primary() -> Dictionary:
	return stars[0] if not stars.is_empty() else {}
