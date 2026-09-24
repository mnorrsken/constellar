class_name Galaxy
extends RefCounted
## The star map: systems and the starlanes between them, plus pathfinding.
##
## Pure data + logic (no autoloads), built from data/stars.json via
## `from_dict`, or by hand in tests with `add_system` / `add_lane`.
## A ship's jump range limits which lanes it can use: every query that walks
## lanes takes a `max_jump` in light years (INF = any lane).

var systems: Array[StarSystem] = []
var lanes: Array[Lane] = []

var _index: Dictionary = {}  # system id -> index
var _adjacent: Array = []  # per system: Array of Lane

## Builds a galaxy from the stars.json layout:
## { systems: [{id, name, pos: [x, y, z], stars: [...]}], lanes: [[id, id], ...] }
static func from_dict(data: Dictionary) -> Galaxy:
	var g := Galaxy.new()
	for s in data.get("systems", []):
		var p: Array = s.pos
		var stars: Array[Dictionary] = []
		stars.assign(s.get("stars", []))
		g.add_system(s.id, s.name, Vector3(p[0], p[1], p[2]), stars)
	for pair in data.get("lanes", []):
		var a := g.index_of(pair[0])
		var b := g.index_of(pair[1])
		if a < 0 or b < 0:
			push_warning("[Galaxy] lane with unknown system: %s" % [pair])
			continue
		g.add_lane(a, b)
	return g

## Adds a system and returns its index.
func add_system(id: String, name: String, position: Vector3,
		stars: Array[Dictionary] = []) -> int:
	var s := StarSystem.new()
	s.index = systems.size()
	s.id = id
	s.name = name
	s.position = position
	s.stars = stars
	systems.append(s)
	_index[id] = s.index
	_adjacent.append([])
	return s.index

## Adds a two-way lane. Returns null for a self-lane or a duplicate.
func add_lane(a: int, b: int) -> Lane:
	if a == b or lane_between(a, b) != null:
		return null
	var lane := Lane.new(a, b, distance(a, b))
	lanes.append(lane)
	_adjacent[a].append(lane)
	_adjacent[b].append(lane)
	return lane

func size() -> int:
	return systems.size()

## Index of the system with this id, or -1.
func index_of(id: String) -> int:
	return _index.get(id, -1)

func system_by_id(id: String) -> StarSystem:
	var i := index_of(id)
	return systems[i] if i >= 0 else null

func distance(a: int, b: int) -> float:
	return systems[a].position.distance_to(systems[b].position)

func lanes_of(i: int) -> Array:
	return _adjacent[i]

func lane_between(a: int, b: int) -> Lane:
	for lane in _adjacent[a]:
		if lane.other(a) == b:
			return lane
	return null

## True if every system can reach every other using lanes no longer than
## `max_jump`.
func is_fully_connected(max_jump: float = INF) -> bool:
	if systems.is_empty():
		return true
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for lane in _adjacent[u]:
			var v: int = lane.other(u)
			if lane.length <= max_jump and not seen.has(v):
				seen[v] = true
				stack.append(v)
	return seen.size() == systems.size()

## Shortest route by distance (A*) from `from` to `to` using only lanes no
## longer than `max_jump`, and (when `allowed` is given, one byte per system)
## only systems whose byte is non-zero. `penalty` adds extra cost (in ly) per
## lane, keyed Vector2i(lower index, higher index) ("safest" routing). Returns the system indices including
## both ends, [from] when from == to, or an empty array when there is no route.
func find_path(from: int, to: int, max_jump: float = INF,
		allowed := PackedByteArray(), penalty := {}) -> PackedInt32Array:
	if from == to:
		return PackedInt32Array([from])
	var goal := systems[to].position
	var g_cost := {from: 0.0}
	var came_from := {}
	var open := {from: systems[from].position.distance_to(goal)}  # index -> f
	var closed := {}
	while not open.is_empty():
		var u: int = -1
		var best := INF
		for i in open:
			if open[i] < best:
				best = open[i]
				u = i
		if u == to:
			return _rebuild(came_from, to)
		open.erase(u)
		closed[u] = true
		for lane in _adjacent[u]:
			if lane.length > max_jump:
				continue
			var v: int = lane.other(u)
			if closed.has(v) or (not allowed.is_empty() and allowed[v] == 0):
				continue
			var cost: float = g_cost[u] + lane.length
			if not penalty.is_empty():
				cost += penalty.get(Vector2i(mini(u, v), maxi(u, v)), 0.0)
			if cost < g_cost.get(v, INF):
				g_cost[v] = cost
				came_from[v] = u
				open[v] = cost + systems[v].position.distance_to(goal)
	return PackedInt32Array()

## Total lane length along a path of system indices.
func path_length(path: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += distance(path[i - 1], path[i])
	return total

func _rebuild(came_from: Dictionary, to: int) -> PackedInt32Array:
	var path := PackedInt32Array([to])
	var u := to
	while came_from.has(u):
		u = came_from[u]
		path.append(u)
	path.reverse()
	return path
