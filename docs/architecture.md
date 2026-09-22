# Architecture

A map of the codebase as it exists today. For the design/milestone plan, see
[`constellar-plan.md`](../constellar-plan.md); for what's done vs. pending,
see [`progress.md`](progress.md). This file describes real files and real
APIs — if it and the code disagree, trust the code and fix this file.

## Project setup

`project.godot` targets Godot 4.7, **Forward+** rendering. Autoloads load in
this order:

1. **`Events`** (`sim/events.gd`) — a global signal bus. Empty for now; the
   sim will emit signals here as milestones need them, and UI/render layers
   will connect. Per the plan, UI must never poke `Sim` internals directly.
2. **`Defs`** (`sim/defs.gd`) — loads read-only content definitions from
   `data/*.json` at startup. `_load_json` reads a JSON array of id-keyed
   objects into a `Dictionary` (id → entry), pushing an error and returning
   `{}` on any parse failure. Currently loads one dictionary,
   `Defs.commodities`, from `data/commodities.json`.
3. **`Sim`** (`sim/sim.gd`) — will own the world and the day clock (plan
   §2). Empty placeholder until Milestone 4 adds the tick loop; the actual
   world state will live in plain `RefCounted` classes so it stays
   headlessly testable.

The viewport is 1920×1080 with `canvas_items` stretch mode.

## Data

`data/commodities.json` is an array of 18 commodity objects, each with
`id`, `name`, `cargo_class`, and `base_price`. Cargo classes: `bulk`,
`liquid`, `container`, `cold`, `secure`.

## Main scene

`main.tscn` is a `Node3D` with a `WorldEnvironment` (ink-blue background,
filmic tonemap, glow enabled) and a `Camera3D`.

## Tests

`tests/run_tests.gd` is a headless `SceneTree` runner
(`godot --headless --script res://tests/run_tests.gd`, wrapped by `make
test`). It discovers every `tests/test_*.gd`, instantiates it, and calls
each `test_*` method with a `Tester` (`t.ok(cond, msg)` / `t.eq(a, b,
msg)`), exiting non-zero on any failure.

`tests/test_defs.gd` covers the data pipeline `Defs` depends on, reading
`data/commodities.json` directly (no autoloads): array of 18 entries, all
required fields present, ids unique, cargo classes all known.
