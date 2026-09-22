class_name GalaxyMap
extends Node3D
## The 3D star map view. Reads a Galaxy (never writes it) and draws:
## the polar grid on the galactic plane, starlanes, a drop line from every
## star to the plane (the Elite II depth cue), the stars themselves, name
## labels, and hover/selection rings. Multiple stars circle their system's
## centre so pairs separate when zoomed in (cosmetic, not to scale).

const STAR_SHADER := preload("res://render/shaders/star.gdshader")
const LANE_SHADER := preload("res://render/shaders/lane.gdshader")
const GRID_SHADER := preload("res://render/shaders/grid.gdshader")
const RING_SHADER := preload("res://render/shaders/ring.gdshader")

const LANE_COLOR := Color(0.25, 0.77, 0.85, 0.32)
## Lanes longer than this are drawn as "deep lanes" (needs a long-range hull).
@export var deep_lane_ly := 12.0
const DEEP_LANE_COLOR := Color(0.62, 0.45, 0.95, 0.22)
const HOVER_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const SELECT_COLOR := Color(1.0, 0.72, 0.28, 1.0)
## Radius (ly) of the stylised circle multiple stars move on.
const MULTI_RADIUS := 0.32
## Radians per second for that motion.
const MULTI_SPIN := 0.25

var galaxy: Galaxy
var hovered := -1
var selected := -1

var _stars: MultiMesh
## Per MultiMesh instance: [system index, orbit radius, start angle] for
## members of multiple systems; empty for single stars.
var _orbits: Array = []
## Per MultiMesh instance: its system and where it is drawn right now.
var _instance_system := PackedInt32Array()
var _instance_pos := PackedVector3Array()
var _labels: Array[Label3D] = []
var _label_ranges := PackedFloat32Array()
var _hover_ring: MeshInstance3D
var _select_ring: MeshInstance3D
var _time := 0.0

func build(g: Galaxy) -> void:
	galaxy = g
	for child in get_children():
		child.queue_free()
	_labels.clear()
	_orbits.clear()
	_build_grid()
	_build_lanes()
	_build_drop_lines()
	_build_stars()
	_build_labels()
	_hover_ring = _make_ring(HOVER_COLOR, 30.0, 0.0, 0.0)
	_select_ring = _make_ring(SELECT_COLOR, 40.0, 10.0, 0.8)

## World position of a system's centre.
func system_position(i: int) -> Vector3:
	return GalaxyCoords.to_world(galaxy.systems[i].position)

## Where every star is drawn this frame (members of multiple systems move),
## with the system each belongs to: use these for picking.
func star_positions() -> PackedVector3Array:
	return _instance_pos

func star_system(instance: int) -> int:
	return _instance_system[instance]

func set_hovered(i: int) -> void:
	hovered = i
	_place_ring(_hover_ring, i if i != selected else -1)

func set_selected(i: int) -> void:
	selected = i
	_place_ring(_select_ring, i)
	_place_ring(_hover_ring, hovered if hovered != selected else -1)

func _process(delta: float) -> void:
	if galaxy == null:
		return
	_time += delta
	_update_multiples()
	_update_labels()

# --- building ------------------------------------------------------------------

