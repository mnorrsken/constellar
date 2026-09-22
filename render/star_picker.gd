class_name StarPicker
## Screen-space picking: which projected star is under the mouse. Stars are
## drawn by one MultiMesh, so there is nothing for physics raycasts to hit;
## instead every system is projected to the screen and the nearest wins.

## Marks a point as not on screen (behind the camera).
const OFF_SCREEN := Vector2(INF, INF)

## Index of the point nearest to `mouse` within `radius` pixels, or -1.
static func nearest(points: PackedVector2Array, mouse: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for i in points.size():
		var p := points[i]
		if p == OFF_SCREEN:
			continue
		var d := p.distance_squared_to(mouse)
		if d <= best_d:
			best_d = d
			best = i
	return best
