class_name ShipViewer
extends SubViewportContainer
## A small 3D window with a ship model turning slowly under studio lights
## (ShipModel). Drag to turn it by hand. show_ship() follows a real ship
## (rebuilt when its fit changes); show_fit() shows any hull and fit, for
## shipyard previews. Its own 3D world, so it never sees the star map.

const TURN_SPEED := 0.35  # radians per second
const TILT := -0.12

var _viewport := SubViewport.new()
var _pivot := Node3D.new()
var _camera := Camera3D.new()
var _model: Node3D
var _key := ""
var _dragging := false

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(240, 120)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	# Warm key light from the front, cool fill from below, a rim from behind.
	for spec in [[Vector3(-35, 40, 0), Color(1.0, 0.94, 0.85), 1.6],
			[Vector3(25, -120, 0), Color(0.5, 0.65, 1.0), 0.6],
			[Vector3(-20, 170, 0), Color(0.6, 0.85, 1.0), 1.0]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		_viewport.add_child(light)
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_viewport.add_child(_pivot)
	_pivot.rotation = Vector3(TILT, 0.8, 0)

## Shows a ship as it is fitted now (no-op if nothing changed).
func show_ship(s: Ship) -> void:
	if s == null:
		clear()
		return
	show_fit(s.hull, Array(s.modules), Sim.world.companies[s.company].color)

## Shows a hull with the given modules (a preview).
func show_fit(hull_id: String, modules: Array, accent := Color(0.98, 0.72, 0.3)) -> void:
	var key := "%s|%s|%s" % [hull_id, ",".join(PackedStringArray(modules)), accent.to_html()]
	if key == _key:
		return
	_key = key
	if _model:
		_model.queue_free()
	_model = ShipModel.build(Defs.world_content.hulls[hull_id], modules, Defs.world_content.modules, accent)
	_pivot.add_child(_model)
	# Frame the whole ship, whichever way it faces.
	var size: Vector3 = _model.get_meta("size")
	var reach := maxf(size.z, size.x) * 0.5
	# (look_at_from_position works before the viewer is in the tree.)
	_camera.look_at_from_position(Vector3(0.0, 0.5, 1.0).normalized() * reach * 2.35, Vector3.ZERO)

func clear() -> void:
	_key = ""
	if _model:
		_model.queue_free()
		_model = null

func _process(delta: float) -> void:
	if _model and not _dragging and is_visible_in_tree():
		_pivot.rotation.y += TURN_SPEED * delta

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		accept_event()
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		_pivot.rotation.y += mm.relative.x * 0.01
		_pivot.rotation.x = clampf(_pivot.rotation.x + mm.relative.y * 0.005, -0.8, 0.5)
		accept_event()
