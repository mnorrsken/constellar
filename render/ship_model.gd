class_name ShipModel
## Builds a 3D model of a ship from its hull and fitted modules, out of
## primitive meshes: engines at the back, a nose or bridge at the front,
## and one bay per module slot in between, each showing what is fitted
## (container stacks, tanks, cabin rings with lit windows, a jump ring ...).
## Shapes come from the data: hulls.json "look" (length, beam, nose,
## engines, fins, paint) and modules.json "look" (shape, color).
##
## The ship lies along +Z (nose forward), centred on the origin. Pure view
## code: it reads definitions and never touches the sim.

const CRATE_COLORS := ["b5452f", "2f6db5", "3f8a4a", "c98a2e", "8a8f96", "6b3fa0", "2a8a8a"]
const ENGINE_GLOW := Color(0.45, 0.75, 1.0)
const WINDOW_GLOW := Color(1.0, 0.82, 0.5)

static var _materials: Dictionary = {}

## A new model: `accent` is the owner's colour (stripes). Its bounds are in
## the root's meta "size" (Vector3).
static func build(hull: Dictionary, modules: Array, module_defs: Dictionary, accent: Color) -> Node3D:
	var root := Node3D.new()
	var look: Dictionary = hull.get("look", {})
	var L := float(look.get("length", 3.0 + 1.3 * int(hull.get("slots", 3))))
	var B := float(look.get("beam", 1.8))
	var H := B * 0.7
	var paint := Color.html(str(look.get("paint", "8e9aa8")))
	var hull_mat := _metal(paint)
	var dark := _metal(Color(0.13, 0.14, 0.16), 0.4, 0.65)
	var rear := -L * 0.5
	var engine_len := L * 0.14
	var nose_len := L * 0.2
	var bay_start := rear + engine_len + L * 0.02
	var bay_end := L * 0.5 - nose_len - L * 0.02
	# The keel runs the whole length, through the bays.
	_box(root, Vector3(B * 0.28, H * 0.26, bay_end - bay_start + 0.2), dark, Vector3(0, 0, (bay_start + bay_end) * 0.5))
	_engines(root, look, B, H, rear, engine_len, hull_mat, dark, accent)
	_nose(root, str(look.get("nose", "block")), B, H, L * 0.5 - nose_len, nose_len, hull_mat, accent)
	if look.get("fins", false):
		for side in [-1.0, 1.0]:
			var fin := _prism(root, Vector3(L * 0.16, H * 0.9, 0.06), hull_mat,
				Vector3(side * B * 0.42, 0, rear + engine_len * 0.9))
			fin.rotation = Vector3(0, deg_to_rad(90), deg_to_rad(side * -70))
	var slots := modules.size()
	var seg := (bay_end - bay_start) / maxf(slots, 1)
	for i in slots:
		var z := bay_start + seg * (i + 0.5)
		var def: Dictionary = module_defs.get(modules[i], {})
		_module(root, def.get("look", {}), B, H, z, seg, i, dark)
		# A thin frame ring between bays reads as structure.
		if i > 0:
			_box(root, Vector3(B * 0.34, H * 0.34, 0.06), hull_mat, Vector3(0, 0, bay_start + seg * i))
	root.set_meta("size", Vector3(B * 1.3, H * 1.4, L * 1.15))
	return root

# --- sections ---------------------------------------------------------------------------

static func _engines(root: Node3D, look: Dictionary, B: float, H: float, rear: float, length: float,
		hull_mat: Material, dark: Material, accent: Color) -> void:
	var z := rear + length * 0.5
	_box(root, Vector3(B * 0.72, H * 0.72, length), hull_mat, Vector3(0, 0, z))
	_box(root, Vector3(B * 0.74, H * 0.08, length * 0.7), _accent(accent), Vector3(0, H * 0.3, z))
	var n := int(look.get("engines", 2))
	var r := minf(B * 0.5 / n, H * 0.3)
	for k in n:
		var x := (k - (n - 1) * 0.5) * (B * 0.7 / maxf(n, 1))
		var y := 0.0 if n < 4 else (H * 0.16 if k % 2 == 0 else -H * 0.16)
		var nozzle := _cylinder(root, r * 0.8, r, length * 0.5, dark, Vector3(x, y, rear - length * 0.15))
		nozzle.rotation.x = deg_to_rad(90)
		var glow := _cylinder(root, r * 0.72, r * 0.72, 0.02, _glow(ENGINE_GLOW, 4.0), Vector3(x, y, rear - length * 0.41))
		glow.rotation.x = deg_to_rad(90)
		var flame := _cylinder(root, 0.0, r * 0.6, r * 3.0, _glow(ENGINE_GLOW, 1.2, true), Vector3(x, y, rear - length * 0.42 - r * 1.5))
		flame.rotation.x = deg_to_rad(-90)

