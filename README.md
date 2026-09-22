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
make stars     # rebuild data/stars.json from the HYG star catalogue
make clean     # remove the .godot/ cache
```

Override the binary if needed: `make test GODOT=/path/to/godot`.

## Map controls

Drag to orbit, right/middle-drag to pan, scroll or trackpad swipe/pinch to
zoom, click a star to select and fly to it, Esc to deselect, Home to return
to Sol. Keyboard: WASD/arrows pan, Q/E orbit, R/F tilt, -/= zoom, F1 toggles
the debug overlay.

## Documentation

- [`constellar-plan.md`](constellar-plan.md) — the authoritative design and
  milestone plan. Read this first.
- [`docs/architecture.md`](docs/architecture.md) — a map of the codebase.
- [`docs/progress.md`](docs/progress.md) — milestone-by-milestone status.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of notable changes.

## Credits

Star data (`data/stars.json`) comes from the [HYG
database](https://codeberg.org/astronexus/hyg) v4.4, licensed CC BY-SA 4.0.

Fonts (`assets/fonts/`): Exo 2, Inter and JetBrains Mono, licensed SIL Open
Font License 1.1.
