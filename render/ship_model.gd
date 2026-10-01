class_name ShipModel
## Builds a 3D model of a ship from its hull and fitted modules: a lofted
## hull (an engine section at the back, a thin spine through the module
## bays, a bow with the bridge), frames between the bays, and one bay per
## module slot showing what is fitted (container stacks, tanks, cabin rings
## with lit windows, a jump ring ...). Shapes come from the data: hulls.json
## "look" (length, beam, nose, engines, fins, paint, style) and modules.json
## "look" (shape, color). A style is a design family (STYLES).
##
## The ship lies along +Z (nose forward), centred on the origin. Pure view
## code: it reads definitions and never touches the sim.

const CRATE_COLORS := ["8c3a2b", "2c4a6e", "3d5c3e", "a37a30", "6c7178", "2d6868", "7b5638", "b0b3b5"]
const ENGINE_GLOW := Color(0.45, 0.75, 1.0)
const WINDOW_GLOW := Color(1.0, 0.82, 0.5)
const HULL_SHADER := preload("res://render/shaders/ship_hull.gdshader")
const PART_SHADER := preload("res://render/shaders/ship_part.gdshader")
const LIGHT_SHADER := preload("res://render/shaders/ship_light.gdshader")
const GLOW_SHADER := preload("res://render/shaders/ship_glow.gdshader")
const FLAME_SHADER := preload("res://render/shaders/ship_flame.gdshader")
## Light patterns (render/shaders/ship_blink.gdshaderinc).
const PATTERNS := {"steady": 0, "flash": 1, "breathe": 2, "flicker": 3, "heartbeat": 4}

## Design families. n: hull section (2 = round, higher = boxier); sides:
## facets around; flat: faceted shading; panel: plate size (around, along);
## variation, grime, patches: plating wear; paint: default hull colour
## (a hull's own "paint" wins); trim: frames and details; glow: engines;
## window: bridge glass ("" = none); frames: "ring" round each bay or
## "collar" on the spine; fins: shape when the hull has fins; nose: forces
## a bow shape; extras: signature parts (_extra); lights: the running
## lights (_lights) and how the engines pulse, each as [colour, pattern,
## period in seconds, ...] with patterns from PATTERNS.
const STYLES := {
	# Concordance and democracies: the clean civilian line.
	"standard": {"paint": "8e9aa8", "trim": "aab4c0", "n": 3.0, "sides": 24, "panel": [0.9, 1.4],
		"variation": 0.05, "grime": 0.05, "glow": "73bfff", "window": "ffd180", "frames": "ring",
		"fins": "swept", "extras": [],
		"lights": {"nav": ["ff2a2a", "2aff5a"], "beacon": ["ffffff", "flash", 1.4],
			"marker": ["cfe4ff", "steady", 1.0, "none"], "engine": ["breathe", 2.4]}},
	# Corporate states: boxy and cheap, radiators and hazard bands.
	"corporate": {"paint": "c4bfb0", "trim": "e0a526", "n": 7.0, "sides": 24, "panel": [1.2, 1.2],
		"variation": 0.03, "grime": 0.2, "glow": "9fd0ff", "window": "e8f4ff", "frames": "ring",
		"fins": "none", "extras": ["radiators", "bands"],
		"lights": {"nav": ["ff2a2a", "2aff5a"], "beacon": ["ffb020", "flash", 0.7],
			"marker": ["ffb020", "flash", 1.2, "chase"], "engine": ["steady", 1.0]}},
	# Military juntas: faceted gunmetal, armour skirts, a turret.
	"junta": {"paint": "4c5446", "trim": "8f3a2c", "n": 2.0, "sides": 6, "flat": true, "panel": [0.7, 0.7],
		"variation": 0.1, "grime": 0.25, "glow": "ff9a50", "window": "ff5a40", "frames": "ring",
		"fins": "blade", "nose": "wedge", "extras": ["skirts", "turret"],
		"lights": {"nav": ["ff3a2a", "ff3a2a"], "marker": ["ff3a2a", "breathe", 4.0, "none"],
			"engine": ["flicker", 1.0]}},
	# Theocracies: cream and gold, a spire.
	"theocracy": {"paint": "e3dccb", "trim": "c9a23a", "n": 2.4, "sides": 28, "panel": [0.6, 2.0],
		"variation": 0.04, "grime": 0.0, "glow": "ffd27a", "window": "ffcf6a", "frames": "ring",
		"fins": "crest", "extras": ["spire"],
		"lights": {"beacon": ["ffd27a", "breathe", 3.0], "marker": ["ffd27a", "breathe", 3.0, "wave"],
			"engine": ["breathe", 3.0]}},
	# Feudal lords: deep red and gold, a ram prow and a crest.
	"feudal": {"paint": "5e1f2c", "trim": "d4a64a", "n": 2.0, "sides": 28, "panel": [0.5, 0.8],
		"variation": 0.06, "grime": 0.05, "glow": "c68cff", "window": "ffc070", "frames": "ring",
		"fins": "swept", "extras": ["prow", "crest"],
		"lights": {"nav": ["c68cff", "ffc070"], "beacon": ["d4a64a", "flash", 2.0],
			"marker": ["ffc070", "flash", 1.6, "chase"], "engine": ["breathe", 2.0]}},
	# Anarchies: patched together from other ships.
	"anarchy": {"paint": "7a6a58", "trim": "b8582a", "n": 4.0, "sides": 10, "flat": true, "panel": [0.5, 0.6],
		"variation": 0.25, "grime": 0.6, "patches": 0.3, "glow": "ffb060", "window": "ffe0a0",
		"frames": "collar", "fins": "blade", "extras": ["scrap"],
		"lights": {"nav": ["ff8a2a", "7aff5a"], "beacon": ["ffd070", "flicker", 1.0],
			"marker": ["", "flicker", 1.0, "random"], "engine": ["flicker", 1.0]}},
	# Robot custodians: smooth white, no windows, a halo.
	"custodians": {"paint": "eef2f5", "trim": "58e0ff", "n": 2.0, "sides": 32, "panel": [1.6, 3.0],
		"variation": 0.0, "grime": 0.0, "metallic": 0.2, "roughness": 0.2, "glow": "58e0ff", "window": "",
		"frames": "collar", "fins": "none", "nose": "round", "extras": ["halo"],
		"lights": {"marker": ["58e0ff", "breathe", 2.0, "wave"], "engine": ["breathe", 2.0]}},
	# Zealot councils: black, red glow, spikes.
	"zealots": {"paint": "1d1b20", "trim": "9a1414", "n": 2.0, "sides": 8, "flat": true, "panel": [0.4, 1.2],
		"variation": 0.05, "grime": 0.1, "glow": "ff2a2a", "window": "ff3030", "frames": "ring",
		"fins": "blade", "nose": "wedge", "extras": ["spikes"],
		"lights": {"beacon": ["ff2020", "heartbeat", 1.6], "marker": ["ff2020", "heartbeat", 1.6, "none"],
			"engine": ["flicker", 1.0]}},
}

