extends RefCounted
## Pure helpers behind the star map: StarLook, OrbitRig, StarPicker.

func test_star_colours_run_blue_to_red(t: Object) -> void:
	var o := StarLook.color("O", 5)
	var g := StarLook.color("G", 2)
	var m := StarLook.color("M", 5)
	t.ok(o.b > o.r, "O stars are blue")
	t.ok(m.r > m.b + 0.3, "M stars are red-orange")
	t.ok(g.r > g.b and g.b > m.b, "G sits between")

func test_subclass_blends_toward_next_class(t: Object) -> void:
	var g0 := StarLook.color("G", 0)
	var g9 := StarLook.color("G", 9)
	var k0 := StarLook.color("K", 0)
	t.ok(g9.b < g0.b and absf(g9.b - k0.b) < absf(g0.b - k0.b), "G9 is closer to K than G0 is")
	t.eq(StarLook.color("G", null), g0, "no subclass = class colour")

func test_unknown_class_falls_back(t: Object) -> void:
	t.eq(StarLook.color("X", 3), StarLook.FALLBACK, "unknown class")

func test_size_and_range_grow_with_luminosity(t: Object) -> void:
	t.ok(StarLook.size(100.0) > StarLook.size(1.0), "brighter is bigger")
	t.ok(StarLook.size(1.0) > StarLook.size(0.001), "dimmer is smaller")
	t.ok(StarLook.size(1e-6) >= 0.08 and StarLook.size(1e6) <= 0.5, "size clamped")
	t.ok(StarLook.label_range(50.0) > StarLook.label_range(0.001), "bright stars labelled from further")
	t.ok(StarLook.min_pixels(0.0) >= 5.0, "zero luminosity still visible")

func test_rig_camera_looks_at_focus(t: Object) -> void:
	var r := OrbitRig.new()
	r.focus = Vector3(3, 0, -4)
	r.distance = 20.0
	var xf := r.camera_transform()
	t.ok(is_equal_approx(xf.origin.distance_to(r.focus), 20.0), "camera at distance")
	var look := -xf.basis.z
	t.ok(look.is_equal_approx((r.focus - xf.origin).normalized()), "camera faces the focus")
	t.ok(xf.origin.y > 0.0, "positive pitch = above the plane")

func test_rig_clamps(t: Object) -> void:
	var r := OrbitRig.new()
	r.zoom(1000.0)
	t.eq(r.distance, OrbitRig.MAX_DISTANCE, "max zoom out")
	r.zoom(0.00001)
	t.eq(r.distance, OrbitRig.MIN_DISTANCE, "max zoom in")
	r.orbit(0.0, 10.0)
	t.eq(r.pitch, OrbitRig.MAX_PITCH, "pitch clamped high")
	r.orbit(0.0, -10.0)
	t.eq(r.pitch, OrbitRig.MIN_PITCH, "pitch clamped low")
	r.set_focus(Vector3(500, 0, 0))
	t.ok(is_equal_approx(r.focus.length(), OrbitRig.MAX_FOCUS_RADIUS), "focus kept near the map")

func test_rig_pan_follows_view(t: Object) -> void:
	var r := OrbitRig.new()
	r.yaw = 0.7
	var right := r.camera_transform().basis.x
	var before := r.focus
	r.pan(0.1, 0.0)
	var moved := r.focus - before
	t.ok(moved.dot(right) > 0.0, "pan right moves the focus to screen right")
	t.ok(is_zero_approx(moved.y), "pan stays in the galactic plane")

func test_rig_lerp(t: Object) -> void:
	var a := OrbitRig.new()
	var b := OrbitRig.new()
	b.focus = Vector3(10, 0, 5)
	b.distance = 5.0
	b.yaw = 2.0
	var c := a.copy()
	c.lerp_to(b, 1.0)
	t.ok(c.focus.is_equal_approx(b.focus) and is_equal_approx(c.distance, 5.0)
		and is_equal_approx(c.yaw, 2.0), "t = 1 reaches the target")
	var h := a.copy()
	h.lerp_to(b, 0.5)
	t.ok(h.distance < a.distance and h.distance > b.distance, "halfway zoom in between")

func test_picker_nearest_within_radius(t: Object) -> void:
	var pts := PackedVector2Array([Vector2(100, 100), Vector2(110, 100), StarPicker.OFF_SCREEN])
	t.eq(StarPicker.nearest(pts, Vector2(108, 101), 12.0), 1, "nearest point wins")
	t.eq(StarPicker.nearest(pts, Vector2(300, 300), 12.0), -1, "nothing within radius")
	t.eq(StarPicker.nearest(PackedVector2Array([StarPicker.OFF_SCREEN]), Vector2.ZERO, 1e9), -1,
		"off-screen points never picked")
