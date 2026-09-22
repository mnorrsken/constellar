class_name MapCamera
extends Camera3D
## Orbit camera for the star map. Input edits a target OrbitRig; the view
## rig eases toward it every frame, so zoom, pan and fly-to are smooth.
##
## Mouse: left-drag orbit, right/middle-drag pan, wheel zoom, click = select.
## Trackpad: two-finger swipe zooms (up/down) and orbits (left/right),
## pinch zooms. Keys: WASD/arrows pan, Q/E orbit, R/F tilt, -/= zoom,
## Home back to Sol.

## Emitted for a left click that was not a drag.
signal clicked(screen_pos: Vector2)

const DRAG_THRESHOLD_PX := 5.0
const EASE := 7.0  # higher = snappier
const HOME_DISTANCE := 100.0

var rig := OrbitRig.new()
var _view := OrbitRig.new()
var _left_down := false
var _dragging := false
var _press_pos := Vector2.ZERO

func _ready() -> void:
	far = 1000.0
	near = 0.05
	fov = 55.0
	go_home(true)

## Back to the overview centred on Sol. `instant` skips the easing.
func go_home(instant := false) -> void:
	rig.set_focus(Vector3.ZERO)
	rig.distance = HOME_DISTANCE
	rig.pitch = deg_to_rad(32.0)
	rig.yaw = deg_to_rad(-25.0)
	if instant:
		_view = rig.copy()
		transform = _view.camera_transform()

## Moves the focus to a point, zooming in to at most `max_distance`.
func fly_to(point: Vector3, max_distance := 16.0) -> void:
	rig.set_focus(point)
	rig.distance = minf(rig.distance, max_distance)

func _process(delta: float) -> void:
	_keyboard(delta)
	_view.lerp_to(rig, 1.0 - exp(-EASE * delta))
	transform = _view.camera_transform()

func _keyboard(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		pan.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		pan.y += 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		pan.y -= 1
	if pan != Vector2.ZERO:
		rig.pan(pan.x * delta * 0.8, pan.y * delta * 0.8)
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		turn += 1
	if Input.is_physical_key_pressed(KEY_E):
		turn -= 1
	var tilt := 0.0
	if Input.is_physical_key_pressed(KEY_R):
		tilt += 1
	if Input.is_physical_key_pressed(KEY_F):
		tilt -= 1
	if turn != 0.0 or tilt != 0.0:
		rig.orbit(turn * delta * 1.4, tilt * delta * 1.0)
	if Input.is_physical_key_pressed(KEY_MINUS):
		rig.zoom(1.0 + delta * 1.5)
	if Input.is_physical_key_pressed(KEY_EQUAL):
		rig.zoom(1.0 / (1.0 + delta * 1.5))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_down = true
					_dragging = false
					_press_pos = mb.position
				else:
					if _left_down and not _dragging:
						clicked.emit(mb.position)
					_left_down = false
					_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					rig.zoom(0.87)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					rig.zoom(1.0 / 0.87)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _left_down and not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			rig.orbit(-mm.relative.x * 0.006, mm.relative.y * 0.005)
		elif mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			rig.pan(-mm.relative.x * 0.0012, mm.relative.y * 0.0012)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		rig.zoom(exp(pg.delta.y * 0.06))
		rig.orbit(-pg.delta.x * 0.02, 0.0)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		rig.zoom(1.0 / mg.factor)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.physical_keycode == KEY_HOME:
			go_home()