static var _materials: Dictionary = {}

## A new model: `accent` is the owner's colour (belts round the hull). Its
## bounds are in the root's meta "size" (Vector3).
static func build(hull: Dictionary, modules: Array, module_defs: Dictionary, accent: Color) -> Node3D:
	var root := Node3D.new()
	var look: Dictionary = hull.get("look", {})
	var style: Dictionary = STYLES.get(str(look.get("style", "standard")), STYLES.standard)
	var L := float(look.get("length", 3.0 + 1.3 * int(hull.get("slots", 3))))
	var B := float(look.get("beam", 1.8))
	var H := B * 0.7
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(hull.get("id", "")))
	var paint := Color.html(str(look.get("paint", style.paint)))
	var rear := -L * 0.5
	var engine_len := L * 0.14
	var nose_len := L * 0.2
	var bay_start := rear + engine_len + L * 0.02
	var bay_end := L * 0.5 - nose_len - L * 0.02
	# What every part needs: sizes, where the sections are, the hull
	# section and the materials.
	var k := {
		"B": B, "H": H, "L": L, "style": style, "rng": rng,
		"n": float(style.n), "sides": int(style.sides), "flat": bool(style.get("flat", false)),
		"rear": rear, "engine_len": engine_len, "bow0": L * 0.5 - nose_len, "bow1": L * 0.5,
		"stern": Vector2(B * 0.46, H * 0.5), "bow": Vector2(B * 0.36, H * 0.36), "spine": Vector2(B * 0.13, H * 0.16),
		"nose": str(style.get("nose", look.get("nose", "block"))),
		"hull": _hull_mat(style, paint),
		"trim": _metal(Color.html(style.trim), 0.8, 0.3),
		"dark": _metal(Color(0.13, 0.14, 0.16), 0.4, 0.65),
		"accent": _accent(accent),
		"glow": Color.html(style.glow),
	}
	_stern(root, k, look, bay_start)
	var spine: Vector2 = k.spine
	_loft(root, [[bay_start - 0.05, spine.x, spine.y, 0.0], [bay_end + L * 0.03, spine.x, spine.y, 0.0]], k, k.hull)
	var bow_mat: Material = k.hull
	if float(style.get("patches", 0.0)) > 0.0:  # a patched ship: its bow came off another ship
		bow_mat = _hull_mat(style, paint.lerp(Color.from_hsv(rng.randf(), 0.4, 0.55), 0.6))
	_bow(root, k, bow_mat)
	if look.get("fins", false):
		_fins(root, k, str(style.fins))
	var slots := modules.size()
	var seg := (bay_end - bay_start) / maxf(slots, 1)
	for i in slots:
		var def: Dictionary = module_defs.get(modules[i], {})
		_module(root, def.get("look", {}), k, bay_start + seg * (i + 0.5), seg, i)
	var frames := []
	for i in range(1, slots):
		frames.append(bay_start + seg * i)
		_frame(root, k, frames[-1], seg)
	for e in style.extras:
		_extra(root, k, str(e))
	_lights(root, k, frames)
	root.set_meta("size", Vector3(B * 1.3, H * 1.4, L * 1.15))
	return root

# --- sections ---------------------------------------------------------------------------

## The engine section: a hull block tapering into the spine, the owner's
## colour as a belt round it, and the nozzles.
static func _stern(root: Node3D, k: Dictionary, look: Dictionary, front: float) -> void:
	var rear: float = k.rear
	var length: float = k.engine_len
	var s: Vector2 = k.stern
	var spine: Vector2 = k.spine
	_loft(root, [[rear, s.x * 0.86, s.y * 0.86, 0.0], [rear + length * 0.1, s.x, s.y, 0.0, 1],
		[rear + length * 0.62, s.x, s.y, 0.0, 1], [front, spine.x, spine.y, 0.0]], k, k.hull)
	_belt(root, k, rear + length * 0.3, length * 0.14, s * 1.03, 0.0, k.accent)
	var n := int(look.get("engines", 2))
	var B: float = k.B
	var H: float = k.H
	var r := minf(B * 0.5 / n, H * 0.3)
	var glow: Color = k.glow
	var pulse: Array = k.style.lights.get("engine", ["steady", 1.0])
	for i in n:
		var x := (i - (n - 1) * 0.5) * (B * 0.7 / maxf(n, 1))
		var y := 0.0 if n < 4 else (H * 0.16 if i % 2 == 0 else -H * 0.16)
		var nozzle := _cylinder(root, r * 0.8, r, length * 0.5, k.dark, Vector3(x, y, rear - length * 0.15))
		nozzle.rotation.x = deg_to_rad(90)
		var disc := _cylinder(root, r * 0.72, r * 0.72, 0.02, _pulse(glow, 4.0, pulse[0], pulse[1], i * 0.17, 0.0, 0.6),
			Vector3(x, y, rear - length * 0.41))
		disc.rotation.x = deg_to_rad(90)
		var flame := _cylinder(root, 0.0, r * 0.6, r * 3.0, _flame(glow, pulse[0], pulse[1], i * 0.17, r * 3.0),
			Vector3(x, y, rear - length * 0.42 - r * 1.5))
		flame.rotation.x = deg_to_rad(-90)

