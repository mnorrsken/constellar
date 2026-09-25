# Constellar: Merchant Empire

A space trade strategy game. You run a merchant house on the rim of a
decaying interstellar civilisation: buy ships, fit them out, set up trade
routes, and grow rich and powerful through trade. You do not win by
fighting.

## Running

Godot 4.7 is installed via Homebrew (`brew install --cask godot`), on PATH
as `godot`. All work goes through the Makefile:

```
make run       # run the game
make editor    # open the Godot editor
make test      # headless test suite
make import    # headless import; catches script/asset errors
make soak      # run the economy 20 game years headless and check market health
make stars     # rebuild data/stars.json from the HYG star catalogue
make audio     # regenerate the music and UI sounds
make clean     # remove the .godot/ cache
```

Override the binary if needed: `make test GODOT=/path/to/godot`.

## Map controls

Drag to orbit, right/middle-drag to pan, scroll or trackpad swipe/pinch to
zoom, click a star to select and fly to it, Esc to deselect, Home to return
to Sol, Z to hide/show the drop lines from stars to the galactic plane. Keyboard: WASD/arrows pan, Q/E orbit, R/F tilt, -/= zoom, F1 toggles
the debug overlay.

Double-click a star, or select it and press Enter, to open its system view.
Esc closes the system view first, then deselects.

Ships: click a ship's chevron on the map, or pick it in the fleet card
(bottom left: "Ships (n)" opens a list, ◀ ▶ step through the fleet), to
open its card on the right: model, route, cargo with what it cost and what
it's worth, contracts aboard, condition, profit, and buttons for its
orders and the port it's docked at. Select a star, and press S (or the
star card's Send button) to
send it there; the card shows jumps, days and the arrival date, or why the
ship can't go. Every inhabited world can refit your ships (the card's
Refit button): drag modules onto slots, or between slots to swap. Small
colonies only make simple modules (each module needs a tech level; the
ones a port can't make are greyed out). New ships are built, sold and
serviced only at the major worlds' shipyards (the card's Shipyard button). The game pauses and
flies to a ship when it arrives or leaves the yard; sending it on resumes
the game, unless other ships are still awaiting orders.

The fleet list, market panel, route orders panel and fleet screen each show
a small 3D model of the ship — drag it to turn it by hand. In the
shipyard, click a hull in the list to see its model, numbers and standard
fit before you buy; your own ships there show the fit you're editing.

Ships wear with age and travel; a worn ship is less reliable and can break
down under way, costing days and a repair bill. Servicing at a shipyard
(or a route stop's "Service when worn" option) restores it, though older
ships can't be serviced back to full. V, or the fleet card's "All", opens the
fleet screen: every ship's status, why it's idle or losing money, age,
condition, reliability, last month's and a year of results, and
Show/Orders/Service buttons.

Fog of war: you only see the glow of distant stars. A system and everything
one jump from it are charted once one of your ships gets there; routes only
use charted systems. F2 (cheat) charts everything and adds 10,000,000 cr.

Trading: with a ship docked, the market panel (M) shows live prices with
Buy/Sell buttons (lot size at the top); elsewhere it shows the last prices
your ships saw and how old they are. O opens the selected ship's route
orders (add the selected system as a stop; sell, buy, wait for a full load,
auto-trade, service when worn at a shipyard; Start route). L shows the
finances: cash, loan (borrow/repay), a ledger table, profit charts and a
ship table with age, condition and loss reasons.
P cycles the map mode: stars, danger (lanes and stars coloured by the
chance of a hit), then the price maps. Every sale shows its profit (or
loss) floating up from the ship. A route that would sell at a loss stops
and pauses the game; restart it to sell anyway.

Events and danger: wars, strikes, pirates, embargoes and other events come
and go, moving prices, closing ports, banning or tariffing goods and
raising the danger of nearby lanes; pulsing map badges mark where
something is happening. The Rim Courier ticker (bottom right, click a
headline to select its system) shows the latest news; N opens the full
log. Flying a dangerous lane can cost a ship its cargo or itself; the route
orders panel (O) has a safest-routing toggle (routes around danger) and an
insurance toggle (a monthly premium that pays out on a raid or loss).

Press M, or the system panel's Market button, to see the selected system's
market. Space pauses/resumes the game clock; 1-4 set its speed (also
buttons on the clock bar, top centre).

Contracts: C, or the system card's Contracts button, shows a market's job
board (freight, passengers, mail) for a docked ship, and your running jobs
with Abandon. Deliver on time for the reward; miss the deadline or abandon
and you pay the penalty.

Sound: music follows the star you zoom in on (its world type's theme, or a
calmer "space" theme when zoomed out); K cycles music/sound/off. All music
and UI sounds are generated by `tools/make_audio.py` (`make audio`).

## Documentation

- [`constellar-plan.md`](constellar-plan.md) — the authoritative design and
  milestone plan. Read this first.
- [`docs/architecture.md`](docs/architecture.md) — a map of the codebase.
- [`docs/progress.md`](docs/progress.md) — milestone-by-milestone status.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of notable changes.

## Credits

Star data (`data/stars.json`) comes from the [HYG
database](https://codeberg.org/astronexus/hyg) v4.4, licensed CC BY-SA 4.0.
Known exoplanets (`data/known_planets.json`) are drawn loosely from the
[NASA Exoplanet Archive](https://exoplanetarchive.ipac.caltech.edu/).

Fonts (`assets/fonts/`): Exo 2, Inter and JetBrains Mono, licensed SIL Open
Font License 1.1.

Music and UI sounds are synthesized by `tools/make_audio.py`, not recorded
or licensed from anywhere.
