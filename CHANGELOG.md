# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Passengers, mail and contracts: every market posts a weekly board of jobs
  (`Contract`/`Contracts`) — freight charters (the client's own cargo of an
  export good, taking hold space of its cargo class), passenger groups
  (economy berths or luxury suites, none from robot worlds) and mail sacks —
  to destinations up to 5 lanes away, weighted to near and (for people/mail)
  big places. Reward scales with load and route length, penalty is 30% of
  the reward, and the deadline allows a slow ship plus slack. Accepting
  needs a ship docked at the origin with room and a charted destination;
  arriving pays the reward, missing the deadline or abandoning (or selling
  the ship) charges the penalty and drops the job. UI: Contracts panel (key
  C, or the system card's board button) with the market's offers, why a ship
  can't take one, and the player's running jobs with Abandon; fleet list
  shows each ship's contract count; finance panel gets Contracts and
  Penalties rows; market panel's hold line counts charter freight.
- Trading and routes: ships carry cargo (`Ship.cargo`, cost basis) in holds
  of the right cargo class; `Trading` buys and sells at the docked market
  (big lots move the price; no sales tax until tariffs and smuggling come
  with the government rules), buys fuel for each trip at departure (`fuel_per_ly` per
  hull, from the local market or dearer without one) and a docking fee on
  arrival at a settlement, and books crew, maintenance and loan interest on
  the first of each month. Every credit goes through `Company.book()` into a
  monthly ledger by category and by ship. Price knowledge per company: a
  company only knows prices where its ships have docked (refreshed weekly
  while docked), with the day it saw them. Route orders: looping stops with
  sell-all, buy one good (fill the hold), wait for a full load (up to 28
  days) or auto-trade (auto-trader module: best known margin for the next
  stop); ships on routes don't pause the game. UI: market panel with live
  or remembered prices and their age, Buy/Sell with lot sizes and cargo
  aboard; route editor (O); finances with borrow/repay (L); price map mode
  (P) tinting stars and names by known price.
- Each ship remembers what it paid for its cargo; every sale reports its
  profit against that, shown as a floating "+12,340 cr" (red for a loss)
  rising from the ship. A route that would sell its cargo at a loss stops,
  keeps the cargo and pauses the game; restarting the route there sells
  anyway.
- Ships and travel: `data/hulls.json` (9 hulls from a courier to heavy
  freighters, a bulk carrier, a tanker, a liner and two later models) and
  `data/modules.json` (cargo holds by cargo class, cabins, suites, mail bay,
  armour, drive tune, jump extender, auto-trader). The player's company
  (`Company`: cash, loan) starts with the Packet *Wanderer* at Lodestar.
  `Fleet` handles specs, shipyards (industrial/core/military/robot worlds at
  tech 8+, any world at tech 10), buying, selling, refits (cost, days in the
  yard), route planning limited by jump range, and daily travel; ships arrive
  on the predicted day. `World` commands take a company id (`buy_ship`,
  `sell_ship`, `refit_ship`, `send_ship`, `take_loan`, `repay_loan`) and
  report events that `Sim` turns into signals and notices. On the map, ships
  are chevrons in company colour moving smoothly along lanes, with the
  selected ship's route and a preview route. UI: fleet list, shipyard
  (buy / refit / sell), send line on the system card (jumps, ly, days,
  arrival date or why not), cash on the clock bar, notices. Ships in a
  system without a settlement are "holding", not "docked".
- Fog of war: each company charts systems (`Company.known`); a system and
  everything one jump from it are charted for good when a ship reaches or
  passes through it (the start world and its neighbours at the start).
  Uncharted stars show only their glow — no name, drop line, lanes, card,
  market or system view — and routes may only use charted systems.
- The game pauses and the camera flies to a player ship that arrives or
  leaves the yard (`Sim.auto_pause`, `main.gd auto_focus`; menu options
  later). F2 cheat: chart everything and add 10,000,000 cr.
- Drop lines are fainter, and Z hides/shows them (`GalaxyMap.show_drop_lines`).
- Sending a ship resumes the game at its previous speed, unless other ships
  are still waiting for orders (`Sim.waiting`, shown as "awaiting orders" in
  the fleet list); then it stays paused and focuses the next waiting ship.
- Calendar and markets: `data/archetypes.json` archetypes now list `industries`
  (input/output recipes, per market size) and `needs` (including `"*"` for
  free ports, which need every good); `data/balance.json` gets an `economy`
  section (market size from population + robots, `volume_scale` 20x on
  production/needs/transit stock/traffic capacity so stocks run to
  thousands-to-tens-of-thousands of tonnes, 30-day stock cover, price
  elasticity and clamps, a small transit stock of every good, weekly
  background traffic, soak limits). `Calendar` turns a day count into a date
  ("13 Jan 3400"); `Market.tick(days)` runs a settlement's recipes for that
  many days at once — each recipe runs at its scarcest input's rate and each
  output throttles separately as its stock fills, price follows stock vs
  target with clamps, and buying/selling a big lot moves the price along the
  way — and keeps a weekly price history. `Economy` builds one market per
  settlement from its archetype; `tick_day(day)` does nothing except on the
  last day of each `update_days` week, when it runs every market a week at a
  time, then moves weekly background traffic between markets up to 2 lanes
  apart, from cheap to dear, then samples prices. Player trades still move
  prices immediately. `World` now has a day clock (`advance_day`,
  `date_string`, `warm_up` to settle markets before day 0) and `Sim` drives
  it with a pause/1x/2x/4x/8x speed clock, emitting
  `Events.day_passed`/`speed_changed`.
- `make soak`: runs the economy headless for 20 game years and fails if
  prices sit at their clamps too often or a market's stock runs away; use it
  to tune `data/archetypes.json`/`balance.json`.
- UI: a clock bar (date, pause/1x-8x buttons, top centre) and a temporary
  market panel (every good's price, change vs base, stock, export/import,
  26-week sparkline) toggled by M or the system panel's Market button; Space
  pauses/resumes, keys 1-4 pick a speed.
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