## The bow's section at t (0 = where it starts, 1 = the tip): [half width,
## half height, centre y].
static func _bow_ring(k: Dictionary, t: float) -> Vector3:
	var A: float = k.bow.x
	var h: float = k.bow.y
	match k.nose:
		"wedge":
			return Vector3(A * (1.0 - 0.72 * pow(t, 1.3)), maxf(h * pow(1.0 - t, 0.75), h * 0.04), -h * 0.45 * t)
		"round":
			var e := sqrt(maxf(1.0 - t * t, 0.0))
			return Vector3(maxf(A * e, A * 0.03), maxf(h * e, h * 0.03), 0.0)
		_:
			var s := clampf((t - 0.78) / 0.22, 0.0, 1.0)
			return Vector3(A * (1.0 - 0.22 * s), h * (1.0 - 0.3 * s), -h * 0.05 * s)

## The bow, the owner's colour round its base, and the bridge: a tower on a
## block bow, a glass canopy on the others.
static func _bow(root: Node3D, k: Dictionary, mat: Material) -> void:
	var z0: float = k.bow0
	var z1: float = k.bow1
	var ts: Array = [0.0, 0.78, 1.0]
	match k.nose:
		"round":
			ts = range(9).map(func(i): return sin(i / 8.0 * PI / 2.0))
		"wedge":
			ts = range(7).map(func(i): return i / 6.0)
	var rings := []
	for t in ts:
		var r := _bow_ring(k, t)
		rings.append([lerpf(z0, z1, t), r.x, r.y, r.z, 1 if k.nose == "block" and t == 0.78 else 0])
	_loft(root, rings, k, mat)
	var base := _bow_ring(k, 0.1)
	_belt(root, k, lerpf(z0, z1, 0.06), (z1 - z0) * 0.08, Vector2(base.x, base.y) * 1.03, base.z, k.accent)
	var win := str(k.style.window)
	if win == "":
		return
	var bl := z1 - z0
	var A: float = k.bow.x
	var h: float = k.bow.y
	if k.nose == "block":
		_loft(root, [[z0 + bl * 0.1, A * 0.5, h * 0.3, h], [z0 + bl * 0.5, A * 0.5, h * 0.3, h]], k, mat)
		_box(root, Vector3(A * 0.8, h * 0.12, 0.02), _glow(Color.html(win), 1.5), Vector3(0, h * 1.08, z0 + bl * 0.5 + 0.011))
		return
	# The canopy follows the top of the bow from t0 to t1.
	var t0 := 0.04
	var t1 := 0.42 if k.nose == "wedge" else 0.55
	var canopy := []
	for i in 7:
		var s := i / 6.0
		var t := lerpf(t0, t1, s)
		var r := _bow_ring(k, t)
		var bulge := maxf(sin(PI * pow(s, 0.8)), 0.08)
		canopy.append([lerpf(z0, z1, t), A * 0.36 * bulge, h * 0.3 * bulge, r.z + r.y * 0.9])
	_loft(root, canopy, k, _glass(Color.html(win)))

## Frames between the bays: a ring on struts, or a collar round the
## spine.
static func _frame(root: Node3D, k: Dictionary, z: float, seg: float) -> void:
	var B: float = k.B
	var t := clampf(seg * 0.05, 0.03, 0.1)
	var spine: Vector2 = k.spine
	if k.style.frames == "collar":
		_band(root, z - t, z + t, spine * 1.8, spine * 0.9, k, k.trim)
		return
	var outer := Vector2(B * 0.52, k.H * 0.56)
	var inner := outer * 0.94
	_band(root, z - t * 0.5, z + t * 0.5, outer, inner, k, k.trim)
	for s in [-1.0, 1.0]:
		_box(root, Vector3(B * 0.03, inner.y - spine.y, t * 0.6), k.dark, Vector3(0, s * (inner.y + spine.y) * 0.5, z))
		_box(root, Vector3(inner.x - spine.x, B * 0.03, t * 0.6), k.dark, Vector3(s * (inner.x + spine.x) * 0.5, 0, z))

static func _fins(root: Node3D, k: Dictionary, kind: String) -> void:
	var B: float = k.B
	var H: float = k.H
	var rear: float = k.rear
	var length: float = k.engine_len
	match kind:
		"swept":
			for side in [-1.0, 1.0]:
				var fin := _prism(root, Vector3(k.L * 0.16, H * 0.9, 0.06), k.hull,
					Vector3(side * B * 0.42, 0, rear + length * 0.9))
				fin.rotation = Vector3(0, deg_to_rad(90), deg_to_rad(side * -70))
		"blade":
			for side in [-1.0, 1.0]:
				var fin := _box(root, Vector3(B * 0.04, H * 0.8, length * 0.7), k.hull,
					Vector3(side * B * 0.5, H * 0.3, rear + length * 0.4))
				fin.rotation.z = -side * 0.6
		"crest":
			_crest(root, k)

## A tall dorsal fin over the engine section, highest at the back.
static func _crest(root: Node3D, k: Dictionary) -> void:
	var length: float = k.engine_len
	var crest := _prism(root, Vector3(length * 1.1, k.H * 0.8, k.B * 0.05), k.hull,
		Vector3(0, k.stern.y + k.H * 0.38, k.rear + length * 0.45))
	(crest.mesh as PrismMesh).left_to_right = 1.0
	crest.rotation.y = deg_to_rad(90)

