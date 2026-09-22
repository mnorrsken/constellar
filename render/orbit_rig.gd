class_name OrbitRig
extends RefCounted
## Camera maths for the star map: a camera orbiting a focus point on (or
## near) the galactic plane. Pure data, so it can be tested and smoothly
## interpolated (the camera node eases its view rig toward a target rig).
##
## World space as in GalaxyCoords: +Y is galactic north, the plane is XZ.

const MIN_DISTANCE := 1.5
const MAX_DISTANCE := 180.0
const MIN_PITCH := 4.0 * PI / 180.0
const MAX_PITCH := 88.0 * PI / 180.0
## The focus may not wander further than this from Sol.
const MAX_FOCUS_RADIUS := 75.0

var focus := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(35.0)
var distance := 60.0

func copy() -> OrbitRig:
	var r := OrbitRig.new()
	r.focus = focus
	r.yaw = yaw
	r.pitch = pitch
	r.distance = distance
	return r

func orbit(dyaw: float, dpitch: float) -> void:
	yaw = wrapf(yaw + dyaw, -PI, PI)
	pitch = clampf(pitch + dpitch, MIN_PITCH, MAX_PITCH)

func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)

## Moves the focus across the galactic plane, relative to the view direction.
## `right` and `forward` are fractions of the current distance.
func pan(right: float, forward: float) -> void:
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var f := Vector3(-sin(yaw), 0.0, -cos(yaw))
	set_focus(focus + (r * right + f * forward) * distance)

func set_focus(p: Vector3) -> void:
	focus = p.limit_length(MAX_FOCUS_RADIUS)

func camera_position() -> Vector3:
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	return focus + offset * distance

func camera_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, camera_position()).looking_at(focus, Vector3.UP)

## Moves this rig a fraction `t` (0..1) of the way to `target`. Distance is
## blended in log space so zooming feels even at every scale.
func lerp_to(target: OrbitRig, t: float) -> void:
	focus = focus.lerp(target.focus, t)
	yaw = lerp_angle(yaw, target.yaw, t)
	pitch = lerpf(pitch, target.pitch, t)
	distance = exp(lerpf(log(distance), log(target.distance), t))
