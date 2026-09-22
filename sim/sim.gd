extends Node
## Sim — owns the game world and the day clock.
##
## The simulation is pure data + logic, separate from rendering. The world
## itself lives in plain `RefCounted` classes (plan §2) so it is headlessly
## testable; this autoload only wraps it, advances it one game day per tick
## and emits `Events`. The day clock arrives in Milestone 4.

## The star map, built from data/stars.json at startup.
var galaxy: Galaxy

func _ready() -> void:
	galaxy = Galaxy.from_dict(Defs.stars)
