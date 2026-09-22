class_name Fonts
## The game's fonts (OFL, see assets/fonts/) and weight variants of them.

const DISPLAY := preload("res://assets/fonts/Exo2.ttf")
const BODY := preload("res://assets/fonts/Inter.ttf")
const MONO := preload("res://assets/fonts/JetBrainsMono.ttf")

## A variable font at a given weight (100–900), with optional extra spacing
## between letters in pixels.
static func weight(base: Font, wght: int, letter_spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	f.variation_opentype = {tag: wght}
	f.spacing_glyph = letter_spacing
	return f
