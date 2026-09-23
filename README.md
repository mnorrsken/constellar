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

Ships: click a ship's chevron on the map or its row in the fleet list
(bottom left), select a star, and press S (or the card's Send button) to
send it there; the card shows jumps, days and the arrival date, or why the
ship can't go. The system card's Shipyard button opens the shipyard (buy,
refit, sell) at industrial and high-tech worlds. The game pauses and flies
to a ship when it arrives or leaves the yard; sending it on resumes the
game, unless other ships are still awaiting orders.

Fog of war: you only see the glow of distant stars. A system and everything
one jump from it are charted once one of your ships gets there; routes only
use charted systems. F2 (cheat) charts everything and adds 10,000,000 cr.

Trading: with a ship docked, the market panel (M) shows live prices with
Buy/Sell buttons (lot size at the top); elsewhere it shows the last prices
your ships saw and how old they are. O opens the selected ship's route
orders (add the selected system as a stop; sell, buy, wait for a full load,
auto-trade; Start route). L shows the finances (ledger, borrow, repay).
P cycles the price map: stars and names coloured by what you know of one
good's price. Every sale shows its profit (or loss) floating up from the
ship. A route that would sell at a loss stops and pauses the game; restart
it to sell anyway.

Press M, or the system panel's Market button, to see the selected system's
market. Space pauses/resumes the game clock; 1-4 set its speed (also
buttons on the clock bar, top centre).

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
