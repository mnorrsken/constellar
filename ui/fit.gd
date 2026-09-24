class_name Fit
## Keeps side panels out of each other's way: a panel whose content can
## grow puts it in a ScrollContainer, and cap() sizes that so the whole
## panel ends above `bottom` (a screen y, e.g. the top of the fleet card).
## Longer content scrolls instead of running under the next panel.

const LEAST := 80.0

static func cap(panel: Control, scroll: ScrollContainer, content: Control, bottom: float) -> void:
	# Everything in the panel except the scrolling part.
	var others := panel.get_combined_minimum_size().y - scroll.custom_minimum_size.y
	var room := bottom - panel.global_position.y - others
	scroll.custom_minimum_size.y = maxf(minf(content.get_combined_minimum_size().y, room), LEAST)
