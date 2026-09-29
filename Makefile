# Constellar — convenience wrapper around the Godot CLI.
# Override the engine binary if it isn't on PATH:  make run GODOT=/path/to/godot

GODOT ?= godot
PROJECT := .

# HYG star catalogue (CC BY-SA 4.0), downloaded once into build/ for `make stars`.
HYG_URL := https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v44.csv.gz
HYG := build/hyg_v44.csv.gz

.DEFAULT_GOAL := help

# Music and UI sounds are generated from tools/make_audio.py (not in git).
AUDIO := assets/audio/music/space.wav

.PHONY: help run editor build import test soak stars audio soundtrack export-windows export-mac clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: $(AUDIO) ## Run the game (main scene)
	$(GODOT) --path $(PROJECT)

editor: $(AUDIO) ## Open the project in the Godot editor
	$(GODOT) --editor --path $(PROJECT)

build: import ## Alias for `import`: compile + reimport, fail on errors

audio: ## Regenerate the music loops and UI sounds (tools/make_audio.py)
	python3 tools/make_audio.py

soundtrack: ## Render ~5-minute MP3s of every music theme into build/soundtrack/ (needs lame)
	python3 tools/make_soundtrack.py

$(AUDIO): tools/make_audio.py
	python3 tools/make_audio.py

import: $(AUDIO) ## Headless import: build the .godot cache and catch script/asset errors
	$(GODOT) --headless --editor --quit --path $(PROJECT)

test: ## Run headless sim tests (non-zero exit on failure)
	$(GODOT) --headless --path $(PROJECT) --script res://tests/run_tests.gd

soak: ## Run the economy for 20 game years headless and check market health
	$(GODOT) --headless --path $(PROJECT) --script res://tools/soak.gd

# Exports need Godot's export templates for this exact version (Editor >
# Manage Export Templates). Installers are built from these by CI (release.yml).
export-windows: import ## Export the Windows game to build/windows/Constellar.exe
	mkdir -p build/windows
	$(GODOT) --headless --path $(PROJECT) --export-release "Windows Desktop" build/windows/Constellar.exe

export-mac: import ## Export the macOS app (zipped) to build/macos/Constellar.zip
	mkdir -p build/macos
	$(GODOT) --headless --path $(PROJECT) --export-release "macOS" build/macos/Constellar.zip

stars: $(HYG) ## Rebuild data/stars.json (systems + lanes) from the HYG catalogue
	python3 tools/build_stars.py $(HYG)

$(HYG):
	mkdir -p $(dir $@)
	curl -fL -o $@ $(HYG_URL)

clean: ## Remove Godot's generated cache and build output
	rm -rf $(PROJECT)/.godot $(PROJECT)/build
