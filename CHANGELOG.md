# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Planets and settlements: `data/known_planets.json` (real planets after the
  NASA Exoplanet Archive, ~30 systems), `data/planet_types.json`,
  `data/archetypes.json` (10 economy archetypes plus `robot`),
  `data/governments.json` (including `custodians`, for robot worlds only),
  `data/names.json` and `data/balance.json` drive per-system generation.
  `PlanetGen` places known planets first and rolls the rest from stellar
  physics (habitable zone, snow line, tidal locking, giant-star and
  white-dwarf cases); `SettlementGen` picks which systems are inhabited —
  or, per `balance.json` `robot_world_chance`, an uninhabited system may
  instead become a robot world (high tech, no/few humans, many robots,
  usually a dead end) — and their archetype, population, tech level,
  government and stability; `World.create` builds it all deterministically
  per seed and gives every settlement a unique name, every root used once
  across the galaxy (seed 1: 120 of 140 systems settled, including 14 robot
  worlds; only 2 of 17 dead ends left empty).
- System view: double-click a star or press Enter to open a full-screen
  orrery (`SystemView`/`OrreryLayout`) with the habitable zone, snow line
  and settlement marked; a system panel (`SystemPanel`/`SettlementCard`) on
  the map shows the selected system's settlement. Esc closes the view, then
  deselects. Star tooltip and map now show each system's settlement (name,
  archetype, population or robot count) or "Uninhabited".

- Project skeleton: Godot 4.7 Forward+ project, Makefile, headless test
  runner, `Events`/`Defs`/`Sim` autoloads, `data/commodities.json` with 18
  commodities in 5 cargo classes, and a dark space main scene with glow.
- Star catalogue and starlane network: `make stars` builds `data/stars.json`
  (140 systems, 315 lanes) from the HYG v4.4 database, and `Galaxy`/
  `StarSystem`/`Lane`/`GalaxyCoords` load and query it (pathfinding, jump
  range, galactic-to-world coordinates).
- 3D galaxy map: `GalaxyMap` draws the polar grid, starlanes (deep lanes over
  12 ly in violet), drop lines, and stars as glow billboards with
  distance-faded name labels; `MapCamera`/`OrbitRig` orbit/pan/zoom by mouse,
  trackpad or keyboard; `StarPicker` drives hover/click selection and
  fly-to. HUD, star tooltip and an F1 debug overlay; Exo 2, Inter and
  JetBrains Mono fonts (SIL OFL 1.1).

### Changed

- UI now renders at 1.25x scale (1536x864 logical UI on a 1920x1080 window),
  with a larger default font and star name labels. System view body labels
  are placed by measured text width (settlement first, others below if
  free, else above, else skipped) instead of a fixed layout.
- Fixed two HYG curation errors: Gliese 860's M6 companion had been picked
  as the system primary (renamed to Kruger 60, correct primary); 36
  Ophiuchi's three components corrected to dwarfs.
