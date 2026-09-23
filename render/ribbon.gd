class_name Ribbon
## Builds screen-width line ribbons for the lane shader: each segment is a
## quad whose vertices carry their own end in VERTEX and the other end in
## CUSTOM0 (the shader widens it in screen space). Used for starlanes and
## ship routes.

const SHADER := preload("res://render/shaders/lane.gdshader")

## A SurfaceTool ready for add_segment().
static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	return st

## One segment a -> b. `along` is the distance (ly) at `a`, so dashes flow on
## across joined segments.
static func add_segment(st: SurfaceTool, a: Vector3, b: Vector3, color: Color, along := 0.0) -> void:
	var length := a.distance_to(b)
	# Corners: (end, other end, side flag, uv). The side flag flips at the far
	# end because the shader measures direction toward the other end.
	var corners := [
		[a, b, -1.0, Vector2(along, -1.0)],
		[a, b, 1.0, Vector2(along, 1.0)],
		[b, a, -1.0, Vector2(along + length, 1.0)],
		[b, a, 1.0, Vector2(along + length, -1.0)],
	]
	for k in [0, 1, 2, 0, 2, 3]:
		var v: Array = corners[k]
		var other: Vector3 = v[1]
		st.set_color(color)
		st.set_uv(v[3])
		st.set_custom(0, Color(other.x, other.y, other.z, v[2]))
		st.add_vertex(v[0])

## A mesh instance using the lane shader at the given width.
static func make_instance(width_px: float, flow_speed := 0.5) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("width_px", width_px)
	mat.set_shader_parameter("flow_speed", flow_speed)
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
