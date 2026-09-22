class_name StarLook
## How a star looks on the map, from its data: colour from spectral class,
## size and brightness from luminosity. Pure functions, no nodes.

## Colour at subclass 0 of each class. Subclasses blend toward the next class
## in NEXT_CLASS, so a G8 is already a little orange.
const CLASS_COLORS := {
	"O": Color("8fa8ff"),
	"B": Color("a9bdff"),
	"A": Color("cfdcff"),
	"F": Color("f6f4ff"),
	"G": Color("ffecbf"),
	"K": Color("ffc07a"),
	"M": Color("ff9160"),
	"D": Color("dfe8ff"),  # white dwarf
	"L": Color("d0603c"),  # brown dwarfs
	"T": Color("b24a6a"),
	"Y": Color("8a3f7a"),
}
const NEXT_CLASS := {"O": "B", "B": "A", "A": "F", "F": "G", "G": "K", "K": "M", "M": "M9"}
const M9_COLOR := Color("ff6e4a")
const FALLBACK := Color(0.9, 0.9, 0.9)

static func color(cls: String, subclass: Variant = null) -> Color:
	if not CLASS_COLORS.has(cls):
		return FALLBACK
	var c: Color = CLASS_COLORS[cls]
	if subclass == null or not NEXT_CLASS.has(cls):
		return c
	var nxt: String = NEXT_CLASS[cls]
	var to: Color = M9_COLOR if nxt == "M9" else CLASS_COLORS[nxt]
	return c.lerp(to, clampf(float(subclass) / 10.0, 0.0, 1.0))

## Diameter of the star's glow in light years (world units) when zoomed in.
static func size(luminosity: float) -> float:
	return clampf(0.3 + 0.08 * _log10(luminosity), 0.08, 0.5)

## HDR intensity of the core; values above 1 feed the glow (bloom).
static func brightness(luminosity: float) -> float:
	return clampf(1.4 + 0.25 * _log10(luminosity), 0.9, 2.0)

## Smallest on-screen diameter in pixels, so faint stars stay visible when the
## whole map is in view.
static func min_pixels(luminosity: float) -> float:
	return clampf(19.0 + 3.0 * _log10(luminosity), 10.0, 28.0)

## Camera distance (ly) within which the system's name label is shown.
## Faint red dwarfs only show up close; bright stars from across the map.
static func label_range(luminosity: float) -> float:
	var rank := clampf((_log10(luminosity) + 3.0) / 5.0, 0.0, 1.0)
	return lerpf(14.0, 180.0, rank)

static func _log10(x: float) -> float:
	return log(maxf(x, 1e-9)) / log(10.0)
