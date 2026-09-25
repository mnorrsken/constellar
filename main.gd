extends Node3D
## Main scene: the star map. Wires the map view, ships, camera, picking and UI.

const PICK_RADIUS_PX := 16.0

@onready var map: GalaxyMap = $GalaxyMap
@onready var markers: ShipMarkers = $ShipMarkers
@onready var camera: MapCamera = $MapCamera
@onready var tooltip: StarTooltip = $UI/Tooltip
@onready var debug_overlay: DebugOverlay = $UI/DebugOverlay
@onready var panel: SystemPanel = $UI/SystemPanel
@onready var system_view: SystemView = $UI/SystemView
@onready var market_panel: MarketPanel = $UI/MarketPanel
@onready var fleet_panel: FleetPanel = $UI/FleetPanel
@onready var shipyard: ShipyardPanel = $UI/ShipyardPanel
@onready var orders_panel: OrdersPanel = $UI/OrdersPanel
@onready var finance_panel: FinancePanel = $UI/FinancePanel
@onready var contracts_panel: ContractsPanel = $UI/ContractsPanel
@onready var news_ticker: NewsTicker = $UI/NewsTicker
@onready var news_panel: NewsPanel = $UI/NewsPanel
@onready var fleet_screen: FleetScreen = $UI/FleetScreen
@onready var ship_panel: ShipPanel = $UI/ShipPanel
@onready var music: MusicPlayer = $Music
@onready var sounds: UiSounds = $UiSounds

## Zoomed in this close (camera distance) on the selected star, its
## world type's music plays; farther out, the "space" theme.
const MUSIC_ZOOM := 22.0
## Sound levels K cycles through: everything, no music, silence.
const SOUND_LEVELS := ["all sound on", "music off", "all sound off"]
var _sound_level := 0
@onready var map_mode: MapModeBar = $UI/MapModeBar
@onready var overlay_dim: ColorRect = $UI/OverlayDim
@onready var floating: FloatingNumbers = $UI/FloatingNumbers

## Market panel wanted open (it follows the selection while on).
var _market_open := false
## Selected ship id, or -1.
var selected_ship := -1
## Fly the camera to a ship that needs orders (arrived, out of the yard).
## Will be a menu option, like Sim.auto_pause.
var auto_focus := true

## Last mouse position from motion events, in the same space as clicks and
## Camera3D.unproject_position. OFF_SCREEN while the mouse is outside.
var _mouse := StarPicker.OFF_SCREEN

func _ready() -> void:
	map.build(Sim.galaxy)
	map.set_known(Sim.player().known)
	markers.setup(Sim.world, map)
	floating.camera = camera
	floating.markers = markers
	debug_overlay.map = map
	debug_overlay.camera = camera
	camera.clicked.connect(_on_clicked)
	camera.double_clicked.connect(_on_double_clicked)
	panel.view_requested.connect(open_system_view)
	panel.market_requested.connect(toggle_market)
	panel.send_requested.connect(send_selected_ship)
	panel.shipyard_requested.connect(open_shipyard)
	panel.contracts_requested.connect(open_contracts)
	fleet_panel.ship_selected.connect(select_ship)
	fleet_panel.orders_requested.connect(open_orders)
	map_mode.mode_changed.connect(_apply_price_map)
	system_view.closed.connect(func(): camera.input_enabled = true)
	for p in _overlays():
		p.closed.connect(_overlay_closed)
	news_ticker.system_requested.connect(_show_news_system)
	news_ticker.log_requested.connect(open_news)
	news_panel.system_requested.connect(_show_news_system)
	fleet_panel.screen_requested.connect(open_fleet)
	ship_panel.orders_requested.connect(open_orders)
	ship_panel.port_requested.connect(_open_port)
	ship_panel.closed.connect(func(): select_ship(-1))
	panel.closed.connect(func(): select(-1))
	fleet_screen.ship_selected.connect(select_ship)
	fleet_screen.orders_requested.connect(open_orders)
	Events.world_events_changed.connect(_update_badges)
	Events.world_events_changed.connect(func(): _apply_price_map(map_mode.commodity))
	Events.charted.connect(func(_c): _update_badges())
	_update_badges()
	Events.fleet_changed.connect(_update_preview)
	for sig in [Events.day_passed, Events.company_changed, Events.charted]:
		sig.connect(func(_x = null): _apply_price_map(map_mode.commodity))
	Events.charted.connect(_on_charted)
	Events.attention.connect(_on_attention)

