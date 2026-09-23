extends Node3D
## Main scene: the star map. Wires the map view, camera, picking and UI.

const PICK_RADIUS_PX := 16.0

@onready var map: GalaxyMap = $GalaxyMap
@onready var camera: MapCamera = $MapCamera
@onready var tooltip: StarTooltip = $UI/Tooltip
@onready var debug_overlay: DebugOverlay = $UI/DebugOverlay
@onready var panel: SystemPanel = $UI/SystemPanel
@onready var system_view: SystemView = $UI/SystemView
@onready var market_panel: MarketPanel = $UI/MarketPanel

## Market panel wanted open (it follows the selection while on).
var _market_open := false

## Last mouse position from motion events, in the same space as clicks and
## Camera3D.unproject_position. OFF_SCREEN while the mouse is outside.
var _mouse := StarPicker.OFF_SCREEN

func _ready() -> void:
	map.build(Sim.galaxy)
	debug_overlay.map = map
	debug_overlay.camera = camera
	camera.clicked.connect(_on_clicked)
	camera.double_clicked.connect(_on_double_clicked)
	panel.view_requested.connect(open_system_view)
	panel.market_requested.connect(toggle_market)
	system_view.closed.connect(func(): camera.input_enabled = true)

func _process(_delta: float) -> void:
	# Re-pick every frame: the camera may be moving under a still mouse.
	var i := pick(_mouse) if _mouse != StarPicker.OFF_SCREEN and not system_view.visible else -1
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
	select(pick(screen_pos))

func _on_double_clicked(screen_pos: Vector2) -> void:
	var i := pick(screen_pos)
	if i >= 0:
		select(i)
		open_system_view()

## Selects a system (-1 = none): ring on the map, card on the right, and the
## camera flies there.
func select(i: int) -> void:
	map.set_selected(i)
	if i >= 0:
		camera.fly_to(map.system_position(i))
		panel.show_system(map.galaxy.systems[i])
		if _market_open:
			market_panel.show_system(map.galaxy.systems[i])
	else:
		panel.visible = false
		market_panel.visible = false

func toggle_market() -> void:
	_market_open = not _market_open
	if _market_open and map.selected >= 0:
		market_panel.show_system(map.galaxy.systems[map.selected])
	else:
		market_panel.visible = false

func open_system_view() -> void:
	if map.selected < 0:
		return
	tooltip.visible = false
	camera.input_enabled = false
	system_view.open(map.galaxy.systems[map.selected])

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_ESCAPE:
			if system_view.visible:
				system_view.close_view()
			else:
				select(-1)
		KEY_ENTER, KEY_KP_ENTER:
			if not system_view.visible:
				open_system_view()
		KEY_M:
			if not system_view.visible:
				toggle_market()
		KEY_SPACE:
			Sim.toggle_pause()
		KEY_1, KEY_2, KEY_3, KEY_4:
			Sim.set_speed(k.physical_keycode - KEY_0)
