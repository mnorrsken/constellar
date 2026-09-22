#!/usr/bin/env python3
"""Build data/stars.json (star systems + starlanes) from the HYG catalogue.

Usage:  python3 tools/build_stars.py <hyg_v4x.csv.gz>   (or `make stars`)

Steps:
  1. Read every HYG star within the rim radius, convert its equatorial
     position (parsecs) to galactic XYZ in light years.
  2. Group stars into systems: HYG companion links (comp_primary) plus any
     stars closer together than the group radius (this catches Proxima).
  3. Name systems, then apply the hand curation in tools/stars_curation.json
     (renames, replacement component lists, extra systems not in HYG).
  4. Select: every system inside the core radius, the notable list, the extra
     systems, then real "bridge" stars that shorten the longest gaps.
  5. Lanes: k nearest neighbours up to a max length, minus lanes that pass
     close by another star, plus the minimum spanning tree (always connected),
     plus data/lanes_overrides.json.
  6. Print lane stats (count, longest, choke points) and write the JSON.

HYG (https://codeberg.org/astronexus/hyg) is CC BY-SA 4.0, and so is the
generated file. Standard library only.
"""

import csv
import gzip
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CURATION = ROOT / "tools" / "stars_curation.json"
OVERRIDES = ROOT / "data" / "lanes_overrides.json"
OUTPUT = ROOT / "data" / "stars.json"

LY_PER_PC = 3.26156
# Stats printout only; hull jump ranges live in hulls.json (Milestone 5).
RANGE_REPORT_LY = (8.0, 10.0, 12.0, 14.0, 16.0)
CHOKE_MIN_PART = 5

CREDIT = (
    "Star positions and magnitudes from the HYG database v4.4 "
    "(https://codeberg.org/astronexus/hyg), licensed CC BY-SA 4.0. "
    "Selected, grouped and extended for Constellar; this file is also CC BY-SA 4.0."
)

# ICRS (equatorial J2000) -> galactic rotation.
EQ_TO_GAL = (
    (-0.0548755604, -0.8734370902, -0.4838350155),
    (0.4941094279, -0.4448296300, 0.7469822445),
    (-0.8676661490, -0.1980763734, 0.4559837762),
)

GREEK = {
    "Alp": "Alpha", "Bet": "Beta", "Gam": "Gamma", "Del": "Delta", "Eps": "Epsilon",
    "Zet": "Zeta", "Eta": "Eta", "The": "Theta", "Iot": "Iota", "Kap": "Kappa",
    "Lam": "Lambda", "Mu": "Mu", "Nu": "Nu", "Xi": "Xi", "Omi": "Omicron", "Pi": "Pi",
    "Rho": "Rho", "Sig": "Sigma", "Tau": "Tau", "Ups": "Upsilon", "Phi": "Phi",
    "Chi": "Chi", "Psi": "Psi", "Ome": "Omega",
}
SUPERSCRIPT = {"1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵"}

