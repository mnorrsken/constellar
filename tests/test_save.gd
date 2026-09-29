extends RefCounted
## Save and load (Milestone 11): a loaded world saves to the very same text,
## and it runs on exactly like the original (both copies a year later are
## identical); save files are written, listed and read back; saves from
## another version are refused.

var _content := Content.load_world_content("res://data/")
var _stars := Content.load_object("res://data/stars.json")

## A world a year and more into a busy game: a ship on route orders, one
## carrying contracts, events running, influence with a post and a
## concession, a loan and a goal.
func _busy_world() -> World:
	var w := World.create(1, _stars, _content)
	w.warm_up()
	var c := w.companies[0]
	c.cash = 3000000.0
	w.reveal_all(0)
	for m in w.economy.markets:
		Trading.observe(w, 0, m.system)
	var s := w.ships_of(0)[0]
	var next: int = w.galaxy.lanes_of(s.system)[0].other(s.system)
	w.set_orders(0, s.id, [
		{"system": s.system, "sell_all": true, "buy": [{"commodity": "machinery", "amount": 0}]},
		{"system": next, "sell_all": true, "buy": [], "wait_full": false}])
	w.start_orders(0, s.id)
	var sol := w.galaxy.index_of("sol")
	var r := w.buy_ship(0, "courier", sol)
	var courier: Ship = r.ship
	for job in Contracts.offers_at(w, sol):
		if Contracts.fits(w, courier, job):
			w.accept_contract(0, job.id, courier.id)
	w.take_loan(0, 300000.0)
	w.set_goal(0, "value")
	c.influence[sol] = 60.0
	w.open_trading_post(0, sol)
	w.sign_concession(0, sol)
	WorldEvents.start(w, "tariff_hike", [next])
	for lane in w.galaxy.lanes:
		var a := w.galaxy.systems[lane.a].settlement
		var b := w.galaxy.systems[lane.b].settlement
		if a and b and a.population > 10000 and b.population > 10000:
			WorldEvents.start(w, "war", [lane.a, lane.b])
			break
	for d in 400:
		w.advance_day()
	w.drain_events()
	return w

## Where two save texts first differ (for a readable failure).
func _diff(a: String, b: String) -> String:
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			return "first difference at %d: ...%s... vs ...%s..." % [i, a.substr(maxi(i - 60, 0), 120),
				b.substr(maxi(i - 60, 0), 120)]
	return "lengths %d vs %d" % [a.length(), b.length()]

## Acceptance: save -> load gives an identical world (the reloaded world
## saves to the same text), and both copies a year on are still identical.
func test_load_gives_an_identical_world_that_runs_on_the_same(t: Object) -> void:
	var w := _busy_world()
	t.ok(w.world_events.size() > 0 and not w.contracts_of(0).is_empty() or w.ships_of(0).size() == 2,
		"a busy game to save")
	var text := SaveGame.to_json(w)
	var error := []
	var loaded := SaveGame.from_data(JSON.parse_string(text), _stars, _content, error)
	t.ok(loaded != null, "loaded %s" % [error])
	var again := SaveGame.to_json(loaded)
	t.ok(again == text, "re-saved it is the same text (%d characters). %s" % [text.length(),
		"" if again == text else _diff(text, again)])
	for d in 365:
		w.advance_day()
		loaded.advance_day()
	var a := SaveGame.to_json(w)
	var b := SaveGame.to_json(loaded)
	t.ok(a == b, "a year later both are identical. %s" % ("" if a == b else _diff(a, b)))
	t.ok(a != text, "and the year did change things")

func test_save_files_are_written_listed_and_read(t: Object) -> void:
	var w := World.create(1, _stars, _content)
	w.warm_up()
	var dir := "user://test_saves/"
	var path := dir + SaveGame.file_name("My Game 2") + ".json"
	t.eq(path, dir + "my_game_2.json", "a file-safe name")
	var r := SaveGame.write(w, path, {"company": "Lodestar", "date": w.date_string()})
	t.ok(r.ok, "written")
	var saves := SaveGame.list(dir)
	t.ok(saves.size() >= 1 and saves[0].name == "my_game_2" and saves[0].meta.company == "Lodestar", "listed with its meta")
	var back := SaveGame.read(path, _stars, _content)
	t.ok(back.ok and SaveGame.to_json(back.world) == SaveGame.to_json(w), "read back the same")
	t.ok(not SaveGame.read(dir + "nothing.json", _stars, _content).ok, "a missing save is refused")
	DirAccess.remove_absolute(path)

func test_saves_from_another_version_are_refused(t: Object) -> void:
	var w := World.create(1, _stars, _content)
	var d := SaveGame.to_data(w)
	d.format = SaveGame.FORMAT + 1
	var error := []
	t.ok(SaveGame.from_data(d, _stars, _content, error) == null and "version" in error[0], "another format")
	d = SaveGame.to_data(w)
	d.lanes = 1
	error.clear()
	t.ok(SaveGame.from_data(d, _stars, _content, error) == null and "star map" in error[0], "another star map")
