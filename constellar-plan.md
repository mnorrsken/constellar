# Project Plan: Constellar: Merchant Empire

A space trade strategy game. You run a merchant house on the rim of a
decaying interstellar civilisation: buy ships, fit them out, set up trade
routes, and grow rich and powerful through trade. You do not win by fighting.

- **Feel:** Elite II / Frontier (a 3D star map with drop lines to the galactic
  plane, real nearby stars, one market per world) crossed with *Ports of Call*
  (you watch your ships cross the map; trips take weeks) and *Transport
  Tycoon* (fleet management, ship models, fitting, route orders, finance
  reports).
- **Theme:** Asimov's Foundation merchants. A fading old core around Sol,
  young rim worlds, and trade as the real source of power. Worlds that depend
  on your goods do what you want. Use our own names only. No "Foundation",
  "Seldon", "Terminus", "Trantor" or other Asimov terms in the game.
- **Not in v1:** real-time piloting, tactical combat, computer rivals. The
  code is built so rivals can be added later (§2.6).

This document is the reference plan for building the game with Claude Code.
Work milestone by milestone. Each milestone has acceptance criteria, and you
do not move on until they pass.

---

## 1. Technology decisions (locked)

- **Engine:** Godot 4.7 (the latest stable, already installed via Homebrew).
  Free, MIT licence, good 3D for a stylised map, and Control nodes plus
  Themes for a rich UI. Same toolchain as Regolith, so the Makefile, test
  runner and headless checks carry over.
- **Language:** GDScript. Move to C# or GDExtension only if profiling shows
  a hotspot. The sim runs one tick per game day over about 100 markets, so
  this is unlikely.
- **Renderer:** Forward+, for glow/bloom on stars and lanes, MSAA and custom
  spatial shaders. The Compatibility renderer is only needed if a web export
  becomes a goal later.
- **Version control:** git. Standard Godot `.gitignore` (`.godot/`,
  `build/`, `dist/`).
- **Star data:** the HYG database v4.x (codeberg.org/astronexus/hyg),
  licensed **CC BY-SA 4.0**. A one-off tool script turns it into
  `data/stars.json`. That file must credit HYG and stays under CC BY-SA.
  Known exoplanets come from the NASA Exoplanet Archive (public data), curated
  by hand into `data/known_planets.json`.
- **Fonts (OFL):** a geometric display face for headings (e.g. Exo 2 or
  Rajdhani), Inter for body text, and JetBrains Mono for numbers and prices
  (tabular figures, so columns do not jitter).
- **Placeholder audio/art:** Kenney packs (CC0) until custom assets exist.
  Most visuals are shaders and procedural meshes anyway.

## 2. Architecture principles (read before writing code)

1. **Sim and rendering are separate.** The sim is pure data and logic,
   advanced by a fixed tick of **one game day**. The map and the UI only read
   sim state. Ships move smoothly on screen because the renderer interpolates
   between day ticks using the tick accumulator fraction. The sim never knows
   about frames.
2. **Pure, injectable sim classes.** Core logic lives in `RefCounted`
   classes with no autoload, signal or rendering dependencies. `World` owns
   all state and has `advance_day()`. The `Sim` autoload wraps `World`, runs
   the clock and emits `Events`. This makes the whole economy headlessly
   testable, including multi-decade soak runs.
3. **Three sim autoloads only:** `Sim` (world + clock), `Defs` (loads
   `data/*.json`), `Events` (signal bus). Add at most one view-layer autoload
   later (`Audio`), as in Regolith.
4. **Content is data-driven.** Commodities, cargo classes, hulls, modules,
   economy archetypes, governments, events and balance numbers all live in
   `data/*.json`. A new ship model or event type means editing JSON, not
   code.
5. **Deterministic.** One seeded RNG in `World` for all sim randomness.
   Per-star generation uses `hash(world_seed, star_id)`, so a star's planets
   do not change when other content is added. Saves store the RNG state.