func _process(_delta: float) -> void:
	music.play_theme(_music_theme())
	# Side panels end above the fixed ones: the market above the fleet card,
	# the right-hand cards above the news ticker (they scroll if longer).
	market_panel.bottom_limit = fleet_panel.global_position.y - 12.0
	panel.bottom_limit = news_ticker.global_position.y - 12.0
	ship_panel.bottom_limit = news_ticker.global_position.y - 12.0
	# Re-pick every frame: the camera may be moving under a still mouse.
	var i := -1
	if _mouse != StarPicker.OFF_SCREEN and not _overlay_open():
		i = pick(_mouse)
	if i != map.hovered:
		map.set_hovered(i)
	if i >= 0:
		tooltip.show_system(map.galaxy, i, _mouse)
	else:
		tooltip.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = (event as InputEventMouse).position

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_mouse = StarPicker.OFF_SCREEN

## Index of the system under a screen position, or -1. Tests every star
## where it is drawn, so each member of a multiple system can be clicked.
func pick(screen_pos: Vector2) -> int:
	var stars := map.star_positions()
	var points := PackedVector2Array()
	points.resize(stars.size())
	for i in stars.size():
		points[i] = StarPicker.OFF_SCREEN if camera.is_position_behind(stars[i]) \
			else camera.unproject_position(stars[i])
	var hit := StarPicker.nearest(points, screen_pos, PICK_RADIUS_PX)
	return map.star_system(hit) if hit >= 0 else -1

## Id of the ship chevron under a screen position, or -1.
func pick_ship(screen_pos: Vector2) -> int:
	var hits := markers.screen_points(camera)
	var points := PackedVector2Array()
	for h in hits:
		points.append(h[1])
	var i := StarPicker.nearest(points, screen_pos, PICK_RADIUS_PX * 0.8)
	return hits[i][0] if i >= 0 else -1

func _on_clicked(screen_pos: Vector2) -> void:
	var ship := pick_ship(screen_pos)
	if ship >= 0:
		select_ship(ship)
	else:
		select(pick(screen_pos))

func _on_double_clicked(screen_pos: Vector2) -> void:
	var i := pick(screen_pos)
	if i >= 0:
		select(i)
		open_system_view()

## The music for what the player looks at: the system view's system, or the
## selected star when zoomed in on it (its world type's theme); else deep space.
func _music_theme() -> String:
	var i := -1
	if system_view.visible and system_view.system:
		i = system_view.system.index
	elif map.selected >= 0 and camera.rig.distance <= MUSIC_ZOOM \
			and camera.rig.focus.distance_to(map.system_position(map.selected)) < 1.0:
		i = map.selected
	if i < 0 or not Sim.player().is_known(i):
		return MusicPlayer.DEFAULT
	var st := Sim.galaxy.systems[i].settlement
	return st.archetype if st else MusicPlayer.DEFAULT

## K: all sound, no music, silence.
func cycle_sound() -> void:
	_sound_level = (_sound_level + 1) % SOUND_LEVELS.size()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), _sound_level >= 1)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"UI"), _sound_level >= 2)
	Events.notice.emit("Sound: %s" % SOUND_LEVELS[_sound_level])

## Selects a system (-1 = none): ring on the map, card on the right, and the
## camera flies there.
func select(i: int) -> void:
	if i >= 0 and i != map.selected:
		sounds.play("select")
	map.set_selected(i)
	orders_panel.set_add_system(i)
	if i >= 0:
		camera.fly_to(map.system_position(i))
		# The right-hand column shows what was clicked last: this star.
		ship_panel.visible = false
		panel.show_system(map.galaxy.systems[i])
		if _market_open:
			market_panel.show_system(map.galaxy.systems[i])
	else:
		panel.visible = false
		market_panel.visible = false
	_update_preview()

## Selects one of the player's ships (-1 = none). With a system selected the
## card then offers to send it there, and the route is previewed.
func select_ship(ship_id: int) -> void:
	selected_ship = ship_id
	markers.selected_ship = ship_id
	market_panel.ship_id = ship_id
	if market_panel.visible and map.selected >= 0:
		market_panel.show_system(map.galaxy.systems[map.selected])
	fleet_panel.select(ship_id)
	panel.set_ship(ship_id)
	if ship_id >= 0:
		camera.fly_to(markers.ship_position(ship_id), 30.0)
		# The right-hand column shows what was clicked last: this ship.
		panel.visible = false
		ship_panel.show_ship(ship_id)
	else:
		ship_panel.visible = false
	_update_preview()

