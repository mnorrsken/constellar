extends RefCounted
## Galaxy graph + pathfinding on small hand-made maps.

## A triangle plus one isolated system:
##   A(0,0,0) -5- B(4,3,0) -5- C(8,0,0), and a direct A–C lane of 8 ly.
##   D(0,20,0) has no lanes.
func _triangle() -> Galaxy:
	var g := Galaxy.new()
	g.add_system("a", "A", Vector3(0, 0, 0))
	g.add_system("b", "B", Vector3(4, 3, 0))
	g.add_system("c", "C", Vector3(8, 0, 0))
	g.add_system("d", "D", Vector3(0, 20, 0))
	g.add_lane(0, 1)
	g.add_lane(1, 2)
	g.add_lane(0, 2)
	return g

func test_lane_length_from_positions(t: Object) -> void:
	var g := _triangle()
	t.ok(is_equal_approx(g.lane_between(0, 1).length, 5.0), "A–B lane is 5 ly")
	t.ok(is_equal_approx(g.lane_between(2, 0).length, 8.0), "lanes work both ways")

func test_duplicate_and_self_lanes_ignored(t: Object) -> void:
	var g := _triangle()
	t.eq(g.add_lane(1, 0), null, "duplicate lane rejected")
	t.eq(g.add_lane(2, 2), null, "self lane rejected")
	t.eq(g.lanes.size(), 3, "lane count unchanged")

func test_index_lookup(t: Object) -> void:
	var g := _triangle()
	t.eq(g.index_of("c"), 2, "index of c")
	t.eq(g.index_of("nope"), -1, "unknown id")
	t.eq(g.system_by_id("b").name, "B", "system by id")

func test_shortest_path_takes_direct_lane(t: Object) -> void:
	var g := _triangle()
	t.eq(g.find_path(0, 2), PackedInt32Array([0, 2]), "A→C direct when range allows")
	t.ok(is_equal_approx(g.path_length(g.find_path(0, 2)), 8.0), "path length 8 ly")

func test_short_range_routes_around_long_lane(t: Object) -> void:
	var g := _triangle()
	t.eq(g.find_path(0, 2, 6.0), PackedInt32Array([0, 1, 2]), "6 ly range goes via B")

func test_too_short_range_has_no_path(t: Object) -> void:
	var g := _triangle()
	t.eq(g.find_path(0, 2, 4.0).size(), 0, "4 ly range cannot leave A")

func test_unreachable_and_same_system(t: Object) -> void:
	var g := _triangle()
	t.eq(g.find_path(0, 3).size(), 0, "no lane to D")
	t.eq(g.find_path(1, 1), PackedInt32Array([1]), "path to itself")

func test_connectivity(t: Object) -> void:
	var g := _triangle()
	t.ok(not g.is_fully_connected(), "D is cut off")
	g.add_lane(3, 0)
	t.ok(g.is_fully_connected(), "connected after D–A lane")
	t.ok(not g.is_fully_connected(10.0), "D–A lane (20 ly) is too long for 10 ly range")

func test_from_dict(t: Object) -> void:
	var g := Galaxy.from_dict({
		"systems": [
			{"id": "x", "name": "X", "pos": [0, 0, 0], "stars": [{"name": "X", "class": "G"}]},
			{"id": "y", "name": "Y", "pos": [3, 4, 0], "stars": []},
		],
		"lanes": [["x", "y"]],
	})
	t.eq(g.size(), 2, "two systems")
	t.eq(g.lanes.size(), 1, "one lane")
	t.ok(is_equal_approx(g.lanes[0].length, 5.0), "lane length from pos")
	t.eq(g.systems[0].primary().get("class"), "G", "stars kept")
