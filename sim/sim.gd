extends Node
## Sim — owns the game world and the day clock.
##
## The simulation is pure data + logic, separate from rendering. The world
## itself lives in plain `RefCounted` classes (plan §2) so it is headlessly
## testable; this autoload only wraps it, advances it one game day per tick
## and emits `Events`.

## Game speeds in days per second; index 0 = paused.
const SPEEDS := [0, 1, 2, 4, 8]

var world: World
## Shortcut to world.galaxy.
var galaxy: Galaxy
## Index into SPEEDS.
var speed := 1

var _accumulator := 0.0

func _ready() -> void:
	var seed_value := int(Defs.world_content.balance.get("world_seed", 1))
	world = World.create(seed_value, Defs.stars, Defs.world_content)
	world.warm_up()
	galaxy = world.galaxy
	print("[Sim] world seed %d: %d inhabited systems, start at %s, %s" % [
		seed_value, world.settlements().size(),
		galaxy.systems[world.start_system].name if world.start_system >= 0 else "?",
		world.date_string()])

func set_speed(index: int) -> void:
	speed = clampi(index, 0, SPEEDS.size() - 1)
	_accumulator = 0.0
	Events.speed_changed.emit(speed)

## Space bar: pause, or resume at 1x.
func toggle_pause() -> void:
	set_speed(1 if speed == 0 else 0)

func _process(delta: float) -> void:
	if world == null or speed == 0:
		return
	_accumulator += delta * SPEEDS[speed]
	var steps := 0
	while _accumulator >= 1.0 and steps < 8:
		_accumulator -= 1.0
		steps += 1
		world.advance_day()
		Events.day_passed.emit(world.day)
