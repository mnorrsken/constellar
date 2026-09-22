extends Node
## Sim — owns the game world and the day clock.
##
## The simulation is pure data + logic, separate from rendering. The world
## itself will live in plain `RefCounted` classes (`World` and friends, plan §2)
## so it is headlessly testable; this autoload only wraps it, advances it one
## game day per tick and emits `Events`. Empty until Milestone 4 adds the clock.