6. **Everything the player does is a command on `World`**, and every command
   takes a `company_id`: `buy_ship(company, hull, system)`,
   `set_orders(company, ship, orders)`, `trade(company, ship, commodity, qty)`
   and so on. The player is just company 0. Ships, cargo, price knowledge and
   influence all belong to a company. Computer rivals later become more
   companies that call the same commands. No player-only code paths.
7. **Coordinates in one place.** `GalaxyCoords` owns the conversion from the
   catalogue (galactic XYZ in parsecs) to light years to Godot world space
   (1 unit = 1 ly, galactic north = +Y, Sol at the origin). Nothing else does
   coordinate maths.
8. **Information is per company.** A company only knows a market's prices as
   of the last time one of its ships docked there, or live if it owns a
   trading post there. The UI always shows how old a price is. This is cheap
   to build and gives both the Foundation "information is power" feel and a
   reason to spread your network.

Folder structure (mirrors Regolith):

```
data/      stars.json, lanes_overrides.json, known_planets.json,
           commodities.json, archetypes.json, governments.json,
           hulls.json, modules.json, events.json, names.json, balance.json
sim/       world, galaxy (systems, lanes, pathfinding), planets (generation),
           economy (markets, industries), fleet (ships, orders), company,
           world_events, influence, galaxy_coords
render/    galaxy_map (stars, lanes, drop lines, grid), ship_markers,
           system_view (orrery), map_modes
ui/        theme, HUD, panels (market, shipyard, fleet, finance, news)
tests/     headless tests (runner copied from Regolith)
tools/     build_stars.py (HYG -> stars.json), balance soak script
```

## 3. Game design summary

### Setting and core loop

Year ~3400. The Concordance, the old civilisation centred on Sol, is slowly
decaying: less trade, worse tech, governors going their own way. Out on the
rim, young colonies need everything and trust nobody. You start as a small
merchant house on a rim world with one old freighter, a bank loan and a
charter to trade. The start world is one fixed rim world, the same in every
game, picked in Milestone 3 from the generated rim settlements (a small
colony a few lanes from a busier hub). A short intro text sets the scene.

Loop: **read the markets → buy or charter a ship → fit it for the cargo →
set a route → watch it cross the map for weeks → collect profit → expand
the fleet and your influence → react to wars, tariffs and crises.**

### Time and pacing

- 1 tick = 1 day. Speeds: pause / 1× (≈1 day per second) / 2× / 4× / 8×.
  Space pauses. Optional auto-pause on arrival, event or bankruptcy warning.
- Drive speed is in ly/day. An early hull does ~0.25 ly/day, so a 6 ly lane
  takes ~24 days. Late hulls reach ~1 ly/day.
- A campaign runs 30–50 game years. New hull models become available by year
  (Transport Tycoon style), and old ships lose reliability as they age.

### The galaxy (real stars, simplified)

- **~100–130 star systems.** All real systems within ~20 ly of Sol form a
  dense old core (Alpha Centauri, Barnard's Star, Sirius, Epsilon Eridani,
  Procyon, 61 Cygni, Tau Ceti, Epsilon Indi…). A sparser set of notable
  stars out to ~50 ly forms the rim (Altair, Vega, Fomalhaut, Castor,
  Capella, Arcturus, Pollux, TRAPPIST-1, 55 Cancri, Upsilon Andromedae…).
  Real positions, real spectral types. Sol is the old core, the rim is where
  you start.
- **Multiple stars are real:** Alpha Cen A/B + Proxima, Sirius A + white
  dwarf B, 61 Cygni A/B, Castor (six stars), 70 Ophiuchi and others. Up
  close they are drawn as orbiting pairs. They limit planet orbits
  (close binaries clear the zone between the two stars).
- **Star look from data:** colour from spectral class (O/B blue-white → M
  orange-red), size and halo from luminosity, and special looks for white
  dwarfs, brown dwarfs and giants (Arcturus, Pollux, Capella).
- **Starlanes:** built once by the tool script. Take the k nearest
  neighbours (k≈3–4) up to a maximum lane length, then add the minimum
  spanning tree so the graph is always connected, then apply hand edits from
  `lanes_overrides.json`. Long "deep lanes" (>9 ly) can only be flown by
  ships with enough jump range. That makes upgrading hulls matter and
  creates natural choke points. The max lane length is a knob: tune it until
  the core is dense and the rim has a few real bottlenecks.