## A style's signature parts.
static func _extra(root: Node3D, k: Dictionary, kind: String) -> void:
	var B: float = k.B
	var H: float = k.H
	var rear: float = k.rear
	var length: float = k.engine_len
	var s: Vector2 = k.stern
	var z0: float = k.bow0
	var z1: float = k.bow1
	var trim: Material = k.trim
	var rng: RandomNumberGenerator = k.rng
	match kind:
		"radiators":
			for side in [-1.0, 1.0]:
				_box(root, Vector3(B * 0.55, B * 0.02, length * 0.55), _metal(Color(0.16, 0.17, 0.19), 0.3, 0.7),
					Vector3(side * (s.x + B * 0.27), 0, rear + length * 0.45))
				_box(root, Vector3(B * 0.02, B * 0.03, length * 0.55), _glow(Color(1.0, 0.45, 0.15), 1.2),
					Vector3(side * (s.x + B * 0.55), 0, rear + length * 0.45))
		"bands":
			for z in [rear + length * 0.08, rear + length * 0.5]:
				_belt(root, k, z, length * 0.06, s * 1.035, 0.0, trim)
			var r := _bow_ring(k, 0.3)
			_belt(root, k, lerpf(z0, z1, 0.3), (z1 - z0) * 0.05, Vector2(r.x, r.y) * 1.04, r.z, trim)
		"skirts":
			for side in [-1.0, 1.0]:
				var plate := _box(root, Vector3(B * 0.05, s.y * 1.5, length * 0.75), k.hull,
					Vector3(side * s.x * 1.08, -s.y * 0.2, rear + length * 0.4))
				plate.rotation.z = side * 0.35
		"turret":
			var z := rear + length * 0.45
			var y := s.y
			_cylinder(root, H * 0.16, H * 0.2, H * 0.14, k.dark, Vector3(0, y + H * 0.07, z))
			_box(root, Vector3(H * 0.3, H * 0.14, H * 0.36), k.hull, Vector3(0, y + H * 0.2, z))
			for side in [-1.0, 1.0]:
				var gun := _cylinder(root, B * 0.015, B * 0.015, length * 0.8, k.dark,
					Vector3(side * H * 0.07, y + H * 0.2, z + length * 0.4))
				gun.rotation.x = deg_to_rad(90)
		"spire":
			var r := _bow_ring(k, 0.3)
			var top := r.z + r.y
			_cylinder(root, 0.0, B * 0.07, H * 1.3, trim, Vector3(0, top + H * 0.62, lerpf(z0, z1, 0.3)))
			_light(root, Vector3(0, top + H * 1.35, lerpf(z0, z1, 0.3)), k.glow, B * 0.45, "breathe", 3.0)
			for side in [-1.0, 1.0]:
				_cylinder(root, 0.0, B * 0.04, H * 0.6, trim, Vector3(side * s.x * 0.7, s.y + H * 0.25, rear + length * 0.3))
		"prow":
			var tip := _bow_ring(k, 1.0)
			var ram := _cylinder(root, 0.0, k.bow.x * 0.2, (z1 - z0) * 0.8, trim, Vector3(0, tip.z, z1 + (z1 - z0) * 0.3))
			ram.rotation.x = deg_to_rad(90)
			for t in [0.25, 0.5]:
				var r := _bow_ring(k, t)
				_belt(root, k, lerpf(z0, z1, t), (z1 - z0) * 0.04, Vector2(r.x, r.y) * 1.03, r.z, trim)
		"crest":
			_crest(root, k)
		"scrap":
			for i in 6:
				var on_bow := i % 2 == 1
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var z := lerpf(z0, z1, rng.randf_range(0.1, 0.5)) if on_bow else rear + length * rng.randf_range(0.15, 0.6)
				var half := _bow_ring(k, 0.3).x if on_bow else s.x
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.5), rng.randf_range(0.25, 0.6))
				var plate := _box(root, Vector3(B * 0.03, H * rng.randf_range(0.2, 0.45), B * rng.randf_range(0.2, 0.5)),
					_metal(c, 0.5, 0.7), Vector3(side * half * 1.02, H * rng.randf_range(-0.2, 0.2), z))
				plate.rotation.x = rng.randf_range(-0.3, 0.3)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var tank := _capsule(root, H * 0.16, length * 0.9, _metal(Color(0.55, 0.5, 0.42), 0.6, 0.6),
				Vector3(side * (s.x + H * 0.14), -s.y * 0.4, rear + length * 0.5))
			tank.rotation.x = deg_to_rad(90)
			var mast := _cylinder(root, 0.015, 0.015, H * 0.9, k.dark, Vector3(-side * s.x * 0.5, s.y + H * 0.4, rear + length * 0.3))
			mast.rotation.z = -side * 0.3
		"halo":
			var r := _bow_ring(k, 0.25)
			var torus := TorusMesh.new()
			torus.inner_radius = r.x * 1.3
			torus.outer_radius = r.x * 1.42
			var halo := _mesh(root, torus, _pulse(k.glow, 2.0, "breathe", 2.0, 0.0, 0.0, 0.3), Vector3(0, r.z, lerpf(z0, z1, 0.25)))
			halo.rotation.x = deg_to_rad(90)
			var band := _bow_ring(k, 0.55)
			# A pulse runs along the ship, bands and markers together.
			var wave := _pulse(k.glow, 2.0, "breathe", 2.0, 0.0, 1.0 / k.L, 0.15)
			_belt(root, k, lerpf(z0, z1, 0.55), (z1 - z0) * 0.02, Vector2(band.x, band.y) * 1.02, band.z, wave)
			_belt(root, k, rear + length * 0.55, length * 0.03, s * 1.02, 0.0, wave)
		"spikes":
			for i in 6:
				var a := TAU * (i + 0.5) / 6.0
				var base := Vector3(cos(a) * s.x, sin(a) * s.y, rear + length * 0.5)
				var spike := _cylinder(root, 0.0, B * 0.05, B * 0.5, k.dark, base)
				_point(spike, Vector3(cos(a), sin(a), -0.8))
				spike.position += spike.basis.y * B * 0.2
			for side in [-1.0, 1.0]:
				var r := _bow_ring(k, 0.2)
				var spike := _cylinder(root, 0.0, B * 0.04, B * 0.4, k.dark, Vector3(side * r.x, r.z, lerpf(z0, z1, 0.2)))
				_point(spike, Vector3(side, 0.2, -1.2))
				spike.position += spike.basis.y * B * 0.15
			_belt(root, k, rear + length * 0.2, length * 0.05, s * 1.03, 0.0, _pulse(k.glow, 2.0, "heartbeat", 1.6, 0.0, 0.0, 0.15))

