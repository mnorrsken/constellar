extends Node
## Events — global signal bus.
##
## Sim emits signals here; UI and render layers connect to them. UI must never
## poke Sim internals directly: it calls Sim methods and listens on this bus.
## Keep signals coarse and gameplay-meaningful; add them as milestones need them.

## Emitted after the world advanced one day (day = new day number).
signal day_passed(day: int)

## Emitted when the game speed changes (0 = paused).
signal speed_changed(speed: int)