GENITIVE = {
    "And": "Andromedae", "Ant": "Antliae", "Aps": "Apodis", "Aqr": "Aquarii",
    "Aql": "Aquilae", "Ara": "Arae", "Ari": "Arietis", "Aur": "Aurigae",
    "Boo": "Bootis", "Cae": "Caeli", "Cam": "Camelopardalis", "Cnc": "Cancri",
    "CVn": "Canum Venaticorum", "CMa": "Canis Majoris", "CMi": "Canis Minoris",
    "Cap": "Capricorni", "Car": "Carinae", "Cas": "Cassiopeiae", "Cen": "Centauri",
    "Cep": "Cephei", "Cet": "Ceti", "Cha": "Chamaeleontis", "Cir": "Circini",
    "Col": "Columbae", "Com": "Comae Berenices", "CrA": "Coronae Australis",
    "CrB": "Coronae Borealis", "Crv": "Corvi", "Crt": "Crateris", "Cru": "Crucis",
    "Cyg": "Cygni", "Del": "Delphini", "Dor": "Doradus", "Dra": "Draconis",
    "Equ": "Equulei", "Eri": "Eridani", "For": "Fornacis", "Gem": "Geminorum",
    "Gru": "Gruis", "Her": "Herculis", "Hor": "Horologii", "Hya": "Hydrae",
    "Hyi": "Hydri", "Ind": "Indi", "Lac": "Lacertae", "Leo": "Leonis",
    "LMi": "Leonis Minoris", "Lep": "Leporis", "Lib": "Librae", "Lup": "Lupi",
    "Lyn": "Lyncis", "Lyr": "Lyrae", "Men": "Mensae", "Mic": "Microscopii",
    "Mon": "Monocerotis", "Mus": "Muscae", "Nor": "Normae", "Oct": "Octantis",
    "Oph": "Ophiuchi", "Ori": "Orionis", "Pav": "Pavonis", "Peg": "Pegasi",
    "Per": "Persei", "Phe": "Phoenicis", "Pic": "Pictoris", "Psc": "Piscium",
    "PsA": "Piscis Austrini", "Pup": "Puppis", "Pyx": "Pyxidis", "Ret": "Reticuli",
    "Sge": "Sagittae", "Sgr": "Sagittarii", "Sco": "Scorpii", "Scl": "Sculptoris",
    "Sct": "Scuti", "Ser": "Serpentis", "Sex": "Sextantis", "Tau": "Tauri",
    "Tel": "Telescopii", "Tri": "Trianguli", "TrA": "Trianguli Australis",
    "Tuc": "Tucanae", "UMa": "Ursae Majoris", "UMi": "Ursae Minoris",
    "Vel": "Velorum", "Vir": "Virginis", "Vol": "Volantis", "Vul": "Vulpeculae",
}

CLASS_BASE = {"O": 0, "B": 10, "A": 20, "F": 30, "G": 40, "K": 50, "M": 60}
# Rough V-band bolometric corrections by spectral index (O0 = 0 ... M9 = 69).
BC_TABLE = [
    (5, -4.0), (9, -3.2), (10, -3.0), (15, -1.2), (19, -0.4), (20, -0.2),
    (25, -0.05), (30, 0.0), (35, -0.03), (40, -0.07), (42, -0.08), (45, -0.10),
    (50, -0.2), (55, -0.6), (60, -1.2), (62, -1.6), (64, -2.4), (65, -2.9),
    (66, -3.6), (68, -4.5), (69, -5.0),
]
M_BOL_SUN = 4.74

SPECT_RE = re.compile(
    r"^(sd|d)?([OBAFGKMLTY])(\d+(?:\.\d+)?)?[\s:]*(Ia|Ib|III|II|IV|VI|V|I)?"
)


# --- geometry ----------------------------------------------------------------

def eq_to_gal_ly(x, y, z):
    return tuple(
        LY_PER_PC * (r[0] * x + r[1] * y + r[2] * z) for r in EQ_TO_GAL
    )


def radec_to_eq(ra_deg, dec_deg, dist_pc):
    ra, dec = math.radians(ra_deg), math.radians(dec_deg)
    return (
        dist_pc * math.cos(dec) * math.cos(ra),
        dist_pc * math.cos(dec) * math.sin(ra),
        dist_pc * math.sin(dec),
    )


def dist(a, b):
    return math.dist(a, b)


# --- star physics (loose) ------------------------------------------------------

def parse_spect(spect, absmag):
    """-> (class letter, subclass float or None, luminosity class str)."""
    s = (spect or "").strip()
    if s[:1] == "D" and len(s) > 1 and (s[1].isalpha() or s[1].isdigit()):
        m = re.search(r"\d+(\.\d+)?", s)
        return "D", float(m.group()) if m else None, ""
    m = SPECT_RE.match(s[:1].upper() + s[1:] if s[:1] in "km" else s)
    if m:
        sub = float(m.group(3)) if m.group(3) else None
        lum_class = m.group(4) or ("V" if m.group(1) == "d" else "VI" if m.group(1) == "sd" else "")
        return m.group(2), sub, lum_class
    # No usable type: guess a main-sequence type from the absolute magnitude.
    if absmag is None:
        return "M", 5.0, "V"
    for limit, cls, sub in ((0.5, "B", 8.0), (2.0, "A", 5.0), (3.5, "F", 5.0),
                            (5.0, "G", 5.0), (7.5, "K", 5.0)):
        if absmag <= limit:
            return cls, sub, "V"
    return "M", round(min(9.0, max(0.0, (absmag - 8.8) * 1.2)), 1), "V"


