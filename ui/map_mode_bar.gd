class_name MapModeBar
extends HBoxContainer
## Map mode picker in the top-right corner: normal star colours; danger
## (lanes and stars coloured by the chance of a hit); or stars tinted by
## what the player knows of one good's price there (green cheap, white
## normal, red dear, grey unknown). P cycles through the modes.

## `commodity` is the price map's good (-1 = none); `danger` is on for the
## danger map.
signal mode_changed(commodity: int)

const FIRST_PRICE := 2  # items: stars, danger, then one per good

var commodity := -1
var danger := false

var _pick := OptionButton.new()

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -28
	offset_top = 28
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.add_item("Map: stars")
	_pick.add_item("Map: danger")
	for id in Sim.world.economy.commodity_ids:
		_pick.add_item("Price map: %s" % Defs.commodities[id].name)
	_pick.item_selected.connect(_select)
	add_child(_pick)

## Next mode (P key).
func cycle() -> void:
	_select((_pick.selected + 1) % _pick.item_count)

func _select(item: int) -> void:
	_pick.select(item)
	danger = item == 1
	commodity = item - FIRST_PRICE if item >= FIRST_PRICE else -1
	mode_changed.emit(commodity)

## Colour for a lane's chance of a hit per crossing: green safe, amber
## risky, red deadly.
static func danger_ramp(d: float) -> Color:
	var safe := Color(0.3, 0.85, 0.5, 0.35)
	var risky := Color(1.0, 0.75, 0.25, 0.7)
	var deadly := Color(1.0, 0.25, 0.25, 0.95)
	if d <= 0.005:
		return safe.lerp(risky, clampf((d - 0.001) / 0.004, 0.0, 1.0))
	return risky.lerp(deadly, clampf((d - 0.005) / 0.06, 0.0, 1.0))

## Colour for a price ratio (price / base).
static func ramp(ratio: float) -> Color:
	var cheap := Color(0.35, 0.95, 0.45)
	var normal := Color(0.92, 0.92, 0.96)
	var dear := Color(1.0, 0.35, 0.3)
	if ratio <= 1.0:
		return cheap.lerp(normal, clampf((ratio - 0.6) / 0.4, 0.0, 1.0))
	return normal.lerp(dear, clampf((ratio - 1.0) / 0.6, 0.0, 1.0))