## One module bay, centred at z, `seg` long. Its parts carry some of the
## style's grime.
static func _module(root: Node3D, look: Dictionary, k: Dictionary, z: float, seg: float, slot: int) -> void:
	var B: float = k.B
	var H: float = k.H
	var dark: Material = k.dark
	var grime := float(k.style.get("grime", 0.0)) * 0.7
	var color := Color.html(str(look.get("color", "9aa4ae")))
	var d := seg * 0.86
	match look.get("shape", ""):
		"crates":
			# Shipping containers stacked either side of a rack on the spine.
			var rng := RandomNumberGenerator.new()
			rng.seed = slot * 7919 + 11
			_box(root, Vector3(B * 0.06, H * 0.8, d), dark, Vector3(0, 0, z))
			var n := maxi(1, roundi(d / (B * 0.8)))
			var each := d / n
			for side in [-1.0, 1.0]:
				for level in 2:
					for i in n:
						var c := Color.html(CRATE_COLORS[rng.randi() % CRATE_COLORS.size()])
						_box(root, Vector3(B * 0.38, H * 0.37, each - B * 0.03), _part(c, {"rib": B * 0.035, "grime": grime + 0.1}),
							Vector3(side * B * 0.23, (level - 0.5) * H * 0.39, z - d * 0.5 + each * (i + 0.5)))
		"hopper":
			# An open ore hopper: sloped walls on a floor, the load heaped inside.
			var wall := _part(Color(0.4, 0.41, 0.42), {"rib": B * 0.08, "rib_line": 1.0, "metallic": 0.5, "grime": grime + 0.3})
			_box(root, Vector3(B * 0.5, H * 0.08, d), wall, Vector3(0, -H * 0.36, z))
			for side in [-1.0, 1.0]:
				var plate := _box(root, Vector3(B * 0.05, H * 0.72, d), wall, Vector3(side * B * 0.37, -H * 0.04, z))
				plate.rotation.z = -side * 0.35
			var ore := _sphere(root, _part(color.darkened(0.4), {"rocky": 1.0}), Vector3(0, H * 0.04, z))
			ore.scale = Vector3(B * 0.7, H * 0.48, d * 0.92)
		"reefer":
			# An insulated box with a cooling unit on top.
			_box(root, Vector3(B * 0.86, H * 0.74, d * 0.94),
				_part(color, {"rib": B * 0.22, "rib_line": 1.0, "metallic": 0.1, "roughness": 0.4, "grime": grime}), Vector3(0, 0, z))
			for side in [-1.0, 1.0]:
				_box(root, Vector3(0.02, H * 0.05, d * 0.86), _glow(Color(0.4, 0.9, 1.0), 2.0), Vector3(side * B * 0.435, H * 0.22, z))
			_box(root, Vector3(B * 0.36, H * 0.12, d * 0.34), dark, Vector3(0, H * 0.43, z - d * 0.2))
			for i in 3:
				_cylinder(root, H * 0.05, H * 0.05, 0.02, _metal(Color(0.5, 0.55, 0.6), 0.6, 0.4),
					Vector3((i - 1) * B * 0.11, H * 0.5, z - d * 0.2))
		"tanks":
			# Two pressure tanks on saddles, a pipe between them.
			var tank := _part(color, {"metallic": 0.75, "roughness": 0.3, "grime": grime})
			for side in [-1.0, 1.0]:
				var t := _capsule(root, H * 0.34, d, tank, Vector3(side * B * 0.28, 0, z))
				t.rotation.x = deg_to_rad(90)
				for f in [-0.3, 0.3]:
					var band := _cylinder(root, H * 0.35, H * 0.35, d * 0.05, dark, Vector3(side * B * 0.28, 0, z + f * d))
					band.rotation.x = deg_to_rad(90)
			for f in [-0.3, 0.3]:
				_box(root, Vector3(B * 0.56, H * 0.1, d * 0.06), dark, Vector3(0, 0, z + f * d))
			var pipe := _cylinder(root, B * 0.025, B * 0.025, d * 0.9, _metal(Color(0.7, 0.55, 0.3), 0.7, 0.35), Vector3(0, H * 0.26, z))
			pipe.rotation.x = deg_to_rad(90)
		"vault":
			# An armoured strongbox with round doors and corner lights.
			_box(root, Vector3(B * 0.62, H * 0.6, d * 0.8),
				_part(color, {"rib": B * 0.14, "rib_line": 1.0, "metallic": 0.6, "roughness": 0.45, "grime": grime}), Vector3(0, 0, z))
			for side in [-1.0, 1.0]:
				var door := _cylinder(root, H * 0.2, H * 0.2, B * 0.03, _metal(Color(0.62, 0.55, 0.4), 0.8, 0.3), Vector3(side * B * 0.32, 0, z))
				door.rotation.z = deg_to_rad(90)
				var hub := _cylinder(root, H * 0.05, H * 0.05, B * 0.06, dark, Vector3(side * B * 0.33, 0, z))
				hub.rotation.z = deg_to_rad(90)
			var corners := [Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]
			for i in corners.size():
				var c: Vector3 = corners[i]
				_light(root, Vector3(c.x * B * 0.3, c.y * H * 0.3, z + c.z * d * 0.4), Color(1.0, 0.7, 0.25), B * 0.12,
					"flash", 1.2, i * 0.25)
		"ring":
			# A habitat drum with rows of cabin windows, rims at both ends.
			var length := d * 0.8
			var drum := _cylinder(root, B * 0.5, B * 0.5, length,
				_part(color, {"windows": 24.0, "window_rows": 3.0, "window_half": length * 0.36, "roughness": 0.45}), Vector3(0, 0, z))
			drum.rotation.x = deg_to_rad(90)
			for e in [-1.0, 1.0]:
				var rim := _cylinder(root, B * 0.52, B * 0.52, length * 0.08, _metal(color.darkened(0.35), 0.6, 0.4), Vector3(0, 0, z + e * length * 0.5))
				rim.rotation.x = deg_to_rad(90)
		"pods":
			# Luxury pods with big warm windows, each on a neck from the spine.
			var skin := _part(color, {"windows": 10.0, "window_rows": 4.0, "window_half": d * 0.3,
				"window_color": Color(1.0, 0.86, 0.55), "metallic": 0.1, "roughness": 0.3})
			for side in [-1.0, 1.0]:
				var pod := _capsule(root, H * 0.28, d * 0.95, skin, Vector3(side * B * 0.3, H * 0.05, z))
				pod.rotation.x = deg_to_rad(90)
				var neck := _cylinder(root, H * 0.06, H * 0.06, B * 0.2, dark, Vector3(side * B * 0.12, H * 0.05, z))
				neck.rotation.z = deg_to_rad(90)
		"mailpod":
			# A mail canister on a rack, with a beacon mast.
			_box(root, Vector3(B * 0.08, H * 0.3, d * 0.5), dark, Vector3(0, H * 0.12, z))
			var can := _capsule(root, H * 0.17, d * 0.6, _part(color, {"roughness": 0.4}), Vector3(0, H * 0.34, z))
			can.rotation.x = deg_to_rad(90)
			for f in [-0.12, 0.12]:
				var band := _cylinder(root, H * 0.175, H * 0.175, d * 0.05, _paint(Color(0.92, 0.92, 0.9)), Vector3(0, H * 0.34, z + f * d))
				band.rotation.x = deg_to_rad(90)
			_cylinder(root, 0.02, 0.02, H * 0.74, dark, Vector3(0, H * 0.88, z))
			_light(root, Vector3(0, H * 1.25, z), Color(1.0, 0.3, 0.3), B * 0.18, "flash", 1.5, slot * 0.3)
		"plates":
			# Sloped armour plates round a frame.
			var plate := _part(color, {"rib": B * 0.2, "rib_line": 1.0, "metallic": 0.7, "roughness": 0.5, "grime": grime + 0.15})
			for side in [-1.0, 1.0]:
				var p := _box(root, Vector3(B * 0.08, H * 0.9, d), plate, Vector3(side * B * 0.44, 0, z))
				p.rotation.z = side * 0.18
				_box(root, Vector3(B * 0.8, H * 0.05, d * 0.06), dark, Vector3(0, 0, z + side * d * 0.35))
			_box(root, Vector3(B * 0.72, H * 0.08, d), plate, Vector3(0, H * 0.44, z))
		"boosters":
			# Drive nacelles on pylons, intakes at the front.
			var skin := _part(Color(0.6, 0.64, 0.7), {"metallic": 0.7, "roughness": 0.35, "grime": grime})
			for side in [-1.0, 1.0]:
				_box(root, Vector3(B * 0.3, H * 0.06, d * 0.4), dark, Vector3(side * B * 0.27, -H * 0.1, z))
				var nac := _capsule(root, H * 0.17, d, skin, Vector3(side * B * 0.42, -H * 0.1, z))
				nac.rotation.x = deg_to_rad(90)
				var intake := TorusMesh.new()
				intake.inner_radius = H * 0.12
				intake.outer_radius = H * 0.19
				_mesh(root, intake, dark, Vector3(side * B * 0.42, -H * 0.1, z + d * 0.38)).rotation.x = deg_to_rad(90)
				var pulse: Array = k.style.lights.get("engine", ["steady", 1.0])
				var g := _cylinder(root, H * 0.13, H * 0.13, 0.02, _pulse(ENGINE_GLOW, 4.0, pulse[0], pulse[1], 0.0, 0.0, 0.6),
					Vector3(side * B * 0.42, -H * 0.1, z - d * 0.5))
				g.rotation.x = deg_to_rad(90)
		"jumpring":
			# A glowing field ring inside a structural ring, on four vanes.
			var frame := TorusMesh.new()
			frame.inner_radius = B * 0.5
			frame.outer_radius = B * 0.58
			_mesh(root, frame, _metal(Color(0.3, 0.33, 0.37), 0.7, 0.4), Vector3(0, 0, z)).rotation.x = deg_to_rad(90)
			var torus := TorusMesh.new()
			torus.inner_radius = B * 0.43
			torus.outer_radius = B * 0.5
			_mesh(root, torus, _pulse(Color(0.3, 0.9, 1.0), 2.5, "breathe", 2.5, 0.0, 0.0, 0.4), Vector3(0, 0, z)).rotation.x = deg_to_rad(90)
			for i in 4:
				var vane := _box(root, Vector3(0.05, B * 0.3, d * 0.3), dark, Vector3(0, 0, z))
				vane.rotation.z = TAU * i / 4.0
				vane.position += Vector3(cos(TAU * i / 4.0 + PI / 2), sin(TAU * i / 4.0 + PI / 2), 0) * B * 0.3
		"dish":
			# A trading-computer dish on a mast, feed horn lit.
			_box(root, Vector3(B * 0.24, H * 0.12, B * 0.24), dark, Vector3(0, H * 0.2, z))
			_cylinder(root, 0.03, 0.03, H * 0.5, dark, Vector3(0, H * 0.5, z))
			var axis := Vector3(0, cos(deg_to_rad(35)), -sin(deg_to_rad(35)))
			var hub := Vector3(0, H * 0.8, z)
			var dish := _cylinder(root, H * 0.4, 0.05, H * 0.14, _metal(Color(0.85, 0.87, 0.9), 0.5, 0.3), hub)
			dish.rotation.x = deg_to_rad(-35)
			var feed := _cylinder(root, 0.012, 0.012, H * 0.3, dark, hub + axis * H * 0.15)
			_point(feed, axis)
			_light(root, hub + axis * H * 0.3, Color(0.5, 1.0, 0.6), B * 0.12, "breathe", 2.0)
		_:
			_box(root, Vector3(B * 0.6, H * 0.6, d), dark, Vector3(0, 0, z))

