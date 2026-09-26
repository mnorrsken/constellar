# Progress log

Milestone-by-milestone status. See [`constellar-plan.md`](../constellar-plan.md)
for the plan and acceptance criteria this tracks.

Current test count: **132 tests, 3675 assertions, 0 failures** (`make test`).

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
- **M5 — Ships and travel — done.** Hulls and modules from data; the
  player's `Company` (cash, loan) with a start ship; `Fleet` shipyards,
  buy/sell/refit, jump-range routing and daily travel (ships arrive on the
  predicted day); `World` commands with a company id. Ship chevrons, route and
  preview on the map; fleet list, shipyard panel, send controls, notices.
  Fog of war (charted systems per company), auto-pause and focus on
  arrivals, F2 cheat.
- **M6 — Trading and routes — done.** Cargo by class, buying/selling,
  fuel and docking fees, monthly crew/maintenance/interest, a
  ledger by category and ship; per-company price knowledge with age; route
  orders (sell, buy, wait for full load, auto-trade). A test route runs 5
  years unattended. Market trading UI, route editor, finances, price map.
- **M7 — Passengers, mail and contracts — done.** Weekly job boards per
  market (`Contract`/`Contracts`): freight, passenger and mail charters,
  reward vs deadline penalty, hold/berth/mail-bay capacity. Contracts panel
  (C) to accept/abandon; fleet, finance and market UI show job counts,
  ledger rows and reserved hold space.
- **M8 — Events, governments and news — done.** Monthly events
  (`data/events.json`, `sim/world_event.gd`/`world_events.gd`) drive
  supply/demand, closed/embargoed ports, tariffs and government changes;
  governments (`data/governments.json`) gain tariffs, bans and lane danger,
  plus a zealots government reachable only via an event. Lane danger and
  raids/losses (`sim/danger.gd`), insurance and safest routing. News ticker
  and log, danger map mode, map badges.
- **M9 — Real UI and finance — done.** Ships age and can break down
  (`sim/aging.gd`); servicing at a shipyard or via a route stop restores
  condition. New hulls (Swift II, Starliner II, Leviathan II) with news
  headlines. Fleet screen (V), rewritten finance panel (ledger, profit
  charts) and shipyard panel (hull comparison, drag-and-drop fitting,
  Service), themed buttons/checkboxes/popups.
- **M10 — Influence and goals — done.** Per-system influence
  (`sim/influence.gd`) grows from sales (more where a good is scarce) and
  delivered contracts, and decays monthly; tiers unlock a trading post, a
  trade concession (lower tariffs, first pick of new contracts) and patron
  status (veto a tariff hike, broker peace, rarer wars/coups there).
  `sim/goals.gd`: a company value goal and a Merchant Prince (patron of 5
  systems) goal, checked monthly, plus bankruptcy after months in the red.
  Influence card on the system panel, an influence map mode, an outcome
  screen for reaching a goal or going bankrupt.
- **M11 — Save/load and main menu — pending.**
- **M12 — Rim Crises, art/audio pass, balance — pending.**
