# Constellar — convenience wrapper around the Godot CLI.
# Override the engine binary if it isn't on PATH:  make run GODOT=/path/to/godot

GODOT ?= godot
PROJECT := .

# HYG star catalogue (CC BY-SA 4.0), downloaded once into build/ for `make stars`.
HYG_URL := https://codeberg.org/astronexus/hyg/media/branch/main/data/hyg/CURRENT/hyg_v44.csv.gz
HYG := build/hyg_v44.csv.gz

.DEFAULT_GOAL := help

.PHONY: help run editor build import test soak stars clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: ## Run the game (main scene)
	$(GODOT) --path $(PROJECT)

editor: ## Open the project in the Godot editor
	$(GODOT) --editor --path $(PROJECT)

build: import ## Alias for `import`: compile + reimport, fail on errors

import: ## Headless import: build the .godot cache and catch script/asset errors
	$(GODOT) --headless --editor --quit --path $(PROJECT)

test: ## Run headless sim tests (non-zero exit on failure)
	$(GODOT) --headless --path $(PROJECT) --script res://tests/run_tests.gd

soak: ## Run the economy for 20 game years headless and check market health
	$(GODOT) --headless --path $(PROJECT) --script res://tools/soak.gd

stars: $(HYG) ## Rebuild data/stars.json (systems + lanes) from the HYG catalogue
	python3 tools/build_stars.py $(HYG)

$(HYG):
	mkdir -p $(dir $@)
	curl -fL -o $@ $(HYG_URL)

clean: ## Remove Godot's generated cache and build output
	rm -rf $(PROJECT)/.godot $(PROJECT)/build