static func _nose(root: Node3D, kind: String, B: float, H: float, start: float, length: float,
		hull_mat: Material, accent: Color) -> void:
	var z := start + length * 0.5
	match kind:
		"wedge":
			var wedge := _prism(root, Vector3(B * 0.85, length * 1.3, H * 0.45), hull_mat, Vector3(0, 0, z + length * 0.1))
			wedge.rotation.x = deg_to_rad(90)
			_box(root, Vector3(B * 0.3, H * 0.12, length * 0.3), _glow(WINDOW_GLOW, 1.5), Vector3(0, H * 0.23, z - length * 0.1))
		"round":
			var s := _sphere(root, hull_mat, Vector3(0, 0, z))
			s.scale = Vector3(B * 0.62, H * 0.6, length * 1.6)
			_box(root, Vector3(B * 0.4, H * 0.08, length * 0.35), _glow(WINDOW_GLOW, 1.5), Vector3(0, H * 0.24, z + length * 0.15))
		_:
			_box(root, Vector3(B * 0.62, H * 0.56, length), hull_mat, Vector3(0, 0, z))
			_box(root, Vector3(B * 0.4, H * 0.3, length * 0.45), hull_mat, Vector3(0, H * 0.4, z - length * 0.15))
			_box(root, Vector3(B * 0.36, H * 0.07, 0.02), _glow(WINDOW_GLOW, 1.5), Vector3(0, H * 0.45, z + length * 0.08 + 0.01))
	_box(root, Vector3(B * 0.64, H * 0.05, length * 0.6), _accent(accent), Vector3(0, -H * 0.1, z))

## One module bay, centred at z, `seg` long.
static func _module(root: Node3D, look: Dictionary, B: float, H: float, z: float, seg: float, slot: int,
		dark: Material) -> void:
	var color := Color.html(str(look.get("color", "9aa4ae")))
	var d := seg * 0.86
	match look.get("shape", ""):
		"crates":
			var rng := RandomNumberGenerator.new()
			rng.seed = slot * 7919 + 11
			for side in [-1.0, 1.0]:
				for level in 2:
					var c := Color.html(CRATE_COLORS[rng.randi() % CRATE_COLORS.size()])
					_box(root, Vector3(B * 0.34, H * 0.38, d), _paint(c), Vector3(side * B * 0.3, (level - 0.5) * H * 0.4, z))
		"hopper":
			var wall := _metal(color.darkened(0.2), 0.5, 0.6)
			_box(root, Vector3(B * 0.95, H * 0.08, d), wall, Vector3(0, -H * 0.3, z))
			for side in [-1.0, 1.0]:
				_box(root, Vector3(B * 0.06, H * 0.6, d), wall, Vector3(side * B * 0.46, 0, z))
			_box(root, Vector3(B * 0.86, H * 0.4, d * 0.96), _paint(color.darkened(0.45), 0.95), Vector3(0, -H * 0.08, z))
		"reefer":
			_box(root, Vector3(B * 0.9, H * 0.78, d), _paint(color, 0.4), Vector3(0, 0, z))
			for side in [-1.0, 1.0]:
				_box(root, Vector3(0.02, H * 0.06, d * 0.9), _glow(Color(0.4, 0.9, 1.0), 2.0), Vector3(side * B * 0.455, H * 0.2, z))
		"tanks":
			for side in [-1.0, 1.0]:
				var t := _capsule(root, H * 0.34, d, _metal(color, 0.7, 0.3), Vector3(side * B * 0.28, 0, z))
				t.rotation.x = deg_to_rad(90)
				var band := _cylinder(root, H * 0.36, H * 0.36, d * 0.08, dark, Vector3(side * B * 0.28, 0, z))
				band.rotation.x = deg_to_rad(90)
		"vault":
			_box(root, Vector3(B * 0.6, H * 0.58, d * 0.8), _metal(color, 0.6, 0.45), Vector3(0, 0, z))
			for corner in [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(-1, 1, -1), Vector3(1, 1, -1)]:
				_box(root, Vector3(0.07, 0.07, 0.07), _glow(Color(1.0, 0.7, 0.25), 3.0),
					Vector3(corner.x * B * 0.3, corner.y * H * 0.29, z + corner.z * d * 0.4))
		"ring":
			var ring := _cylinder(root, B * 0.5, B * 0.5, d * 0.8, _metal(color, 0.4, 0.5), Vector3(0, 0, z))
			ring.rotation.x = deg_to_rad(90)
			for k in [-1.0, 1.0]:
				var band := _cylinder(root, B * 0.505, B * 0.505, d * 0.1, _glow(WINDOW_GLOW, 1.6), Vector3(0, 0, z + k * d * 0.2))
				band.rotation.x = deg_to_rad(90)
		"pods":
			for side in [-1.0, 1.0]:
				var pod := _capsule(root, H * 0.28, d * 0.95, _paint(color, 0.35), Vector3(side * B * 0.3, H * 0.05, z))
				pod.rotation.x = deg_to_rad(90)
				_box(root, Vector3(0.02, H * 0.08, d * 0.6), _glow(Color(1.0, 0.85, 0.45), 2.0), Vector3(side * (B * 0.3 + H * 0.28), H * 0.08, z))
		"mailpod":
			_box(root, Vector3(B * 0.34, H * 0.34, d * 0.6), _paint(color, 0.5), Vector3(0, H * 0.3, z))
			_cylinder(root, 0.02, 0.02, H * 0.8, dark, Vector3(0, H * 0.85, z))
			_sphere(root, _glow(Color(1.0, 0.3, 0.3), 3.0), Vector3(0, H * 1.25, z)).scale = Vector3.ONE * 0.08
		"plates":
			for side in [-1.0, 1.0]:
				_box(root, Vector3(B * 0.08, H * 0.9, d), _metal(color, 0.7, 0.5), Vector3(side * B * 0.46, 0, z))
			_box(root, Vector3(B * 0.84, H * 0.08, d), _metal(color, 0.7, 0.5), Vector3(0, H * 0.42, z))
		"boosters":
			for side in [-1.0, 1.0]:
				var nac := _capsule(root, H * 0.17, d, _metal(Color(0.6, 0.64, 0.7)), Vector3(side * B * 0.42, -H * 0.1, z))
				nac.rotation.x = deg_to_rad(90)
				var g := _cylinder(root, H * 0.13, H * 0.13, 0.02, _glow(ENGINE_GLOW, 4.0), Vector3(side * B * 0.42, -H * 0.1, z - d * 0.5))
				g.rotation.x = deg_to_rad(90)
		"jumpring":
			var torus := TorusMesh.new()
			torus.inner_radius = B * 0.42
			torus.outer_radius = B * 0.52
			var ring := _mesh(root, torus, _glow(Color(0.3, 0.9, 1.0), 2.5), Vector3(0, 0, z))
			ring.rotation.x = deg_to_rad(90)
			for k in 4:
				var vane := _box(root, Vector3(0.05, B * 0.3, d * 0.3), dark, Vector3(0, 0, z))
				vane.rotation.z = TAU * k / 4.0
				vane.position += Vector3(cos(TAU * k / 4.0 + PI / 2), sin(TAU * k / 4.0 + PI / 2), 0) * B * 0.3
		"dish":
			_cylinder(root, 0.03, 0.03, H * 0.7, dark, Vector3(0, H * 0.5, z))
			var dish := _cylinder(root, H * 0.4, 0.05, H * 0.14, _metal(Color(0.85, 0.87, 0.9), 0.5, 0.3), Vector3(0, H * 0.9, z))
			dish.rotation.x = deg_to_rad(-35)
			_sphere(root, _glow(Color(0.5, 1.0, 0.6), 2.5), Vector3(0, H * 1.0, z + 0.05)).scale = Vector3.ONE * 0.06
		_:
			_box(root, Vector3(B * 0.6, H * 0.6, d), dark, Vector3(0, 0, z))