func _build_grid() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 140)
	var mat := ShaderMaterial.new()
	mat.shader = GRID_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Grid"
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_lanes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for lane in galaxy.lanes:
		var a := system_position(lane.a)
		var b := system_position(lane.b)
		var c := DEEP_LANE_COLOR if lane.length > deep_lane_ly else LANE_COLOR
		# Corners: (end, other end, side flag, uv). The side flag flips at the
		# far end because the shader measures direction toward the other end.
		var corners := [
			[a, b, -1.0, Vector2(0.0, -1.0)],
			[a, b, 1.0, Vector2(0.0, 1.0)],
			[b, a, -1.0, Vector2(lane.length, 1.0)],
			[b, a, 1.0, Vector2(lane.length, -1.0)],
		]
		for k in [0, 1, 2, 0, 2, 3]:
			var v: Array = corners[k]
			var other: Vector3 = v[1]
			st.set_color(c)
			st.set_uv(v[3])
			st.set_custom(0, Color(other.x, other.y, other.z, v[2]))
			st.add_vertex(v[0])
	var mat := ShaderMaterial.new()
	mat.shader = LANE_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Lanes"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_drop_lines() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for s in galaxy.systems:
		var top := system_position(s.index)
		var foot := Vector3(top.x, 0.0, top.z)
		var c := StarLook.color(s.primary().get("class", ""), s.primary().get("subclass"))
		# Stalks fade toward the plane; stars below it get fainter ones.
		c.a = 0.4 if top.y >= 0.0 else 0.22
		var foot_c := Color(c, c.a * 0.3)
		st.set_color(c)
		st.add_vertex(top)
		st.set_color(foot_c)
		st.add_vertex(foot)
		c.a *= 0.7
		var steps := 14
		for k in steps:
			var a0 := TAU * k / steps
			var a1 := TAU * (k + 1) / steps
			_line(st, foot + Vector3(cos(a0), 0, sin(a0)) * 0.3,
				foot + Vector3(cos(a1), 0, sin(a1)) * 0.3, c)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "DropLines"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _line(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(a)
	st.set_color(c)
	st.add_vertex(b)

func _build_stars() -> void:
	var count := 0
	for s in galaxy.systems:
		count += s.stars.size()
	_stars = MultiMesh.new()
	_stars.transform_format = MultiMesh.TRANSFORM_3D
	_stars.use_colors = true
	_stars.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_stars.mesh = quad
	_stars.instance_count = count
	_instance_system.resize(count)
	_instance_pos.resize(count)
	var i := 0
	for s in galaxy.systems:
		var centre := system_position(s.index)
		var total_mass := 0.0
		for star in s.stars:
			total_mass += float(star.get("mass", 1.0))
		for k in s.stars.size():
			var star: Dictionary = s.stars[k]
			var lum := float(star.get("luminosity", 1.0))
			_stars.set_instance_transform(i, Transform3D(Basis.IDENTITY, centre))
			_instance_system[i] = s.index
			_instance_pos[i] = centre
			_stars.set_instance_color(i, StarLook.color(star.get("class", ""), star.get("subclass")))
			_stars.set_instance_custom_data(i, Color(
				StarLook.size(lum), StarLook.brightness(lum), StarLook.min_pixels(lum), 0.0))
			if s.is_multiple():
				# Heavier stars sit nearer the middle, like a barycentre.
				var r := MULTI_RADIUS * (1.0 - float(star.get("mass", 1.0)) / total_mass)
				r *= s.stars.size() / float(s.stars.size() - 1)
				_orbits.append([s.index, r, TAU * k / s.stars.size()])
			else:
				_orbits.append([])
			i += 1
	var mat := ShaderMaterial.new()
	mat.shader = STAR_SHADER
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stars"
	mmi.multimesh = _stars
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_update_multiples()

func _build_labels() -> void:
	var font := Fonts.weight(Fonts.DISPLAY, 500)
	_label_ranges.resize(galaxy.size())
	for s in galaxy.systems:
		var lum := 0.0
		for star in s.stars:
			lum += float(star.get("luminosity", 0.0))
		var label := Label3D.new()
		label.text = s.name
		label.font = font
		label.font_size = 22
		label.outline_size = 8
		label.outline_modulate = Color(0.02, 0.03, 0.07, 0.85)
		label.modulate = Color(0.78, 0.86, 0.96)
		label.pixel_size = 0.0007
		label.fixed_size = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.double_sided = true
		label.offset = Vector2(0, -24)
		label.position = system_position(s.index)
		add_child(label)
		_labels.append(label)
		_label_ranges[s.index] = StarLook.label_range(lum) * (2.0 if s.id == "sol" else 1.0)

func _make_ring(color: Color, diameter: float, segments: float, spin: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("ring_color", color)
	mat.set_shader_parameter("diameter_px", diameter)
	mat.set_shader_parameter("segments", segments)
	mat.set_shader_parameter("spin", spin)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0
	add_child(mi)
	return mi

func _place_ring(ring: MeshInstance3D, i: int) -> void:
	ring.visible = i >= 0
	if i >= 0:
		ring.position = system_position(i)

# --- per frame -----------------------------------------------------------------

func _update_multiples() -> void:
	for i in _orbits.size():
		var o: Array = _orbits[i]
		if o.is_empty():
			continue
		var a: float = o[2] + _time * MULTI_SPIN
		var p := system_position(o[0]) + Vector3(cos(a), 0.0, sin(a)) * float(o[1])
		_instance_pos[i] = p
		_stars.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))

func _update_labels() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for i in _labels.size():
		var label := _labels[i]
		var d := eye.distance_to(label.position)
		var r := _label_ranges[i]
		var a := 1.0 - smoothstep(r * 0.75, r, d)
		if i == hovered or i == selected:
			a = 1.0
		label.visible = a > 0.01
		label.modulate.a = a
		label.outline_modulate.a = a * 0.85
