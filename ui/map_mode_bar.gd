class_name MapModeBar
extends HBoxContainer
## Map mode picker in the top-right corner: normal star colours, or stars tinted
## by what the player knows of one good's price there (green cheap, white
## normal, red dear, grey unknown). P cycles through the goods.

signal mode_changed(commodity: int)

var commodity := -1

var _pick := OptionButton.new()

func _ready() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -28
	offset_top = 28
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pick.focus_mode = Control.FOCUS_NONE
	_pick.add_item("Map: stars")
	for id in Sim.world.economy.commodity_ids:
		_pick.add_item("Price map: %s" % Defs.commodities[id].name)
	_pick.item_selected.connect(func(i): _select(i - 1))
	add_child(_pick)

## Next mode (P key).
func cycle() -> void:
	var n := Sim.world.economy.commodity_ids.size()
	_select(commodity + 1 if commodity + 1 < n else -1)

func _select(c: int) -> void:
	commodity = c
	_pick.select(c + 1)
	mode_changed.emit(c)

## Colour for a price ratio (price / base).
static func ramp(ratio: float) -> Color:
	var cheap := Color(0.35, 0.95, 0.45)
	var normal := Color(0.92, 0.92, 0.96)
	var dear := Color(1.0, 0.35, 0.3)
	if ratio <= 1.0:
		return cheap.lerp(normal, clampf((ratio - 0.6) / 0.4, 0.0, 1.0))
	return normal.lerp(dear, clampf((ratio - 1.0) / 0.6, 0.0, 1.0))
