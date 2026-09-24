class_name Motion
## Small UI animations: panels ease in when they open.

const SECONDS := 0.18

## Fades a panel in and grows it from 96% to full size around its centre.
static func pop_in(c: Control) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.96, 0.96)
	# Wait a frame so the panel has its size before picking the pivot.
	(func():
		c.pivot_offset = c.size * 0.5
		var t := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_property(c, "modulate:a", 1.0, SECONDS)
		t.tween_property(c, "scale", Vector2.ONE, SECONDS)).call_deferred()

## Fades a side panel in (when it was hidden).
static func fade_in(c: Control) -> void:
	c.modulate.a = 0.0
	c.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) \
		.tween_property(c, "modulate:a", 1.0, SECONDS)