## The style's running lights: port (+X) and starboard lights, beacons
## on top of and under the engine section (taking turns), and markers on
## the frames, the tail and the bow tip. Markers spread their phase by
## "chase" (one after another, stern to bow), "wave" (along the ship) or
## "random"; a marker colour of "" is a random colour per light.
static func _lights(root: Node3D, k: Dictionary, frames: Array) -> void:
	var lights: Dictionary = k.style.lights
	var B: float = k.B
	var s: Vector2 = k.stern
	var rear: float = k.rear
	var length: float = k.engine_len
	var rng: RandomNumberGenerator = k.rng
	var nav: Array = lights.get("nav", [])
	if nav.size() == 2:
		var bow := _bow_ring(k, 0.15)
		for i in 2:
			var side := 1.0 if i == 0 else -1.0
			var c := Color.html(nav[i])
			_light(root, Vector3(side * s.x * 1.02, 0, rear + length * 0.62), c, B * 0.3)
			_light(root, Vector3(side * bow.x * 1.02, bow.z, lerpf(k.bow0, k.bow1, 0.15)), c, B * 0.24)
	var beacon: Array = lights.get("beacon", [])
	if not beacon.is_empty():
		for i in 2:
			_light(root, Vector3(0, s.y * (1.04 if i == 0 else -1.04), rear + length * 0.45), Color.html(beacon[0]),
				B * 0.4, beacon[1], beacon[2], i * 0.5)
	var marker: Array = lights.get("marker", [])
	if marker.is_empty():
		return
	var top: float = k.H * 0.56 if k.style.frames == "ring" else k.spine.y * 1.8
	var spots: Array[Vector3] = [Vector3(0, s.y * 0.9, rear)]
	for z in frames:
		spots.append(Vector3(0, top, z))
	var tip := _bow_ring(k, 0.97)
	spots.append(Vector3(0, tip.z, float(k.bow1) + 0.02))
	for i in spots.size():
		var phase := 0.0
		match marker[3]:
			"chase":
				phase = -float(i) / spots.size()
			"wave":
				phase = -spots[i].z / float(k.L)
			"random":
				phase = rng.randf()
		var c := Color.html(marker[0]) if marker[0] != "" else Color.from_hsv(rng.randf(), 0.6, 1.0)
		_light(root, spots[i], c, B * 0.22, marker[1], marker[2], phase)

