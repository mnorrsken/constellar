extends RefCounted
## The generated star map (data/stars.json, from tools/build_stars.py).
## If these fail after `make stars`, fix the tool or its curation file.

const STARS := "res://data/stars.json"

## Every system must be reachable with this jump range (the planned range of
## the starting hull; plan Milestone 5).
const START_RANGE_LY := 12.0

var _data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STARS))
var _g := Galaxy.from_dict(_data)

func test_credit_present(t: Object) -> void:
	var credit: String = _data.get("credit", "")
	t.ok("HYG" in credit and "CC BY-SA 4.0" in credit, "stars.json credits HYG under CC BY-SA 4.0")

func test_all_systems_and_lanes_loaded(t: Object) -> void:
	t.eq(_g.size(), _data.systems.size(), "ids unique, every system indexed")
	t.eq(_g.lanes.size(), _data.lanes.size(), "every lane refers to known systems, no duplicates")
	t.ok(_g.size() >= 100, "at least 100 systems (got %d)" % _g.size())

func test_connected(t: Object) -> void:
	t.ok(_g.is_fully_connected(), "every system reachable")
	t.ok(_g.is_fully_connected(START_RANGE_LY), "every system reachable with a %.0f ly range" % START_RANGE_LY)

func test_sol_and_alpha_centauri(t: Object) -> void:
	var sol := _g.system_by_id("sol")
	var acen := _g.system_by_id("alpha_centauri")
	t.ok(sol != null and sol.position == Vector3.ZERO, "Sol at the origin")
	var d := sol.position.distance_to(acen.position)
	t.ok(absf(d - 4.37) < 0.1, "Sol–Alpha Centauri ≈ 4.37 ly (got %.3f)" % d)
	t.eq(acen.stars.size(), 3, "Alpha Centauri A, B and Proxima")

func test_multiple_star_systems(t: Object) -> void:
	var sirius := _g.system_by_id("sirius")
	t.ok(sirius.is_multiple(), "Sirius is multiple")
	t.eq(sirius.stars[1].get("class"), "D", "Sirius B is a white dwarf")
	t.eq(_g.system_by_id("castor").stars.size(), 6, "Castor has six stars")

func test_stars_have_physics(t: Object) -> void:
	for s in _g.systems:
		t.ok(not s.stars.is_empty(), "%s has stars" % s.name)
		for star in s.stars:
			t.ok(star.luminosity > 0.0 and star.mass > 0.0, "%s has luminosity and mass" % star.name)

func test_paths_respect_jump_range(t: Object) -> void:
	var sol := _g.index_of("sol")
	var castor := _g.index_of("castor")
	for jump in [START_RANGE_LY, 16.0]:
		var path := _g.find_path(sol, castor, jump)
		t.ok(path.size() >= 2, "Sol→Castor reachable with %.0f ly range" % jump)
		for i in range(1, path.size()):
			t.ok(_g.distance(path[i - 1], path[i]) <= jump, "hop within %.0f ly" % jump)
	t.ok(_g.path_length(_g.find_path(sol, castor, 16.0))
		<= _g.path_length(_g.find_path(sol, castor, START_RANGE_LY)) + 0.001,
		"longer range never gives a longer route")