# --- primitives and materials ------------------------------------------------------------

static func _mesh(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

static func _box(root: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(root, m, mat, pos)

static func _prism(root: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _mesh(root, m, mat, pos)

## Axis along Y until rotated.
static func _cylinder(root: Node3D, top: float, bottom: float, height: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 24
	m.rings = 1
	return _mesh(root, m, mat, pos)

static func _capsule(root: Node3D, radius: float, height: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 24
	m.rings = 6
	return _mesh(root, m, mat, pos)

## A unit sphere (scale it).
static func _sphere(root: Node3D, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 24
	m.rings = 12
	return _mesh(root, m, mat, pos)

static func _metal(c: Color, metallic := 0.55, roughness := 0.45) -> StandardMaterial3D:
	var key := "metal:%s:%s:%s" % [c.to_html(), metallic, roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = roughness
		m.metallic_specular = 0.6
		_materials[key] = m
	return _materials[key]

static func _paint(c: Color, roughness := 0.6) -> StandardMaterial3D:
	return _metal(c, 0.15, roughness)

static func _accent(c: Color) -> StandardMaterial3D:
	var key := "accent:" + c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.35
		m.roughness = 0.4
		_materials[key] = m
	return _materials[key]

## Self-lit (engines, windows, lights); `soft` is see-through and additive
## (the engine flame).
static func _glow(c: Color, energy: float, soft := false) -> StandardMaterial3D:
	var key := "glow:%s:%s:%s" % [c.to_html(), energy, soft]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		if soft:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(c, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			# Emission above 1 is what makes the viewer's glow bloom.
			m.albedo_color = Color.BLACK
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = energy
		_materials[key] = m
	return _materials[key]
