extends Node3D
## Main scene: the star map. Wires the map view, camera, picking and UI.

const PICK_RADIUS_PX := 16.0

@onready var map: GalaxyMap = $GalaxyMap
@onready var camera: MapCamera = $MapCamera
@onready var tooltip: StarTooltip = $UI/Tooltip
@onready var debug_overlay: DebugOverlay = $UI/DebugOverlay

## Last mouse position from motion events, in the same space as clicks and
## Camera3D.unproject_position. OFF_SCREEN while the mouse is outside.
var _mouse := StarPicker.OFF_SCREEN

func _ready() -> void:
	map.build(Sim.galaxy)
	debug_overlay.map = map
	debug_overlay.camera = camera
	camera.clicked.connect(_on_clicked)

func _process(_delta: float) -> void:
	# Re-pick every frame: the camera may be moving under a still mouse.
	var i := pick(_mouse) if _mouse != StarPicker.OFF_SCREEN else -1
	if i != map.hovered:
		map.set_hovered(i)
	if i >= 0:
		tooltip.show_system(map.galaxy, i, _mouse)
	else:
		tooltip.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = (event as InputEventMouse).position

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse = StarPicker.OFF_SCREEN

## Index of the system under a screen position, or -1. Tests every star
## where it is drawn, so each member of a multiple system can be clicked.
func pick(screen_pos: Vector2) -> int:
	var stars := map.star_positions()
	var points := PackedVector2Array()
	points.resize(stars.size())
	for i in stars.size():
		points[i] = StarPicker.OFF_SCREEN if camera.is_position_behind(stars[i]) \
			else camera.unproject_position(stars[i])
	var hit := StarPicker.nearest(points, screen_pos, PICK_RADIUS_PX)
	return map.star_system(hit) if hit >= 0 else -1

func _on_clicked(screen_pos: Vector2) -> void:
	var i := pick(screen_pos)
	map.set_selected(i)
	if i >= 0:
		camera.fly_to(map.system_position(i))

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		map.set_selected(-1)