def bolometric_correction(cls, sub):
    if cls == "D":
        return -4.0 + 0.35 * sub if sub is not None else -1.0
    if cls not in CLASS_BASE:
        return -5.0
    idx = CLASS_BASE[cls] + (sub if sub is not None else 5.0)
    if idx <= BC_TABLE[0][0]:
        return BC_TABLE[0][1]
    for (x0, y0), (x1, y1) in zip(BC_TABLE, BC_TABLE[1:]):
        if idx <= x1:
            return y0 + (y1 - y0) * (idx - x0) / (x1 - x0)
    return BC_TABLE[-1][1]


def estimate_mass(cls, lum_class, lum):
    if cls == "D":
        return 0.6
    if cls in "LTY":
        return 0.07
    if lum_class in ("Ia", "Ib", "I", "II", "III"):
        return 1.5
    if lum < 0.033:
        return (lum / 0.23) ** (1 / 2.3)
    if lum < 16:
        return lum ** 0.25
    return (lum / 1.4) ** (1 / 3.5)


def make_component(name, spect, absmag, luminosity=None, mass=None):
    cls, sub, lum_class = parse_spect(spect, absmag)
    if luminosity is None:
        m_bol = absmag + bolometric_correction(cls, sub)
        luminosity = 10 ** (-0.4 * (m_bol - M_BOL_SUN))
    if mass is None:
        mass = estimate_mass(cls, lum_class, luminosity)
    return {
        "name": name,
        "spect": spect or "",
        "class": cls,
        "subclass": sub,
        "lum_class": lum_class,
        "luminosity": float(f"{luminosity:.4g}"),
        "mass": round(mass, 3),
    }


# --- names -------------------------------------------------------------------

def bayer_name(bayer, con):
    m = re.match(r"^([A-Za-z]+)(?:-(\d))?$", bayer)
    if not m or m.group(1) not in GREEK or con not in GENITIVE:
        return None
    return GREEK[m.group(1)] + SUPERSCRIPT.get(m.group(2) or "", "") + " " + GENITIVE[con]


def catalogue_name(gl):
    gl = " ".join(gl.split())
    gl = re.sub(r"(\d)[A-C]$", r"\1", gl)
    return re.sub(r"^Gl ", "Gliese ", gl)


def default_name(row):
    if row["proper"]:
        return row["proper"]
    if row["bayer"]:
        n = bayer_name(row["bayer"], row["con"])
        if n:
            return n
    if row["flam"] and row["con"] in GENITIVE:
        return f"{row['flam']} {GENITIVE[row['con']]}"
    if row["gl"]:
        return catalogue_name(row["gl"])
    if row["hip"]:
        return f"HIP {row['hip']}"
    if row["hd"]:
        return f"HD {row['hd']}"
    return f"HYG {row['id']}"


def slugify(name):
    for sup, digit in ((v, k) for k, v in SUPERSCRIPT.items()):
        name = name.replace(sup, digit)
    name = name.replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


# --- loading and grouping ----------------------------------------------------

def load_rows(path, rim_ly):
    rows = []
    with gzip.open(path, "rt", newline="") as f:
        for row in csv.DictReader(f):
            if not row["dist"]:
                continue
            d_ly = float(row["dist"]) * LY_PER_PC
            if d_ly > rim_ly:
                continue
            row["pos"] = eq_to_gal_ly(float(row["x"]), float(row["y"]), float(row["z"]))
            row["absmag_f"] = float(row["absmag"]) if row["absmag"] else None
            rows.append(row)
    return rows


