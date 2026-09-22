class_name DebugOverlay
extends Control
## F1 debug view: every on-screen system's id and galactic coordinates (ly),
## plus camera state and FPS. Keep this working for the life of the project —
## when something on the map looks wrong, check coordinates first (plan §5).

const FONT := Fonts.MONO
const TEXT := Color(0.55, 1.0, 0.6, 0.9)

var map: GalaxyMap
var camera: MapCamera

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_F1:
		visible = not visible

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	if map == null or map.galaxy == null or camera == null:
		return
	for s in map.galaxy.systems:
		var world := map.system_position(s.index)
		if camera.is_position_behind(world):
			continue
		var p := camera.unproject_position(world)
		var g := s.position
		draw_string(FONT, p + Vector2(8, 14), "%s  (%.1f, %.1f, %.1f)" % [s.id, g.x, g.y, g.z],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, TEXT)
	var r := camera.rig
	var info := "FPS %d   focus (%.1f, %.1f, %.1f)   dist %.1f ly   yaw %.0f°   pitch %.0f°   hovered %s" % [
		Engine.get_frames_per_second(), r.focus.x, r.focus.y, r.focus.z, r.distance,
		rad_to_deg(r.yaw), rad_to_deg(r.pitch),
		map.galaxy.systems[map.hovered].id if map.hovered >= 0 else "-"]
	var bottom := get_viewport_rect().size.y
	draw_rect(Rect2(8, bottom - 30, 900, 22), Color(0, 0, 0, 0.6))
	draw_string(FONT, Vector2(14, bottom - 14), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, TEXT)