# --- lofted geometry --------------------------------------------------------------------

## One hull section at z: a superellipse (k.n: 2 = ellipse, higher is
## boxier) with half size `half`, centred on (x, y). k.sides + 1 points
## from the bottom round (the last repeats the first, for the UV seam);
## faceted styles are turned so a flat face lies at the bottom.
static func _section(half: Vector2, y: float, z: float, k: Dictionary, x := 0.0) -> PackedVector3Array:
	var sides: int = k.sides
	var e := 2.0 / float(k.n)
	var turn := PI / sides if k.flat else 0.0
	var out := PackedVector3Array()
	for i in sides + 1:
		var a := -PI / 2.0 + turn + TAU * i / sides
		var c := cos(a)
		var s := sin(a)
		out.append(Vector3(x + half.x * signf(c) * pow(absf(c), e), y + half.y * signf(s) * pow(absf(s), e), z))
	return out

## A closed tube through `rings` ([z, half width, half height, centre y,
## hard edge]) in z order, capped at both ends. A ring whose fifth value is
## 1 is a hard edge. UV is in model units, round the section and along Z,
## for the plating shader.
static func _loft(root: Node3D, rings: Array, k: Dictionary, mat: Material, x := 0.0) -> MeshInstance3D:
	var sides: int = k.sides
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[PackedVector3Array] = []
	var us: Array[PackedFloat32Array] = []
	for r in rings:
		var ring := _section(Vector2(r[1], r[2]), r[3], r[0], k, x)
		var u := PackedFloat32Array([0.0])
		for i in range(1, ring.size()):
			u.append(u[i - 1] + ring[i].distance_to(ring[i - 1]))
		pts.append(ring)
		us.append(u)
	var group := 1
	for j in rings.size() - 1:
		st.set_smooth_group(-1 if k.flat else group)
		var yc := (float(rings[j][3]) + float(rings[j + 1][3])) * 0.5
		for i in sides:
			var p := [pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i]]
			var uv := [Vector2(us[j][i], p[0].z), Vector2(us[j][i + 1], p[1].z),
				Vector2(us[j + 1][i + 1], p[2].z), Vector2(us[j + 1][i], p[3].z)]
			var c: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
			_quad(st, p, uv, Vector3(c.x - x, c.y - yc, 0.0))
		if rings[j + 1].size() > 4 and rings[j + 1][4]:
			group += 1
	st.set_smooth_group(-1)
	for end in [0, rings.size() - 1]:
		var r: Array = rings[end]
		var centre := Vector3(x, r[3], r[0])
		var ring := pts[end]
		for i in sides:
			_tri(st, [centre, ring[i], ring[i + 1]],
				[Vector2(centre.x, centre.y), Vector2(ring[i].x, ring[i].y), Vector2(ring[i + 1].x, ring[i + 1].y)],
				Vector3(0, 0, -1 if end == 0 else 1))
	st.generate_normals()
	return _mesh(root, st.commit(), mat, Vector3.ZERO)

## A flat ring (a frame) from z0 to z1, sections `outer` and `inner`.
static func _band(root: Node3D, z0: float, z1: float, outer: Vector2, inner: Vector2, k: Dictionary, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o0 := _section(outer, 0.0, z0, k)
	var o1 := _section(outer, 0.0, z1, k)
	var i0 := _section(inner, 0.0, z0, k)
	var i1 := _section(inner, 0.0, z1, k)
	for i in int(k.sides):
		st.set_smooth_group(-1 if k.flat else 1)
		var out := Vector3(o0[i].x + o0[i + 1].x, o0[i].y + o0[i + 1].y, 0.0)
		_quad(st, [o0[i], o0[i + 1], o1[i + 1], o1[i]], [], out)
		st.set_smooth_group(-1 if k.flat else 2)
		_quad(st, [i0[i], i0[i + 1], i1[i + 1], i1[i]], [], -out)
		st.set_smooth_group(-1)
		_quad(st, [o0[i], o0[i + 1], i0[i + 1], i0[i]], [], Vector3(0, 0, -1))
		_quad(st, [o1[i], o1[i + 1], i1[i + 1], i1[i]], [], Vector3(0, 0, 1))
	st.generate_normals()
	return _mesh(root, st.commit(), mat, Vector3.ZERO)

## A short straight tube round the hull (a colour belt), `length` long from z.
static func _belt(root: Node3D, k: Dictionary, z: float, length: float, half: Vector2, y: float, mat: Material) -> void:
	_loft(root, [[z, half.x, half.y, y], [z + length, half.x, half.y, y]], k, mat)

## Adds quad a-b-c-d as two triangles facing `outward`.
static func _quad(st: SurfaceTool, p: Array, uv: Array, outward: Vector3) -> void:
	_tri(st, [p[0], p[1], p[2]], [] if uv.is_empty() else [uv[0], uv[1], uv[2]], outward)
	_tri(st, [p[0], p[2], p[3]], [] if uv.is_empty() else [uv[0], uv[2], uv[3]], outward)

## Adds one triangle wound so its front faces `outward` (Godot's front
## faces are clockwise).
static func _tri(st: SurfaceTool, p: Array, uv: Array, outward: Vector3) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var order := [0, 1, 2] if (c - a).cross(b - a).dot(outward) >= 0.0 else [0, 2, 1]
	for o in order:
		st.set_uv(Vector2.ZERO if uv.is_empty() else uv[o])
		st.add_vertex(p[o])

## Turns a primitive so its +Y axis points along `dir`.
static func _point(mi: MeshInstance3D, dir: Vector3) -> void:
	var y := dir.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.FORWARD).normalized()
	mi.basis = Basis(x, y, x.cross(y))

