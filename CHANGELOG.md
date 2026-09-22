# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
