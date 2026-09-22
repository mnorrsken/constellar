class_name GalaxyCoords
## The one place that converts between galactic coordinates and Godot world
## space (plan §2.7).
##
## Galactic (as in data/stars.json, built by tools/build_stars.py): light
## years, Sol at the origin, +X toward the galactic centre, +Y in the direction
## of galactic rotation, +Z toward the north galactic pole.
##
## World: 1 unit = 1 light year, Sol at the origin, +Y (up) = galactic north,
## so the galactic plane is Godot's XZ ground plane. Both frames are
## right-handed; this is a pure rotation, so distances are the same in both.

static func to_world(galactic: Vector3) -> Vector3:
	return Vector3(galactic.x, galactic.z, -galactic.y)

static func to_galactic(world: Vector3) -> Vector3:
	return Vector3(world.x, -world.z, world.y)
