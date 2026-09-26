extends RefCounted
## Calendar, Market (prices, trades, recipes) and Economy (traffic, history).

const CFG := {
	"cover_days": 10.0, "elasticity": 0.8, "price_min": 0.25, "price_max": 4.0,
	"overstock_start": 1.0, "overstock_stop": 2.0, "decay_per_day": 0.01, "history_weeks": 3,
	"update_days": 7,
	"traffic": {"friction": 0.1, "per_ly": 0.0, "capacity": 1000.0, "max_share": 0.5},
}
const BASES := [100.0, 50.0, 20.0]

## A market making commodity 1 from commodity 0, with target stock set.
func _market(cfg := CFG) -> Market:
	var m := Market.new(0, PackedFloat64Array(BASES), cfg)
	m.size = 1.0
	m.add_recipe({0: 10.0}, {1: 5.0})
	m.settle()
	return m

func test_calendar(t: Object) -> void:
	t.eq(Calendar.format(0, 3400), "1 Jan 3400", "day 0")
	t.eq(Calendar.format(31, 3400), "1 Feb 3400", "day 31")
	t.eq(Calendar.format(364, 3400), "31 Dec 3400", "last day of the year")
	t.eq(Calendar.format(365, 3400), "1 Jan 3401", "new year")

func test_price_rises_when_stock_falls(t: Object) -> void:
	var m := _market()
	var tg := m.target[0]
	t.ok(is_equal_approx(m.price_at(0, tg), 100.0), "at target = base price")
	t.ok(m.price_at(0, tg * 0.5) > m.price_at(0, tg), "less stock, higher price")
	t.ok(m.price_at(0, tg * 2.0) < m.price_at(0, tg), "more stock, lower price")
	t.ok(is_equal_approx(m.price_at(0, 0.0), 400.0), "empty market hits the 4x clamp")
	t.ok(is_equal_approx(m.price_at(0, tg * 1000.0), 25.0), "flooded market hits the 0.25x clamp")
	t.eq(m.price_at(2, 0.0), 20.0, "untraded goods sit at base price")

func test_big_lots_get_worse_prices(t: Object) -> void:
	var m := _market()
	var small := m.quote_buy(0, 1.0)
	var big := m.quote_buy(0, 50.0) / 50.0
	t.ok(big > small, "buying 50 costs more per unit (%.1f) than buying 1 (%.1f)" % [big, small])
	var sell_small := m.quote_sell(0, 1.0)
	var sell_big := m.quote_sell(0, 50.0) / 50.0
	t.ok(sell_big < sell_small, "selling 50 earns less per unit (%.1f) than selling 1 (%.1f)" % [sell_big, sell_small])

func test_buy_and_sell_move_stock_and_price(t: Object) -> void:
	var m := _market()
	var before := m.price[0]
	var got: Array = m.buy(0, 30.0)
	t.eq(got[0], 30.0, "bought what was asked")
	t.ok(m.price[0] > before, "buying raises the price")
	var all: Array = m.buy(0, 1e9)
	t.ok(is_equal_approx(m.stock[0], 0.0) and all[0] < 1e9, "cannot buy more than the stock")
	m.sell(0, 500.0)
	t.ok(m.price[0] < 400.0, "selling brings the price down again")

func test_recipe_runs_at_scarcest_input(t: Object) -> void:
	var m := _market()
	m.stock[0] = 5.0  # half of one day's input
	m.stock[1] = 0.0
	m.tick(1)
	t.ok(is_equal_approx(m.stock[1], 2.5), "half the input makes half the output (%.2f)" % m.stock[1])
	t.ok(is_zero_approx(m.stock[0]), "input used up, never negative")

func test_outputs_throttle_separately(t: Object) -> void:
	var m := Market.new(0, PackedFloat64Array(BASES), CFG)
	m.size = 1.0
	m.add_recipe({}, {0: 10.0, 1: 10.0})
	m.settle()
	m.stock[0] = m.target[0] * 2.0  # warehouse full for output 0
	m.stock[1] = 0.0
	m.tick(1)
	t.ok(m.stock[1] > 9.0, "output 1 still produced while output 0 is full")

func test_decay_only_above_target(t: Object) -> void:
	var m := Market.new(0, PackedFloat64Array(BASES), CFG)
	m.size = 1.0
	m.add_recipe({0: 0.0001}, {})
	m.settle()
	var tg := m.target[0]
	m.stock[0] = tg
	m.tick(1)
	t.ok(m.stock[0] > tg * 0.999, "stock at target does not rot")
	m.stock[0] = tg * 2.0
	m.tick(1)
	t.ok(m.stock[0] < tg * 2.0 * 0.999, "surplus slowly rots")

func test_traffic_moves_goods_to_the_dearer_market(t: Object) -> void:
	var e := Economy.new()
	e._cfg = CFG
	e.commodity_ids = PackedStringArray(["a", "b", "c"])
	var cheap := _market()
	var dear := _market()
	cheap.system = 0
	dear.system = 1
	dear.stock[0] = dear.target[0] * 0.2
	dear.refresh_prices()
	e.markets.assign([cheap, dear])
	e.links = [[cheap, dear, 5.0]]
	var before := cheap.stock[0]
	e.run_traffic()
	t.ok(cheap.stock[0] < before and dear.stock[0] > dear.target[0] * 0.2, "goods flowed to the dear market")
	var gap_before := dear.price[1] / cheap.price[1]
	t.ok(is_equal_approx(gap_before, 1.0), "equal prices ...")
	var s1 := cheap.stock[1]
	e.run_traffic()
	t.ok(is_equal_approx(cheap.stock[1], s1), "... move nothing (friction)")