### Planets and settlements

- **Known exoplanets are used where they exist** (Proxima b, Epsilon Eridani
  b, Ross 128 b, Teegarden's b, Gliese 667C, TRAPPIST-1 b–h, 55 Cancri,
  HD 219134…). The rest are generated from the star: habitable zone at
  ≈ √L AU, snow line at ≈ 2.7·√L AU. Rocky worlds inside, gas giants
  beyond. Red dwarf planets are small and tidally locked ("eyeball worlds").
  White dwarf systems have debris belts.
- **Planet types:** molten, barren rock, desert, tidally locked, ocean, ice,
  garden (very rare), gas giant, ice giant, asteroid belt.
- **v1: one market per inhabited system.** The settlement sits on the best
  body (or a station). Several ports per system can come in v2.
- **Each settlement has:** population, tech level (1–10), government,
  stability (0–1), and an **economy archetype** that follows from geography:
  - garden/ocean world → agricultural (exports food, needs machinery)
  - barren rock / belt → mining (exports ore and rare elements, needs food)
  - gas giant → fuel refinery (He-3, deuterium)
  - ice world → water and volatiles
  - old core world → high-tech and consumer (exports electronics and robots,
    imports raw materials and luxuries)
  - young rim colony → needs almost everything
  - plus research stations, military bases and free ports.

  Geography decides who needs what, so good trade routes come out of the
  map and are not just random numbers.

### Commodities and cargo classes

About 18 goods, each in a cargo class. The cargo class decides which ship
module can carry it (the Transport Tycoon wagon-type idea):

