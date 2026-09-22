extends Node
## Defs — loaded, read-only content definitions.
##
## All game content (commodities, hulls, modules, events, ...) lives in
## data/*.json and is loaded here at startup. Engine code reads these
## dictionaries; it never hard-codes content. Adding content = editing JSON,
## not touching this file.

const DATA_DIR := "res://data/"

## commodity id (String) -> definition (Dictionary: id, name, cargo_class, base_price)
var commodities: Dictionary = {}

func _ready() -> void:
	commodities = _load_json(DATA_DIR + "commodities.json")
	print("[Defs] loaded %d commodity definitions: %s" % [commodities.size(), ", ".join(commodities.keys())])

## Loads a JSON file expected to contain an array of objects each with an "id"
## field, and returns a dictionary keyed by that id. Returns {} on any failure.
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[Defs] missing data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("[Defs] failed to parse JSON: %s" % path)
		return {}
	if not (parsed is Array):
		push_error("[Defs] expected a JSON array at top level: %s" % path)
		return {}
	var out: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary and entry.has("id"):
			out[entry["id"]] = entry
		else:
			push_warning("[Defs] skipping entry without 'id' in %s" % path)
	return out
