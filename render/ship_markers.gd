class_name ShipMarkers
extends Node3D
## Ships on the star map: a chevron per ship in its company's colour.
## Travelling ships move smoothly along their lanes (sim position + speed x
## the current day fraction); docked ships park around their star. Draws
## the selected ship's remaining route and a preview route (the path it
## would fly to the selected system). Reads the World, never writes it.

const CHEVRON_SHADER := preload("res://render/shaders/chevron.gdshader")
const ROUTE_COLOR := Color(1.0, 0.72, 0.28, 0.85)
const PREVIEW_COLOR := Color(0.45, 0.9, 1.0, 0.7)
## Radius (ly) of the parking circle around a star.
const PARK_RADIUS := 0.55

var world: World
var map: GalaxyMap
var selected_ship := -1
## System indices of a route to preview (empty = none).
var preview_path := PackedInt32Array()

var _chevrons: MultiMesh
var _route: MeshInstance3D
var _preview: MeshInstance3D
## Per chevron: ship id and world position this frame (for picking).
var _ids := PackedInt32Array()
var _points := PackedVector3Array()

func setup(w: World, m: GalaxyMap) -> void:
	world = w
	map = m
	_chevrons = MultiMesh.new()
	_chevrons.transform_format = MultiMesh.TRANSFORM_3D
	_chevrons.use_colors = true
	_chevrons.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_chevrons.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = CHEVRON_SHADER
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _chevrons
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_route = Ribbon.make_instance(3.0, 1.2)
	_preview = Ribbon.make_instance(2.5, 0.8)
	add_child(_route)
	add_child(_preview)

## Ship ids and screen positions of every chevron, for picking.
func screen_points(camera: Camera3D) -> Array:
	var out := []
	for i in _ids.size():
		if not camera.is_position_behind(_points[i]):
			out.append([_ids[i], camera.unproject_position(_points[i])])
	return out

## Where a ship is drawn now (world space).
func ship_position(ship_id: int) -> Vector3:
	var i := _ids.find(ship_id)
	return _points[i] if i >= 0 else Vector3.ZERO

func _process(_delta: float) -> void:
	if world == null:
		return
	var ships := world.fleet.ships
	if _chevrons.instance_count != ships.size():
		_chevrons.instance_count = ships.size()
	_ids.resize(ships.size())
	_points.resize(ships.size())
	var frac := Sim.day_fraction()
	var parked := {}  # system -> how many parked there so far
	for i in ships.size():
		var s := ships[i]
		var pos: Vector3
		var heading: Vector3
		if s.status == Ship.Status.TRAVELING:
			# A broken-down ship sits still until it is repaired.
			var ahead := 0.0 if s.broken_until > world.day else world.fleet.speed(s) * frac
			var at: Array = world.fleet.route_point(s, ahead)
			pos = GalaxyCoords.to_world(at[0])
			heading = GalaxyCoords.to_world(at[1])
		else:
			var k: int = parked.get(s.system, 0)
			parked[s.system] = k + 1
			var angle := k * 0.9 + 0.4
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * PARK_RADIUS
			pos = map.system_position(s.system) + offset
			heading = Vector3(-sin(angle), 0.0, cos(angle))
		_ids[i] = s.id
		_points[i] = pos
		_chevrons.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		_chevrons.set_instance_color(i, world.companies[s.company].color if s.company < world.companies.size() else Color.WHITE)
		_chevrons.set_instance_custom_data(i, Color(heading.x, heading.y, heading.z, 1.0 if s.id == selected_ship else 0.0))
	_draw_route()
	_draw_preview()

func _draw_route() -> void:
	var s := world.fleet.get_ship(selected_ship) if selected_ship >= 0 else null
	if s == null or s.status != Ship.Status.TRAVELING:
		_route.visible = false
		return
	var st := Ribbon.begin()
	var from := ship_position(s.id)
	var along := 0.0
	for k in range(s.leg + 1, s.route.size()):
		var to := map.system_position(s.route[k])
		Ribbon.add_segment(st, from, to, ROUTE_COLOR, along)
		along += from.distance_to(to)
		from = to
	_route.mesh = st.commit()
	_route.visible = true

func _draw_preview() -> void:
	if preview_path.size() < 2:
		_preview.visible = false
		return
	var st := Ribbon.begin()
	var along := 0.0
	for k in range(1, preview_path.size()):
		var a := map.system_position(preview_path[k - 1])
		var b := map.system_position(preview_path[k])
		Ribbon.add_segment(st, a, b, PREVIEW_COLOR, along)
		along += a.distance_to(b)
	_preview.mesh = st.commit()
	_preview.visible = true
