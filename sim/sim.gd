extends Node
## Sim — owns the game world and the day clock.
##
## The simulation is pure data + logic, separate from rendering. The world
## itself lives in plain `RefCounted` classes (plan §2) so it is headlessly
## testable; this autoload only wraps it, advances it one game day per tick
## and emits `Events`. The day clock arrives in Milestone 4.

var world: World
## Shortcut to world.galaxy.
var galaxy: Galaxy

func _ready() -> void:
	var seed_value := int(Defs.world_content.balance.get("world_seed", 1))
	world = World.create(seed_value, Defs.stars, Defs.world_content)
	galaxy = world.galaxy
	print("[Sim] world seed %d: %d inhabited systems, start at %s" % [
		seed_value, world.settlements().size(),
		galaxy.systems[world.start_system].name if world.start_system >= 0 else "?"])