func _on_charted(company_id: int) -> void:
	if company_id != Sim.PLAYER:
		return
	map.set_known(Sim.player().known)
	if map.selected >= 0:
		panel.show_system(map.galaxy.systems[map.selected])

## A player ship needs orders: select it and its system, and fly there.
func _on_attention(ship_id: int, system_index: int) -> void:
	if not auto_focus or system_view.visible or shipyard.visible:
		return
	select_ship(ship_id)
	select(system_index)
	camera.fly_to(map.system_position(system_index), 12.0)

func send_selected_ship() -> void:
	if selected_ship >= 0 and map.selected >= 0:
		Sim.send_ship(selected_ship, map.selected)

func _update_preview() -> void:
	var ship: Ship = Sim.world.fleet.get_ship(selected_ship) if selected_ship >= 0 else null
	if ship == null and selected_ship >= 0:
		selected_ship = -1  # sold
		markers.selected_ship = -1
		panel.set_ship(-1)
	markers.preview_path = PackedInt32Array()
	if ship and ship.status != Ship.Status.TRAVELING and map.selected >= 0:
		var plan := Sim.plan_route(ship.id, map.selected)
		if plan.ok:
			markers.preview_path = plan.path

func toggle_market() -> void:
	_market_open = not _market_open
	if _market_open and map.selected >= 0:
		market_panel.show_system(map.galaxy.systems[map.selected])
	else:
		market_panel.visible = false

func open_system_view() -> void:
	if map.selected < 0:
		return
	if not Sim.player().is_known(map.selected):
		Events.notice.emit("Uncharted: send a ship within one jump first")
		return
	tooltip.visible = false
	camera.input_enabled = false
	system_view.open(map.galaxy.systems[map.selected])

func open_shipyard() -> void:
	if map.selected < 0 or not Sim.player().is_known(map.selected) \
			or not Sim.world.fleet.can_refit_at(map.selected):
		return
	_overlay_opened()
	shipyard.open(map.selected)

## The contract board of the selected system, else of the selected ship's.
func open_contracts() -> void:
	var i := map.selected
	var ship: Ship = Sim.world.fleet.get_ship(selected_ship) if selected_ship >= 0 else null
	if i < 0 and ship and ship.status != Ship.Status.TRAVELING:
		i = ship.system
	if i < 0 or not Sim.player().is_known(i) or Sim.world.economy.market_at(i) == null:
		Events.notice.emit("Select a charted system with a market")
		return
	_overlay_opened()
	contracts_panel.open(i, selected_ship)

## A button on the ship card for its port: market, contracts or yard.
func _open_port(what: String, system_index: int) -> void:
	select(system_index)
	match what:
		"market":
			if not _market_open:
				toggle_market()
		"contracts":
			open_contracts()
		"yard":
			open_shipyard()

func open_fleet() -> void:
	_overlay_opened()
	fleet_screen.open()

func open_news() -> void:
	_overlay_opened()
	news_panel.open()

## A headline was clicked: select its system (if charted) and fly there.
func _show_news_system(i: int) -> void:
	if i >= 0 and Sim.player().is_known(i):
		select(i)

## Pulsing rings at systems with running events: red for danger (war,
## pirates), amber for politics (zealots, embargo, agreements), cyan else.
func _update_badges() -> void:
	var colors := {"danger": Color(1.0, 0.3, 0.28), "politics": Color(1.0, 0.7, 0.25), "info": Color(0.35, 0.85, 1.0)}
	var rank := {"danger": 3, "politics": 2, "info": 1}
	var best := {}  # system -> badge
	for ev in Sim.world.world_events:
		var badge: String = WorldEvents.def_of(Sim.world, ev.kind).get("badge", "info")
		for i in ev.systems:
			if Sim.world.galaxy.systems[i].settlement and rank[badge] > rank.get(best.get(i, ""), 0):
				best[i] = badge
	var out := {}
	for i in best:
		out[i] = colors[best[i]]
	map.set_badges(out)