# --- primitives and materials ------------------------------------------------------------

static func _mesh(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi

static func _box(root: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(root, m, mat, pos)

static func _prism(root: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _mesh(root, m, mat, pos)

## Axis along Y until rotated.
static func _cylinder(root: Node3D, top: float, bottom: float, height: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 24
	m.rings = 1
	return _mesh(root, m, mat, pos)

static func _capsule(root: Node3D, radius: float, height: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = 24
	m.rings = 6
	return _mesh(root, m, mat, pos)

## A unit sphere (scale it).
static func _sphere(root: Node3D, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 24
	m.rings = 12
	return _mesh(root, m, mat, pos)

static func _metal(c: Color, metallic := 0.55, roughness := 0.45) -> StandardMaterial3D:
	var key := "metal:%s:%s:%s" % [c.to_html(), metallic, roughness]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metallic
		m.roughness = roughness
		m.metallic_specular = 0.6
		_materials[key] = m
	return _materials[key]

static func _paint(c: Color, roughness := 0.6) -> StandardMaterial3D:
	return _metal(c, 0.15, roughness)

static func _accent(c: Color) -> StandardMaterial3D:
	var key := "accent:" + c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.35
		m.roughness = 0.4
		_materials[key] = m
	return _materials[key]

## Self-lit (engines, windows, lights); `soft` is see-through and additive
## (the engine flame).
static func _glow(c: Color, energy: float, soft := false) -> StandardMaterial3D:
	var key := "glow:%s:%s:%s" % [c.to_html(), energy, soft]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		if soft:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(c, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			# Emission above 1 is what makes the viewer's glow bloom.
			m.albedo_color = Color.BLACK
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = energy
		_materials[key] = m
	return _materials[key]

## The plated hull of a style (ship_hull shader).
static func _hull_mat(style: Dictionary, paint: Color) -> ShaderMaterial:
	var key := "hull:%s:%s" % [style.hash(), paint.to_html()]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = HULL_SHADER
		m.set_shader_parameter("albedo", paint)
		m.set_shader_parameter("metallic", float(style.get("metallic", 0.55)))
		m.set_shader_parameter("roughness", float(style.get("roughness", 0.45)))
		m.set_shader_parameter("panel", Vector2(style.panel[0], style.panel[1]))
		m.set_shader_parameter("variation", float(style.get("variation", 0.05)))
		m.set_shader_parameter("grime", float(style.get("grime", 0.0)))
		m.set_shader_parameter("patches", float(style.get("patches", 0.0)))
		m.set_shader_parameter("patch_color", paint.lerp(Color(0.55, 0.3, 0.18), 0.7))
		_materials[key] = m
	return _materials[key]

## Bridge glass: dark and glossy, lit from inside.
static func _glass(c: Color) -> StandardMaterial3D:
	var key := "glass:" + c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.1, 0.14)
		m.metallic = 0.9
		m.roughness = 0.12
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.5
		_materials[key] = m
	return _materials[key]

## A module part (ship_part shader): a colour plus shader settings (rib,
## rib_line, rocky, grime, windows, window_rows, window_half,
## window_color, metallic, roughness).
static func _part(c: Color, opts := {}) -> ShaderMaterial:
	var key := "part:%s:%s" % [c.to_html(), opts]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = PART_SHADER
		m.set_shader_parameter("albedo", c)
		for o in opts:
			m.set_shader_parameter(o, opts[o])
		_materials[key] = m
	return _materials[key]

## A point light: a camera-facing glow `size` across, blinking in
## `pattern` (PATTERNS) every `period` seconds, shifted by `phase` (0..1).
static func _light(root: Node3D, pos: Vector3, c: Color, size: float, pattern := "steady", period := 1.0,
		phase := 0.0) -> void:
	var key := "light:%s:%s:%s:%s:%s" % [c.to_html(), pattern, period, snappedf(fposmod(phase, 1.0), 0.01), snappedf(size, 0.01)]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = LIGHT_SHADER
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("pattern", PATTERNS.get(pattern, 0))
		m.set_shader_parameter("period", period)
		m.set_shader_parameter("phase", fposmod(phase, 1.0))
		m.set_shader_parameter("pull", size * 0.5)
		_materials[key] = m
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mi := _mesh(root, quad, _materials[key], pos)
	mi.extra_cull_margin = size

## A glowing part that pulses in `pattern` (PATTERNS) every `period`
## seconds. `wave` shifts the phase per model unit along Z; `low` is the
## dimmest it gets.
static func _pulse(c: Color, energy: float, pattern: String, period: float, phase := 0.0, wave := 0.0,
		low := 0.0) -> ShaderMaterial:
	var key := "pulse:%s:%s:%s:%s:%s:%s:%s" % [c.to_html(), energy, pattern, period, snappedf(phase, 0.01), wave, low]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = GLOW_SHADER
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("energy", energy)
		m.set_shader_parameter("pattern", PATTERNS.get(pattern, 0))
		m.set_shader_parameter("period", period)
		m.set_shader_parameter("phase", phase)
		m.set_shader_parameter("wave", wave)
		m.set_shader_parameter("low", low)
		_materials[key] = m
	return _materials[key]

## An engine flame `height` long that flickers and stretches with
## `pattern`.
static func _flame(c: Color, pattern: String, period: float, phase: float, height: float) -> ShaderMaterial:
	var key := "flame:%s:%s:%s:%s:%s" % [c.to_html(), pattern, period, snappedf(phase, 0.01), snappedf(height, 0.01)]
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("pattern", PATTERNS.get(pattern, 0))
		m.set_shader_parameter("period", period)
		m.set_shader_parameter("phase", phase)
		m.set_shader_parameter("height", height)
		_materials[key] = m
	return _materials[key]
