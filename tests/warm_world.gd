extends RefCounted
## A warmed-up world for tests, made once per test run. World.create +
## warm_up takes about a second; after the first time, make() rebuilds the
## same world from its save data in about 50 ms. The copy is exact (see
## test_save.gd, which keeps the real warm-up path to prove it), so a test
## gets what World.create(seed) + warm_up() would give it. Keyed by seed and
## the stars and content, so a test with edited content gets its own.

static var _data := {}

static func make(stars: Dictionary, content: Dictionary, world_seed := 1) -> World:
	var key := [world_seed, stars.hash(), content.hash()]
	if not _data.has(key):
		var w := World.create(world_seed, stars, content)
		w.warm_up()
		_data[key] = SaveGame.to_data(w)
	return SaveGame.from_data(_data[key], stars, content)
