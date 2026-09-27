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

## Sizes a centred panel's scrolling part so the whole panel fits the
## screen (with `margin` above and below; longer content scrolls), then
## centres it (see center).
static func fit_screen(panel: Control, scroll: ScrollContainer, content: Control, margin := 24.0) -> void:
	var others := panel.get_combined_minimum_size().y - scroll.custom_minimum_size.y
	var room := panel.get_viewport_rect().size.y - 2.0 * margin - others
	scroll.custom_minimum_size.y = maxf(minf(content.get_combined_minimum_size().y, room), LEAST)
	center(panel)

## Shrinks a centred panel (anchored at the middle, growing both ways) back
## to its content and puts it back in the middle of the screen, never past
## the top-left corner. reset_size() alone keeps the top-left corner, and
## the next growth goes both ways, so a panel that refreshes while the game
## runs would creep up and to the left off the screen.
static func center(panel: Control) -> void:
	panel.reset_size()
	var screen := panel.get_viewport_rect().size
	panel.position = ((screen - panel.size) * 0.5).max(Vector2.ZERO).round()