def group_rows(rows, group_ly):
    parent = list(range(len(rows)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)

    by_id = {r["id"]: i for i, r in enumerate(rows)}
    for i, r in enumerate(rows):
        p = r["comp_primary"]
        if p and p != r["id"] and p in by_id:
            union(i, by_id[p])
    for i in range(len(rows)):
        for j in range(i + 1, len(rows)):
            if dist(rows[i]["pos"], rows[j]["pos"]) < group_ly:
                union(i, j)

    groups = {}
    for i in range(len(rows)):
        groups.setdefault(find(i), []).append(rows[i])
    return list(groups.values())


def build_system(members):
    comps = []
    for r in members:
        comps.append((r, make_component("", r["spect"], r["absmag_f"] if r["absmag_f"] is not None else 15.0)))
    comps.sort(key=lambda rc: -rc[1]["luminosity"])
    primary = comps[0][0]
    return {
        "name": default_name(primary),
        "pos": primary["pos"],
        "stars": [c for _, c in comps],
    }


def name_components(system):
    stars = system["stars"]
    if len(stars) == 1:
        stars[0]["name"] = system["name"]
        return
    for i, s in enumerate(stars):
        s["name"] = f"{system['name']} {chr(ord('A') + i)}"


# --- selection ---------------------------------------------------------------

def mst_edges(points):
    n = len(points)
    edges = sorted(
        (dist(points[i], points[j]), i, j) for i in range(n) for j in range(i + 1, n)
    )
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    out = []
    for d, i, j in edges:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[ri] = rj
            out.append((d, i, j))
    return out


def add_bridges(selected, pool, bridge_ly, max_systems):
    """Add real stars from the pool that split the longest MST gaps."""
    accepted = set()
    added = []
    while len(selected) < max_systems:
        pts = [s["pos"] for s in selected]
        long_edges = sorted(
            ((d, i, j) for d, i, j in mst_edges(pts)
             if d > bridge_ly and (selected[i]["name"], selected[j]["name"]) not in accepted),
            reverse=True,
        )
        if not long_edges:
            break
        d, i, j = long_edges[0]
        a, b = selected[i], selected[j]
        best, best_score = None, d
        for c in pool:
            score = max(dist(a["pos"], c["pos"]), dist(c["pos"], b["pos"]))
            if score < best_score - 1e-6:
                best, best_score = c, score
        if best is None:
            accepted.add((a["name"], b["name"]))
            continue
        pool.remove(best)
        selected.append(best)
        added.append(best["name"])
    return added


# --- lanes -------------------------------------------------------------------

def build_lanes(systems, cfg, overrides):
    pts = [s["pos"] for s in systems]
    n = len(pts)
    k, max_len, detour = cfg["k_nearest"], cfg["max_lane_ly"], cfg["detour_factor"]
    lanes = set()
    for i in range(n):
        near = sorted((dist(pts[i], pts[j]), j) for j in range(n) if j != i)[:k]
        for d, j in near:
            if d <= max_len:
                lanes.add((min(i, j), max(i, j)))

    def detoured(i, j):
        d = dist(pts[i], pts[j])
        return any(
            dist(pts[i], pts[c]) + dist(pts[c], pts[j]) <= detour * d
            for c in range(n) if c not in (i, j)
        )

    lanes = {(i, j) for i, j in lanes if not detoured(i, j)}
    for _, i, j in mst_edges(pts):
        lanes.add((min(i, j), max(i, j)))

    index = {s["id"]: i for i, s in enumerate(systems)}
    for a, b in overrides.get("add", []):
        i, j = index[a], index[b]
        lanes.add((min(i, j), max(i, j)))
    for a, b in overrides.get("remove", []):
        i, j = index[a], index[b]
        lanes.discard((min(i, j), max(i, j)))
    return sorted(lanes)


def adjacency(n, lanes):
    adj = [set() for _ in range(n)]
    for i, j in lanes:
        adj[i].add(j)
        adj[j].add(i)
    return adj


def components(adj, removed=None):
    """Sizes of the connected parts of the graph, ignoring node `removed`."""
    seen = {removed}
    sizes = []
    for start in range(len(adj)):
        if start in seen:
            continue
        seen.add(start)
        stack, size = [start], 0
        while stack:
            u = stack.pop()
            size += 1
            for v in adj[u]:
                if v not in seen:
                    seen.add(v)
                    stack.append(v)
        sizes.append(size)
    return sizes


def choke_points(adj, min_part):
    """Systems whose loss cuts off at least `min_part` other systems."""
    out = []
    for u in range(len(adj)):
        sizes = sorted(components(adj, u))
        if len(sizes) > 1 and sizes[-2] >= min_part:
            out.append(u)
    return out


# --- main --------------------------------------------------------------------

def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    cur = json.loads(CURATION.read_text())
    overrides = json.loads(OVERRIDES.read_text())

    rows = load_rows(sys.argv[1], cur["rim_radius_ly"])
    pool = [build_system(g) for g in group_rows(rows, cur["group_radius_ly"])]

    unused_renames = set(cur["rename"])
    for s in pool:
        if s["name"] in cur["rename"]:
            unused_renames.discard(s["name"])
            s["name"] = cur["rename"][s["name"]]
    for name in sorted(unused_renames):
        print(f"warning: rename '{name}' matched no system")

    for extra in cur["extra_systems"]:
        eq = radec_to_eq(extra["ra_deg"], extra["dec_deg"], extra["dist_pc"])
        pool.append({"name": extra["name"], "pos": eq_to_gal_ly(*eq), "stars": []})
        cur["systems"].setdefault(extra["name"], {"components": extra["components"]})

    names = [s["name"] for s in pool]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        sys.exit(f"duplicate system names: {sorted(dupes)}")

    by_name = {s["name"]: s for s in pool}
    for name, spec in cur["systems"].items():
        if name not in by_name:
            sys.exit(f"curated system '{name}' not found")
        s = by_name[name]
        if "components" in spec:
            s["stars"] = [
                make_component(c["name"], c["spect"], None, c["luminosity"], c["mass"])
                for c in spec["components"]
            ]
        else:
            name_components(s)
            for star, cname in zip(s["stars"], spec.get("component_names", [])):
                star["name"] = cname
    for s in pool:
        if s["name"] not in cur["systems"]:
            name_components(s)

    core_ly = cur["core_radius_ly"]
    selected = [s for s in pool if math.hypot(*s["pos"]) <= core_ly]
    for name in cur["notable"] + [e["name"] for e in cur["extra_systems"]]:
        if name not in by_name:
            sys.exit(f"notable system '{name}' not found within {cur['rim_radius_ly']} ly")
        if by_name[name] not in selected:
            selected.append(by_name[name])
    rest = [s for s in pool if s not in selected]
    bridges = add_bridges(selected, rest, cur["bridge_max_lane_ly"], cur["max_systems"])

    selected.sort(key=lambda s: (math.hypot(*s["pos"]), s["name"]))
    for s in selected:
        s["id"] = slugify(s["name"])
    ids = [s["id"] for s in selected]
    if len(set(ids)) != len(ids):
        sys.exit("duplicate system ids")

    lanes = build_lanes(selected, cur["lanes"], overrides)
    pts = [s["pos"] for s in selected]
    lengths = sorted(((dist(pts[i], pts[j]), i, j) for i, j in lanes), reverse=True)
    adj = adjacency(len(selected), lanes)
    points = choke_points(adj, CHOKE_MIN_PART)

    out = {
        "credit": CREDIT,
        "systems": [
            {
                "id": s["id"],
                "name": s["name"],
                "pos": [round(c, 3) for c in s["pos"]],
                "stars": s["stars"],
            }
            for s in selected
        ],
        "lanes": [[selected[i]["id"], selected[j]["id"]] for i, j in lanes],
    }
    OUTPUT.write_text(json.dumps(out, indent="\t", ensure_ascii=False) + "\n")

    n = len(selected)
    print(f"systems: {n}  (core {sum(1 for s in selected if math.hypot(*s['pos']) <= core_ly)}, "
          f"bridges added {len(bridges)}, multi-star {sum(1 for s in selected if len(s['stars']) > 1)})")
    print(f"lanes: {len(lanes)}  mean degree {2 * len(lanes) / n:.2f}  "
          f"dead ends {sum(1 for a in adj if len(a) == 1)}")
    print("jump range -> usable lanes, reachable map:")
    for jump in RANGE_REPORT_LY:
        usable = [(i, j) for d, i, j in lengths if d <= jump]
        parts = sorted(components(adjacency(n, usable)), reverse=True)
        print(f"  {jump:4.1f} ly: {len(usable):3d} lanes, largest connected part "
              f"{parts[0]}/{n} systems")
    print("longest lanes:")
    for d, i, j in lengths[:6]:
        print(f"  {d:5.2f} ly  {selected[i]['name']} - {selected[j]['name']}")
    print(f"choke points (loss cuts off >= {CHOKE_MIN_PART} systems): {len(points)}: "
          + ", ".join(selected[i]["name"] for i in points))
    if bridges:
        print("bridge stars added: " + ", ".join(bridges))
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
