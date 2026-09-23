class_name Content
## Loads data/*.json. Used by the Defs autoload and directly by tests, so
## tests can build a World from the real data without autoloads.

## Loads a JSON array of objects with an "id" field into a dictionary keyed by
## that id. Returns {} on any failure.
static func load_list(path: String) -> Dictionary:
	var parsed: Variant = _parse(path)
	if not (parsed is Array):
		push_error("[Content] expected a JSON array at top level: %s" % path)
		return {}
	var out: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary and entry.has("id"):
			out[entry["id"]] = entry
		else:
			push_warning("[Content] skipping entry without 'id' in %s" % path)
	return out

## Loads a JSON file whose top level is an object. Returns {} on any failure.
static func load_object(path: String) -> Dictionary:
	var parsed: Variant = _parse(path)
	if not (parsed is Dictionary):
		push_error("[Content] expected a JSON object at top level: %s" % path)
		return {}
	return parsed

## Everything World.create needs besides the star map.
static func load_world_content(dir: String) -> Dictionary:
	return {
		"commodities": load_list(dir + "commodities.json"),
		"hulls": load_list(dir + "hulls.json"),
		"modules": load_list(dir + "modules.json"),
		"known_planets": load_object(dir + "known_planets.json"),
		"planet_types": load_list(dir + "planet_types.json"),
		"archetypes": load_list(dir + "archetypes.json"),
		"governments": load_list(dir + "governments.json"),
		"names": load_object(dir + "names.json"),
		"balance": load_object(dir + "balance.json"),
	}

static func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("[Content] missing data file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("[Content] failed to parse JSON: %s" % path)
	return parsed
