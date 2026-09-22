extends RefCounted
## Milestone 0 smoke tests: the data pipeline that Defs depends on.
## Tests pure data directly — no autoloads, no rendering — per the
## "sim is headlessly testable" architecture principle.

const COMMODITIES := "res://data/commodities.json"
const CARGO_CLASSES := ["bulk", "liquid", "container", "cold", "secure"]

func _parse(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func test_commodities_is_array_of_eighteen(t: Object) -> void:
	var data: Variant = _parse(COMMODITIES)
	t.ok(data is Array, "commodities.json parses to an Array")
	t.eq(data.size(), 18, "commodity definition count")

func test_commodities_have_required_fields(t: Object) -> void:
	for entry in _parse(COMMODITIES):
		for key in ["id", "name", "cargo_class", "base_price"]:
			t.ok(entry is Dictionary and entry.has(key), "entry missing '%s'" % key)

func test_commodity_ids_are_unique(t: Object) -> void:
	var data: Variant = _parse(COMMODITIES)
	var ids := {}
	for entry in data:
		ids[entry["id"]] = true
	t.eq(ids.size(), data.size(), "commodity ids are unique")

func test_commodities_use_known_cargo_classes(t: Object) -> void:
	for entry in _parse(COMMODITIES):
		t.ok(entry["cargo_class"] in CARGO_CLASSES,
			"'%s' has unknown cargo class '%s'" % [entry["id"], entry["cargo_class"]])
