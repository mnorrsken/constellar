# CLAUDE.md — Constellar: Merchant Empire

Space trade strategy game in **Godot 4.7** (GDScript). Elite II star map +
Ports of Call ship travel + Transport Tycoon fleet management, themed on
Asimov's Foundation merchants (our own names only, no Asimov terms).

- **The plan is authoritative:** `constellar-plan.md` defines the milestones
  (0–12) and the architecture principles. Read it before starting work.
- **Current status & codebase map:** `docs/progress.md` (milestone status) and
  `docs/architecture.md` (how the code fits together). Keep these as the source
  of truth for "where are we" — do not duplicate status into this file.

## Commands

Godot is installed via Homebrew (`brew install --cask godot`), on PATH as
`godot`. All work goes through the Makefile:

- `make run` — run the game
- `make editor` — open the Godot editor
- `make test` — headless test suite (exits non-zero on failure). The full
  suite takes about 35 s; `make test T="trading save"` runs only
  `tests/test_trading.gd` and `tests/test_save.gd`
- `make import` / `make build` — headless import. **Exits 0 even on script
  errors**: grep its output for `ERROR`/`SCRIPT`/`WARNING`
- `make soak` — 20 game years of the economy headless; fails if markets sit
  at the price clamps too often or stock runs away (limits in
  `data/balance.json` economy.soak). Run it after changing economy data.
- `make audio` — regenerate the music loops and UI sounds
  (`tools/make_audio.py`, plain Python). The WAVs are not in git; `make
  run`/`editor`/`import` build them when the script changes
- `make soundtrack` — render a ~5-minute MP3 of each music theme to
  `build/soundtrack/` (`tools/make_soundtrack.py`; needs the `lame`
  encoder). For listening, not shipped with the game
- `make export-windows` / `make export-mac` — export the game to `build/`
  (needs Godot's export templates for this exact version)
- `make clean` — remove the `.godot/` cache

Override the binary if needed: `make test GODOT=/path/to/godot`.

## Architecture (don't violate these — see the plan §2)

- **Sim and rendering are separate.** Sim is pure data + logic advanced one
  game day per tick; the map and UI only read sim state and interpolate
  between ticks for smooth motion.
- **Pure, injectable sim classes.** Core logic lives in `RefCounted` classes
  with **no autoload/Events/rendering dependencies**, so it is headlessly
  testable. The `Sim` autoload wraps the world and emits `Events`.
- **Three sim autoloads only:** `Sim` (world + clock), `Defs` (loads
  `data/*.json`), `Events` (signal bus). UI never pokes sim internals — it
  calls Sim methods and listens on `Events`.
- **Every player action is a command with a `company_id`.** The player is
  company 0; computer rivals later use the same commands. No player-only
  code paths.
- **Content is data-driven:** commodities, hulls, modules, events etc. live
  in `data/*.json`. Adding content = editing JSON, not engine code.
- **Deterministic:** one seeded RNG in the world; per-star generation seeded
  from `hash(world_seed, star_id)`.
- **Coordinates in one place:** `tools/build_stars.py` writes galactic XYZ in
  light years; `GalaxyCoords` owns galactic → world space (1 unit = 1 ly,
  galactic north = +Y, Sol at origin).

Folders: `sim/` (logic), `render/` (map views), `ui/` (panels, theme), `data/`
(JSON), `tests/` (headless tests), `tools/` (data build scripts). Create a
folder when the first file for it lands.

## Development flow (follow this loop)

1. **One milestone at a time**, in plan order. Don't move on until its
   acceptance criteria pass.
2. **Put new logic in the pure sim classes** so it can be tested without the
   engine. The `Sim` autoload is a thin wrapper that emits `Events`.
3. **Write headless tests** in `tests/test_*.gd`. The runner
   (`tests/run_tests.gd`) auto-discovers every `test_*` method and passes a
   tester `t` with `t.ok(cond, msg)` / `t.eq(a, b, msg)`. Construct sim
   classes with hand-made defs; don't rely on autoloads in tests. For a
   warmed-up world use `WarmWorld.make(stars, content)`
   (`tests/warm_world.gd`): it warms one world per run and hands out
   exact copies from its save data.
4. **Verify before declaring done** (after each edit, the quick checks):
   - `make import` — output has no `ERROR`/`SCRIPT`/`WARNING` lines (the exit
     code alone proves nothing)
   - `godot --headless --quit-after 20 --path .` — no runtime errors
   - Sim changes: `make test T="<files>"` for the test files of the area
     you touched (UI/render-only changes need none)
   - **Visual check via a throwaway capture scene** (below) when a change is
     visual.
   - The **full `make test` only before a commit or push**, and it must be
     all green then.
5. **After each logical feature/change, hand off to the docs agent**
   (`subagent_type: "docs"`) to update `CHANGELOG.md` (under `Unreleased`,
   Keep a Changelog headings), `README.md`, `docs/progress.md` (one status
   line per milestone) and `docs/architecture.md`. It commits only when told
   to and only if `make test` is green; it never pushes.

### Visual verification (headless screenshots)

Create a *throwaway* `capture.tscn` + `capture.gd`, run it, read the PNG,
then delete both files:

```gdscript
extends Node
var _f := 0
func _ready() -> void:
	Sim.show_menu = false  # else the main menu covers the map
	add_child(load("res://main.tscn").instantiate())
func _process(_d: float) -> void:
	_f += 1
	if _f == 30:  # let a few frames render (set up sim state earlier if needed)
		get_viewport().get_texture().get_image().save_png("<scratch>/shot.png")
		get_tree().quit()
```

Run with `godot --path . res://capture.tscn` (not headless; it needs a
renderer), view the PNG, then `rm capture.gd capture.tscn capture.gd.uid`.
Save PNGs to a scratch dir, never the repo.

## Git

Commit messages: `feat: …`, `fix: …`, `docs: …` (short, imperative). Never
commit `.godot/` (gitignored). Commit only verified work.

## Release notes

Follows the wiki "GitHub Release Process"; what differs here:

- CHANGELOG headings are Keep a Changelog: `## [X.Y.Z] - YYYY-MM-DD` (the
  `## [Unreleased]` section becomes it). `release.yml` takes the notes from
  that exact heading and fails without it.
- Bump `config/version` in `project.godot` in the release commit: the tag
  must match it or `release.yml` refuses to build.
- A `vX.Y.Z` tag runs `.github/workflows/release.yml` (laid out like
  fringeworlds'; it only builds and publishes, no game tests): the Windows
  export on Linux, the macOS export plus DMG
  (`packaging/macos/build-dmg.sh`) on a Mac, a per-user MSI (WiX 6,
  `packaging/windows/`) built on Windows, then the GitHub release with
  checksums. `ci.yml` runs the checks on the same tag (nothing runs on
  pushes to main); run `make test` locally before pushing.
- Before tagging a change to the process, dry-run it: `gh workflow run
  release.yml` builds everything and publishes nothing.
- Nothing is signed: SmartScreen warns on Windows, and Gatekeeper blocks the
  first start on macOS (the release notes say how to get past both).
- Godot upgrades: bump the default version in
  `.github/actions/setup-godot/action.yml`.

## GDScript notes

- **Indent with tabs** (Godot convention) — mixed spaces/tabs won't parse.
- Cast `InputEvent` subtypes before accessing subtype fields
  (`var mb := event as InputEventMouseButton`) or type inference fails.
- Star data (`data/stars.json`, from HYG) is CC BY-SA 4.0: keep the credit.