func open_orders(ship_id: int) -> void:
	if ship_id < 0:
		Events.notice.emit("Select a ship first")
		return
	select_ship(ship_id)
	_overlay_opened()
	orders_panel.open(ship_id, map.selected)

func open_finance() -> void:
	_overlay_opened()
	finance_panel.open()

## Modal panels (shipyard, orders, finance, contracts, news): dim the map
## and stop the camera.
func _overlay_opened() -> void:
	sounds.play("open")
	for p in _overlays():
		if p.visible:
			p.visible = false
	tooltip.visible = false
	camera.input_enabled = false
	overlay_dim.visible = true

func _overlay_closed() -> void:
	sounds.play("close")
	if not _overlays().any(func(p): return p.visible):
		overlay_dim.visible = false
		camera.input_enabled = not system_view.visible

func _overlay_open() -> bool:
	return system_view.visible or _overlays().any(func(p): return p.visible)

## The modal panels (one open at a time, over a dimmed map).
func _overlays() -> Array:
	return [shipyard, orders_panel, finance_panel, contracts_panel, news_panel, fleet_screen]

## Map modes: the danger map (lanes and stars by the chance of a hit), or
## stars tinted by the known price of one good (c; -1 = off).
func _apply_price_map(c: int) -> void:
	tooltip.price_commodity = c
	if map_mode.danger:
		var lanes := {}
		var stars := {}
		for key in Sim.world.danger:
			var d: float = Sim.world.danger[key]
			lanes[key] = MapModeBar.danger_ramp(d)
			for i in [key.x, key.y]:
				stars[i] = maxf(stars.get(i, 0.0), d)
		for i in stars:
			stars[i] = Color(MapModeBar.danger_ramp(stars[i]), 1.0)
		map.set_lane_colors(lanes)
		map.set_tints(stars)
		return
	map.set_lane_colors({})
	if c < 0:
		map.set_tints({})
		return
	var w: World = Sim.world
	var tints := {}
	var unknown := Color(0.28, 0.3, 0.36)
	for s in w.galaxy.systems:
		var known := w.known_prices(Sim.PLAYER, s.index)
		if known.is_empty():
			tints[s.index] = unknown
		else:
			tints[s.index] = MapModeBar.ramp(known.price[c] / w.economy.markets[0].base_price[c])
	map.set_tints(tints)

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var overlay := _overlay_open()
	match k.physical_keycode:
		KEY_ESCAPE:
			if shipyard.visible:
				shipyard.close_panel()
			elif orders_panel.visible:
				orders_panel.close_panel()
			elif finance_panel.visible:
				finance_panel.close_panel()
			elif contracts_panel.visible:
				contracts_panel.close_panel()
			elif news_panel.visible:
				news_panel.close_panel()
			elif fleet_screen.visible:
				fleet_screen.close_panel()
			elif system_view.visible:
				system_view.close_view()
			elif ship_panel.visible:
				select_ship(-1)
			elif map.selected >= 0:
				select(-1)
			else:
				select_ship(-1)
		KEY_ENTER, KEY_KP_ENTER:
			if not overlay:
				open_system_view()
		KEY_M:
			if not overlay:
				toggle_market()
		KEY_S:
			if not overlay:
				send_selected_ship()
		KEY_O:
			if not overlay:
				open_orders(selected_ship)
		KEY_L:
			if finance_panel.visible:
				finance_panel.close_panel()
			elif not overlay:
				open_finance()
		KEY_C:
			if contracts_panel.visible:
				contracts_panel.close_panel()
			elif not overlay:
				open_contracts()
		KEY_V:
			if fleet_screen.visible:
				fleet_screen.close_panel()
			elif not overlay:
				open_fleet()
		KEY_K:
			cycle_sound()
		KEY_N:
			if news_panel.visible:
				news_panel.close_panel()
			elif not overlay:
				open_news()
		KEY_P:
			if not overlay:
				map_mode.cycle()
		KEY_SPACE:
			Sim.toggle_pause()
		KEY_F2:
			Sim.cheat()
		KEY_Z:
			map.show_drop_lines = not map.show_drop_lines
			Events.notice.emit("Drop lines %s" % ("on" if map.show_drop_lines else "off"))
		KEY_1, KEY_2, KEY_3, KEY_4:
			Sim.set_speed(k.physical_keycode - KEY_0)
