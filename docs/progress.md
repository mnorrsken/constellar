# Progress log

Milestone-by-milestone status. See [`constellar-plan.md`](../constellar-plan.md)
for the plan and acceptance criteria this tracks.

Current test count: **65 tests, 2310 assertions, 0 failures** (`make test`).

- **M0 — Project skeleton — done.** Godot 4.7 project setup, autoloads
  (`Events`/`Defs`/`Sim`), `data/commodities.json`, Makefile, headless test
  harness.
- **M1 — Star catalogue and lanes — done.** `make stars` builds
  `data/stars.json` (140 systems, 315 lanes, fully connected at a 12 ly jump
  range) from the HYG v4.4 catalogue; `Galaxy`/`StarSystem`/`Lane`/
  `GalaxyCoords` load it and provide pathfinding and coordinate conversion.
- **M2 — 3D galaxy map — done.** `GalaxyMap` draws the polar grid, starlanes,
  drop lines and stars (glow billboards, distance-faded labels);
  `MapCamera`/`OrbitRig` orbit/pan/zoom; `StarPicker` drives hover/click
  selection and fly-to; HUD, star tooltip, F1 debug overlay.
- **M3 — Planets and settlements — done.** Deterministic per-seed world
  generation (`World.create`): known real planets plus rolled ones
  (`PlanetGen`), settlements with archetype/population/tech/government
  (`SettlementGen`), all driven by `data/known_planets.json`,
  `planet_types.json`, `archetypes.json`, `governments.json`, `names.json`
  and `balance.json`. Uninhabited systems (usually dead ends) may roll a
  robot world instead. Full-screen system view (`SystemView`/`OrreryLayout`,
  double-click or Enter to open) and a map-side system panel showing the
  selected system's settlement.
- **M4 — Calendar and markets — done.** `Calendar` (day -> date) and
  `Market`/`Economy` (per-settlement recipes and prices, weekly background
  traffic between markets) drive the game world; `World` runs a day clock
  (`advance_day`, `warm_up` to settle markets before day 0) and `Sim` adds a
  pause/1x-8x speed clock. `make soak` runs the economy 20 game years
  headless and checks it stays healthy. Clock bar and a temporary market
  panel in the UI.
- **M5 — Ships and travel — pending.**
- **M6 — Trading and routes — pending.**
- **M7 — Passengers, mail and contracts — pending.**
- **M8 — Events, governments and news — pending.**
- **M9 — Real UI and finance — pending.**
- **M10 — Influence and goals — pending.**
- **M11 — Save/load and main menu — pending.**
- **M12 — Rim Crises, art/audio pass, balance — pending.**
