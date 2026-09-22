extends RefCounted
## GalaxyCoords: galactic light years <-> Godot world space.

func test_galactic_north_is_up(t: Object) -> void:
	t.eq(GalaxyCoords.to_world(Vector3(0, 0, 1)), Vector3.UP, "north galactic pole -> +Y")

func test_galactic_centre_is_plus_x(t: Object) -> void:
	t.eq(GalaxyCoords.to_world(Vector3(1, 0, 0)), Vector3.RIGHT, "galactic centre -> +X")

func test_round_trip(t: Object) -> void:
	var p := Vector3(1.5, -2.25, 7.0)
	t.eq(GalaxyCoords.to_galactic(GalaxyCoords.to_world(p)), p, "to_world then to_galactic")

func test_distances_preserved(t: Object) -> void:
	var a := Vector3(1, 2, 3)
	var b := Vector3(-4, 0.5, 2)
	t.ok(is_equal_approx(a.distance_to(b),
		GalaxyCoords.to_world(a).distance_to(GalaxyCoords.to_world(b))), "rotation keeps distances")

func test_right_handed(t: Object) -> void:
	var x := GalaxyCoords.to_world(Vector3(1, 0, 0))
	var y := GalaxyCoords.to_world(Vector3(0, 1, 0))
	var z := GalaxyCoords.to_world(Vector3(0, 0, 1))
	t.ok(x.cross(y).is_equal_approx(z), "x × y = z survives the conversion (no mirroring)")
