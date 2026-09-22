# Progress log

Milestone-by-milestone status. See [`constellar-plan.md`](../constellar-plan.md)
for the plan and acceptance criteria this tracks.

Current test count: **34 tests, 499 assertions, 0 failures** (`make test`).

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
- **M3 — Planets and settlements — pending.**
- **M4 — Calendar and markets — pending.**
- **M5 — Ships and travel — pending.**
- **M6 — Trading and routes — pending.**
- **M7 — Passengers, mail and contracts — pending.**
- **M8 — Events, governments and news — pending.**
- **M9 — Real UI and finance — pending.**
- **M10 — Influence and goals — pending.**
- **M11 — Save/load and main menu — pending.**
- **M12 — Rim Crises, art/audio pass, balance — pending.**