func test_week_of_production_in_one_step(t: Object) -> void:
	var cfg := CFG.duplicate()
	cfg.decay_per_day = 0.0  # keep the arithmetic exact
	var m := _market(cfg)
	m.stock[0] = 70.0  # exactly a week of input
	m.stock[1] = 0.0
	m.tick(7)
	t.ok(is_equal_approx(m.stock[1], 35.0), "7 days of output at once (%.1f)" % m.stock[1])
	t.ok(is_zero_approx(m.stock[0]), "7 days of input used")

func test_markets_move_once_a_week(t: Object) -> void:
	var content := Content.load_world_content("res://data/")
	var w := World.create(1, Content.load_object("res://data/stars.json"), content)
	var m := w.economy.markets[0]
	var start := m.stock.duplicate()
	for i in 6:
		w.advance_day()
	t.eq(m.stock, start, "no change during the week")
	w.advance_day()
	t.ok(m.stock != start, "the market moved at the end of the week")

func test_stocks_are_in_thousands_of_tonnes(t: Object) -> void:
	var content := Content.load_world_content("res://data/")
	var w := World.create(1, Content.load_object("res://data/stars.json"), content)
	var earth := w.economy.market_at(w.galaxy.index_of("sol"))
	var grain := w.economy.index_of("grain")
	t.ok(earth.target[grain] > 10000.0, "Earth keeps over 10,000 t of grain (%d)" % earth.target[grain])

func test_weekly_history_is_capped(t: Object) -> void:
	var m := _market()
	for i in 5:
		m.record_week()
	t.eq(m.history.size(), 3, "keeps history_weeks samples")

func test_world_days_and_determinism(t: Object) -> void:
	var content := Content.load_world_content("res://data/")
	var stars := Content.load_object("res://data/stars.json")
	var a := World.create(1, stars, content)
	var b := World.create(1, stars, content)
	for i in 60:
		a.advance_day()
		b.advance_day()
	t.eq(a.day, 60, "60 days passed")
	t.eq(a.date_string(), "2 Mar 3400", "date after 60 days")
	var same := true
	for i in a.economy.markets.size():
		if a.economy.markets[i].stock != b.economy.markets[i].stock:
			same = false
	t.ok(same, "same seed, same markets after 60 days")

func test_one_year_stays_healthy(t: Object) -> void:
	var content := Content.load_world_content("res://data/")
	var w := World.create(1, Content.load_object("res://data/stars.json"), content)
	for i in 365:
		w.advance_day()
	var bad := 0
	var clamped := 0
	var traded := 0
	for m in w.economy.markets:
		for c in m.stock.size():
			if is_nan(m.stock[c]) or m.stock[c] < 0.0:
				bad += 1
			if m.is_traded(c):
				traded += 1
				var r := m.price[c] / m.base_price[c]
				if r >= 3.999 or r <= 0.2501:
					clamped += 1
	t.eq(bad, 0, "no negative or NaN stock")
	t.ok(float(clamped) / traded < float(content.balance.economy.soak.max_clamp_share),
		"few prices at the clamps after a year (%d of %d)" % [clamped, traded])
	t.eq(w.economy.markets[0].history.size(), 52, "a year of weekly history")

func test_traffic_fills_up_to_the_fill_share(t: Object) -> void:
	var cfg := CFG.duplicate(true)
	cfg.traffic["fill"] = 1.5
	var e := Economy.new()
	e._cfg = cfg
	e.commodity_ids = PackedStringArray(["a", "b", "c"])
	var cheap := _market(cfg)
	var dear := _market(cfg)
	dear.system = 1
	cheap.stock[0] = cheap.target[0] * 20.0  # a glut next door
	cheap.refresh_prices()
	e.markets.assign([cheap, dear])
	e.links = [[cheap, dear, 5.0]]
	for i in 20:
		e.run_traffic()
	t.ok(dear.stock[0] > dear.target[0] * 1.05, "traders fill past the target stock")
	t.ok(dear.stock[0] <= dear.target[0] * 1.5 + 0.01, "but not past the fill share")

## Robots wear out parts: a robot world uses machinery and electronics by
## its robot count (balance "robot_needs"), like people use food.
func test_robots_use_machinery_and_electronics(t: Object) -> void:
	var content := Content.load_world_content("res://data/")
	var w := World.create(1, Content.load_object("res://data/stars.json"), content)
	var e := w.economy
	var mach := e.index_of("machinery")
	var elec := e.index_of("electronics")
	var found := false
	for m in e.markets:
		var st := w.galaxy.systems[m.system].settlement
		if st.robots > 0 and st.population == 0:
			found = true
			var per := float(content.balance.economy.volume_scale) * e.size_of(st.robots, 0.0)
			t.ok(m.demand_rate[mach] >= float(content.balance.economy.robot_needs.machinery) * per - 0.01,
				"%s uses machinery for its robots" % st.name)
			t.ok(m.demand_rate[elec] > 0.0, "and electronics")
			break
	t.ok(found, "a robot world without people")
