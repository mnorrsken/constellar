class_name Toast
extends VBoxContainer
## Short notices under the clock bar (arrivals, refusals). Each fades out
## after a few seconds.

const SHOW_SECONDS := 4.0

func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_top = 80
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	Events.notice.connect(show_notice)

func show_notice(text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	panel.add_child(label)
	add_child(panel)
	var tween := create_tween()
	tween.tween_interval(SHOW_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)
	while get_child_count() > 4:
		get_child(0).free()