| Class | Goods |
|---|---|
| Bulk | Ore, Grain, Water Ice |
| Liquid | Fuel (He-3/Deuterium), Chemicals |
| Container | Metals, Machinery, Consumer Goods, Textiles, Electronics, Robots |
| Cold | Luxury Foods, Medicine, Biologics |
| Secure | Rare Elements, Luxuries, Weapons, Atomics (small high-tech devices, the rim's "atomic gadgets") |

Governments decide what is legal. Weapons, narcotics and atomics can be
banned or taxed. Smuggling is a v2 candidate.

Passengers (economy and luxury) and mail are separate cargo, carried in
cabins and a mail bay.

### Economy model

- Every market holds a **stock** per commodity. Each day, industries turn
  inputs into outputs (partial output if inputs are short), and the
  population consumes goods.
- **Price** = base × (target stock ÷ stock)^elasticity, clamped to about
  0.25×–4× base, then multiplied by event modifiers and tariffs.
  Target stock = N days of local demand.
- **Your trades move the price.** Buying or selling a large lot is priced
  along the curve (integrated), so dumping 500 t of grain on one market
  crashes it. This stops "one route forever" and rewards spreading out.
- **Background traffic:** an abstract flow along each lane moves goods from
  cheap to expensive neighbours at limited capacity. It stands in for the
  thousands of NPC traders, stops markets drifting to extremes, and later
  shrinks as real rival companies take its place.
- Every market keeps price history (weekly samples), shown as sparklines.

### Ships (Transport Tycoon hints)

- **Hulls** (`hulls.json`): courier, light / medium / heavy freighter, bulk
  carrier, tanker, liner. Each hull has a price, module slots, speed
  (ly/day), jump range (ly), crew cost per month, maintenance, reliability,
  year introduced and year retired.
- **Modules** (`modules.json`): bulk hold, container hold, cold hold, tank,
  secure vault, economy cabins, luxury suites, mail bay. Non-cargo: armour
  plating (lowers loss chance on dangerous lanes), drive tune (+speed),
  jump extender (+range), auto-trader computer. Refitting costs money and
  takes days at a shipyard.
- **Shipyards** only exist at industrial and high-tech worlds, so where you
  buy and refit ships is itself a geographic choice.
- **Aging:** reliability drops with age. Breakdowns cause delays and repair
  bills. Servicing at a shipyard resets part of it. The finance screen
  shows when a ship is no longer worth keeping.

### Orders and routes

- **Manual:** send a ship to a system, and buy or sell there by hand
  (Ports of Call style, good for the first hours).
- **Route orders** (Transport Tycoon style): a looping list of stops. Each
  stop has buy rules (commodity, max quantity, max price), sell rules
  (commodity, min price), "wait for full load" with a timeout, and service
  or refuel.
- **Auto-trade** (needs the auto-trader module): at each stop the ship buys
  whatever has the best known margin for its next stop. The quality of its
  decisions depends on how fresh your price info is.
- **Contracts board** at every market: freight charters (deliver X to Y by a
  date for a fixed fee), passengers and mail. This is safe early income and
  the main way a one-ship house gets started.
- Pathfinding: A* over the lane graph, using only lanes within the ship's
  jump range. Weights are travel time plus a risk penalty the player can set
  ("safest / fastest").

### Money

Cash, a bank loan (max amount and interest, as in Transport Tycoon), monthly
ledger (revenue per ship; costs for crew, maintenance, fuel, docking fees,
tariffs and insurance), company value, and profit-per-ship charts.
Bankruptcy: cash below zero for 3 months with the loan maxed out.

### Events and politics

- **Data-driven events** (`events.json`): each has a trigger (monthly
  chance plus conditions such as government, stability, archetype or
  distance), effects (supply/demand multipliers, tariffs, bans, lane risk,
  port closed, government change, population change), a duration and a
  headline template.
- **Starter set:** war between two systems (lanes between them become
  dangerous, demand for weapons, food and medicine goes up); zealot
  government takes power (tariffs on luxuries, ban on narcotics and atomics);
  plague (medicine demand way up); crop failure; mining strike (a new
  deposit); labour strike (port closed); pirate activity on a lane; stellar
  flare at a red dwarf (station damage, fuel demand); embargo; trade
  agreement (tariffs removed between two systems); festival (luxury
  demand).
- **Governments** (`governments.json`): corporate, democracy, theocracy,
  military junta, feudal lord, Concordance governor, anarchy. Each has a
  tariff profile, banned goods, a base stability, and how likely it is to
  start or join wars.
- **News feed** ("The Rim Courier"): a scrolling ticker plus a news log,
  with each headline linked to its system on the map.
- **Insurance:** optional monthly premium per ship, priced from the lanes it
  used last month. Pays out on losses.

### Influence (the Foundation layer)

- Each company has an **influence score (0–100) per system**. It grows with
  the value of goods you deliver there (much more for goods the system is
  short of), passengers carried and contracts completed. It decays slowly.
- **Tiers:**
  - 25: may open a **trading post** (warehouse, live prices, lower fees)
  - 50: **trade concession** (half tariffs, first pick of contracts)
  - 75: **patron** (lobby: veto a new tariff, lower the odds of coups and
    war there, broker peace when both sides of a war depend on you)
- This makes Asimov's idea playable: worlds that depend on your trade do not
  go to war against your interests.
- **Rim Crises** (late milestone): every 8–12 years, a scripted multi-stage
  crisis (a Concordance tariff wall, a warlord's embargo, a rebel admiral)
  whose outcome depends on your influence and your economic position, not
  on fleets.

### Victory / defeat (v1)

Sandbox with optional goals chosen at new game: company value target, the
Merchant Prince goal (patron in N systems), or come through the Rim Crises
with your house intact. Defeat by bankruptcy.

### Look and UI ("sleek and modern, not boring")

- **Map:** deep ink-blue space with a faint polar grid on the galactic
  plane centred on Sol. Stars are glowing billboards with bloom. Each star
  has a thin **drop line** to the grid plane with a small foot marker, the
  Elite II trick that makes 3D depth readable. Lanes are thin lines with an
  animated flow shader. Brightness and thickness show trade volume, so the
  economy is visible at a glance. Ships are small glowing chevrons in their
  company's colour, with short trails, moving along the lanes.
- **Camera:** orbit around a focused star, smooth zoom, click a star to fly
  the focus to it, double-click to open the system view (a stylised,
  not-to-scale orrery of the planets and settlement, as in Elite II).
- **Map modes** (hotkeys): price of a chosen commodity (heat colour per
  system), government, danger, influence, and age of price info.
- **Panels:** dark glass panels with thin 1 px borders, one accent colour
  (amber for money and your company; cyan for information; red/magenta for
  danger). Numbers in tabular monospace. Prices tick up and down with small
  coloured arrows, sparklines in market tables, and panels slide in with
  easing. System badges pulse for active events (red ring for war, amber for
  tariffs).
- **Screens:** market (table + sparklines + contracts), shipyard (hull
  compare + drag-and-drop module fitting with a slot diagram), fleet list,
  route editor, finance (ledger + charts), news log.

---

## 4. Milestones

### Milestone 0 — Project skeleton

Godot 4.7 project (Forward+), the folder layout above, `.gitignore`,
Makefile (`run`, `editor`, `import`, `test`, `clean`), test runner copied
from Regolith, empty `Sim` / `Defs` / `Events` autoloads, `Defs` loading a
placeholder `commodities.json`. Main scene: an empty 3D scene with
WorldEnvironment glow enabled.

*Accept when:* `make import` is clean, `make test` runs one passing test,
the game opens to a dark scene, and `Defs` prints the loaded commodities.

### Milestone 1 — Star catalogue and lanes

`tools/build_stars.py`: read HYG, pick the systems (≤20 ly plus the notable
stars ≤50 ly), group multiple stars into one system, write `stars.json`
(id, name, position in ly, components with spectral class, luminosity and
mass). Build the lanes (k-nearest + minimum spanning tree + overrides).
`GalaxyCoords` and the galaxy/lane classes in `sim/`. Pathfinding with a
jump-range filter.

*Accept when:* tests pass for a connected graph, correct Sol–Alpha Cen
distance (~4.37 ly), Sirius and Castor loaded as multi-star systems, and
paths that avoid lanes longer than the ship's range. The tool prints lane
stats (count, longest, choke points).

### Milestone 2 — 3D galaxy map

Stars rendered from data (MultiMesh billboards + halo shader, colour and
size by spectral type), drop lines and grid plane, lanes as one mesh with a
flow shader, orbit camera, hover tooltip, click to focus with a smooth fly-to,
binary pairs visible when zoomed in. A debug overlay with star ids and
coordinates behind a hotkey.

*Accept when:* the whole map runs smoothly on this Mac, depth is readable
thanks to the drop lines, every star can be picked reliably after any camera
move, and a screenshot already looks like a game, not a debug view.

### Milestone 3 — Planets and settlements

Planet generation per star (seeded, known exoplanets first), multi-star
orbit limits, settlement placement, archetype, population, tech level,
government. The system view (orrery) and a system info panel. Pick the
fixed rim start world and record it in `balance.json`.

*Accept when:* the same seed always gives the same planets; changing
`known_planets.json` does not change other systems; archetypes follow
geography (gas giant systems refine fuel, etc.); every inhabited system
opens a readable system view.

### Milestone 4 — Calendar and markets

Day tick with speed controls and a date display. Commodities, archetype
industries, consumption, stock/price model, integrated trade pricing,
background lane traffic, weekly price history. Temporary market panel.

*Accept when:* tests show prices rise when stock falls and that selling a
big lot gets a worse average price than a small one; a headless 20-year soak
run without players keeps markets out of the price clamps most of the time
(threshold in `balance.json`) and shows no runaway stock.

### Milestone 5 — Ships and travel

Hulls, modules, the company (cash + loan), shipyards, buy/sell/refit ship,
send a ship to a system, travel time from lane length and speed, arrival
events. Ship chevrons moving along lanes with interpolation between ticks.

*Accept when:* you can buy a ship at a shipyard, fit modules, send it
across several lanes and watch it arrive on the predicted day; a ship with
too little jump range routes around a deep lane or reports that it cannot
reach the target.

### Milestone 6 — Trading and routes

Manual buy/sell with cargo class checks, fuel and docking fees, tariffs,
per-company price knowledge with age, route orders with buy/sell rules and
full-load waiting, the ledger. Map mode for commodity prices.

*Accept when:* a full manual trade loop makes money; a two-stop route runs
unattended for 5 game years; the UI shows the age of every known price; a
test proves a company does not see prices it has no source for.

### Milestone 7 — Passengers, mail and contracts

Passenger and mail generation from population and distance, cabins and the
mail bay, a contracts board with deadlines, penalties and rewards.

*Accept when:* a new game can be started and grown from one ship using only
contracts and passengers; missed deadlines apply penalties.

### Milestone 8 — Events, governments and news

Event engine from `events.json`, the starter event set, government effects
(tariffs, bans, stability), lane danger and losses, armour and insurance,
news ticker and log, system event badges, danger map mode.

*Accept when:* in a 20-year soak run every starter event fires at least once
with visible market effects; a zealot takeover changes tariffs and the
route orders respect the new bans; a war makes its lanes dangerous and the
"safest" routing avoids them.

### Milestone 9 — Real UI and finance

Replace debug UI: the full Theme (fonts, colours, glass panels, motion),
market screen with sparklines, shipyard with a drag-and-drop fitting view,
fleet list, route editor, finance screen with charts, ship aging,
breakdowns, servicing, and new hull models by year.

*Accept when:* the game is playable without reading code; every idle or
losing ship explains why (no cargo match, price too low, waiting for full
load, broken down); an old ship's falling profit is visible on the charts.

### Milestone 10 — Influence and goals

Influence per company per system, trading posts, concessions, patron
actions, influence map mode, victory goals, bankruptcy.

*Accept when:* long-term trade with a system reliably raises its tier and
unlocks the matching action; a patron can veto a tariff event; each victory
goal and bankruptcy can be reached in a test game.

### Milestone 11 — Save/load and main menu

Serialise the whole world (galaxy seed, markets, companies, ships, orders,
knowledge, influence, active events, date, RNG state) to JSON in
`user://saves/`. Main menu: New Game (seed, goal), Continue,
Load, Quit. Autosave every game year.

*Accept when:* save → quit → load gives an identical world, checked by
comparing a re-serialised snapshot with the save file, and both copies
advanced 1 year from the load are also identical (determinism).

### Milestone 12 — Rim Crises, art/audio pass, balance

Scripted crises, final shaders and effects, ambient music and UI sounds,
`balance.json` tuning from soak runs and playtests (target: a comfortable
first fleet of 5 ships in 2–4 hours of play).

*Accept when:* three full playtests reach a goal without exploits or dead
ends, and a screenshot of the map reads as "sleek, modern, Elite II".

### Later (v2 candidates, design only)

- **Computer rival houses** — companies driven by an AI that calls the same
  `World` commands, with their own knowledge and influence. They compete for
  contracts, markets and patronage.
- Several ports per system; smuggling and customs; exploring and charting
  new lanes; colony founding (seed a new market); crew and captains with
  traits; multiplayer hot-seat.

---

## 5. Working with Claude Code on this project

- One milestone per session or branch. Commit at each acceptance criterion.
  Refer to this file and the current milestone by number.
- Headless tests for the sim: lane graph, pathfinding, price curves, trade
  pricing, travel time, event effects, knowledge per company, save/load
  determinism. A long soak run (`make soak`) is the main balance tool.
- New content is a data entry in `data/*.json`, not a new code path.
- When something on the map looks wrong, suspect `GalaxyCoords` first, and
  keep the debug overlay from Milestone 2 behind a hotkey for the life of
  the project.
- Add a repo `CLAUDE.md` in Milestone 0 (commands, architecture rules,
  pointer to this plan), plus `docs/progress.md` and `docs/architecture.md`
  as in Regolith.

## 6. Open questions

- Galaxy size: real stars ≤20 ly + notable stars ≤50 ly (≈100–130
  systems) is the assumption. A bigger radius gives more rim but longer,
  sparser lanes.

Decided: the title is **Constellar: Merchant Empire**, and the game starts on
one fixed rim world.
