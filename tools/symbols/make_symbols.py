#!/usr/bin/env python3
"""Builds godot/data/ui/symbols.json: VolnaLabs' own map and resource symbols (AGPL-3.0, own work).

One visual language for every building and resource (v2, Phase 2A.2): soft, rounded, filled
silhouettes on a 24-unit grid (tinted in game). Every shape is drawn with a same-colour stroke with
round joins and caps, so all corners are rounded; features are at least 2 units wide, no hairlines.
Dark "detail" shapes are soft cut-like accents. Each symbol has three levels of detail:
  far  — the silhouette only (legible at 10-12 px on a zoomed-out map),
  full — silhouette + main details (map at normal zoom, menus, inspector),
  near — full + small extra details (zoomed-in map, large previews).
The same symbol is used on the map, in the build menu, quick build, inspector, tooltips and the
encyclopedia (scripts/ui/symbols.gd via Icons).
Usage (repo root): python3 tools/symbols/make_symbols.py
"""
import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "godot", "data", "ui", "symbols.json")
DARK = "#2a2622"


def rect(x, y, w, h, r=0):
    return '<rect x="%g" y="%g" width="%g" height="%g" rx="%g"/>' % (x, y, w, h, r)


def poly(*pts):
    return '<polygon points="%s"/>' % " ".join("%g,%g" % p for p in pts)


def circle(cx, cy, r):
    return '<circle cx="%g" cy="%g" r="%g"/>' % (cx, cy, r)


def ellipse(cx, cy, rx, ry, rot=0):
    t = ' transform="rotate(%g %g %g)"' % (rot, cx, cy) if rot else ""
    return '<ellipse cx="%g" cy="%g" rx="%g" ry="%g"%s/>' % (cx, cy, rx, ry, t)


def path(d):
    return '<path d="%s"/>' % d


# id -> (body, detail, near_extra)
S = {}

# --- buildings -----------------------------------------------------------------------------------
# City: a block of three towers of different heights on a common ground line.
S["b_city"] = (
    [rect(2.5, 11, 5.5, 10, 2.2), rect(9.2, 4, 5.6, 17, 2.4), rect(16, 8, 5.5, 13, 2.2), rect(1.5, 19.5, 21, 2.5, 1.2)],
    [rect(10.5, 7, 3, 2), rect(10.5, 11, 3, 2), rect(10.5, 15, 3, 2), rect(3.5, 14, 3, 2), rect(17.5, 11, 3, 2)],
    [rect(17.5, 15, 3, 2), rect(3.5, 17.5, 3, 1.5)])
# Port: a pier over water with a dockside crane and a container.
S["b_port"] = (
    [rect(1, 14, 22, 3), rect(15, 3, 3, 11), rect(6, 3, 15, 2.6), rect(3, 9, 7, 5), rect(3, 17, 2.5, 5), rect(18.5, 17, 2.5, 5)],
    [rect(7.6, 5.6, 1.6, 3.4)],
    [rect(4.5, 10.5, 1.6, 2.5), rect(7.2, 10.5, 1.6, 2.5)])
# Factory: saw-tooth roof workshop and a tall chimney.
S["b_factory"] = (
    [poly((1, 21), (1, 11), (6, 14), (6, 11), (11, 14), (11, 11), (16, 14), (16, 21)), rect(17.5, 3, 4, 18)],
    [rect(3, 16, 2.5, 2.5), rect(7.5, 16, 2.5, 2.5), rect(12, 16, 2.5, 2.5)],
    [rect(17.5, 6, 4, 1.6)])
# Defence post: a crenellated fort wall with a gate.
S["b_defense"] = (
    [rect(3, 10, 18, 11), rect(3, 6, 4, 4), rect(10, 6, 4, 4), rect(17, 6, 4, 4)],
    [path("M9.5 21 V16.5 A2.5 2.5 0 0 1 14.5 16.5 V21 Z")],
    [rect(5, 12, 2, 2), rect(17, 12, 2, 2)])
# Research centre: a laboratory flask standing on a building base.
S["b_research_center"] = (
    [rect(3, 18, 18, 4, 1.5), circle(12, 12, 5.6), rect(10, 2.5, 4, 7, 1.2), rect(8.8, 2, 6.4, 2, 1)],
    [path("M7 12.6 A5 5 0 0 0 17 12.6 Z")],
    [circle(10.2, 9.6, 0.9)])
# Radar: a tilted dish on a mast with a tripod base.
S["b_radar"] = (
    [path("M2 7 A9.5 9.5 0 0 0 15 20 Z"), poly((8.6, 13.4), (17.6, 4.4), (19.4, 6.2), (10.4, 15.2)), circle(18.8, 4.6, 2.2),
     rect(12, 15, 3, 4), poly((7, 22.5), (20, 22.5), (17, 18.5), (10, 18.5))],
    [path("M5 9.4 A6.6 6.6 0 0 0 12.6 17 Z")],
    [])
# Airbase: a top-down plane over a runway.
S["b_airbase"] = (
    [poly((12, 1), (13.4, 3.5), (13.4, 8), (21, 11.5), (21, 13.3), (13.4, 11.8), (13.4, 15), (16, 16.6), (16, 18), (12, 17.2),
          (8, 18), (8, 16.6), (10.6, 15), (10.6, 11.8), (3, 13.3), (3, 11.5), (10.6, 8), (10.6, 3.5)),
     rect(1, 20, 22, 3)],
    [rect(3, 21, 3, 1), rect(8.5, 21, 3, 1), rect(14, 21, 3, 1), rect(19.5, 21, 2, 1)],
    [])
# Military academy: a classical portico with a star in the pediment.
S["b_military_academy"] = (
    [poly((1, 9), (12, 2.5), (23, 9)), rect(3, 10, 2.6, 9), rect(8, 10, 2.6, 9), rect(13.4, 10, 2.6, 9), rect(18.4, 10, 2.6, 9),
     rect(1, 19, 22, 3)],
    [poly((12, 4.2), (12.7, 5.9), (14.4, 5.9), (13, 6.9), (13.6, 8.5), (12, 7.5), (10.4, 8.5), (11, 6.9), (9.6, 5.9), (11.3, 5.9))],
    [])
# Logistics hub: a pyramid of three cargo crates.
S["b_logistics_hub"] = (
    [rect(1.8, 13, 9.2, 9, 1.6), rect(13, 13, 9.2, 9, 1.6), rect(7.4, 3, 9.2, 9, 1.6)],
    [rect(5.4, 13, 1.6, 9), rect(16.9, 13, 1.6, 9), rect(11.2, 3, 1.6, 9)],
    [rect(1.5, 16.7, 9.5, 1.4), rect(13, 16.7, 9.5, 1.4), rect(7.25, 6.7, 9.5, 1.4)])
# Command centre: a headquarters block with a tall mast and a pennant.
S["b_command_center"] = (
    [rect(2, 13, 20, 9, 2), rect(10.7, 2, 2.6, 11, 1.2), poly((13.3, 2.2), (20.5, 4.3), (13.3, 6.4)), rect(7, 10, 10, 3.5, 1.4)],
    [rect(4.5, 16, 3, 3), rect(16.5, 16, 3, 3), rect(10.5, 16, 3, 6)],
    [])
# Bunker: a low armoured dome flush with the ground, with a firing slit.
S["b_bunker"] = (
    [path("M2 19 A10 8.5 0 0 1 22 19 Z"), rect(1, 18.5, 22, 3.5, 1.5)],
    [rect(6.5, 13.5, 11, 2.2)],
    [rect(11, 7.6, 2, 2)])
# Power plant: a cooling tower and a lightning bolt.
S["b_power_plant"] = (
    [path("M4 22 C6.5 16 7.5 11 5.5 3 H18.5 C16.5 11 17.5 16 20 22 Z")],
    [poly((13.2, 6), (8.5, 13.5), (11.6, 13.5), (10.4, 19.5), (15.6, 11.4), (12.4, 11.4))],
    [])
# Naval base: a warship on the water.
S["b_naval_base"] = (
    [poly((1, 13), (23, 13), (19.5, 18), (4.5, 18)), rect(8, 8, 7, 5), rect(10.8, 3, 1.8, 5), rect(15, 10, 5, 1.8),
     rect(1, 20, 22, 2)],
    [rect(9.5, 9.5, 1.6, 1.6), rect(12, 9.5, 1.6, 1.6)],
    [rect(5, 14.6, 2, 1.4), rect(17, 14.6, 2, 1.4)])
# SAM: a launcher vehicle with two missiles raised.
S["b_sam"] = (
    [rect(2, 15, 20, 4.5), poly((5, 15), (13.5, 4.5), (15.8, 6.3), (8.2, 15)), poly((10, 15), (18.5, 4.5), (20.8, 6.3), (13.2, 15))],
    [circle(6, 20, 1.9), circle(12, 20, 1.9), circle(18, 20, 1.9)],
    [])
# Missile silo: an upright rocket rising from an open hatch.
S["b_silo"] = (
    [path("M12 1 C14.4 3.4 14.6 6 14.6 8 V16 H9.4 V8 C9.4 6 9.6 3.4 12 1 Z"), poly((9.4, 11), (6, 16), (9.4, 16)),
     poly((14.6, 11), (18, 16), (14.6, 16)), rect(2, 18, 20, 4), poly((1, 15), (5.5, 18), (2, 18)), poly((23, 15), (18.5, 18), (22, 18))],
    [rect(11, 6, 2, 2)],
    [])

# --- resources and stats --------------------------------------------------------------------------
S["r_gold"] = (
    [ellipse(9, 19, 7, 2.8), rect(2, 15, 14, 4), ellipse(9, 15, 7, 2.8), rect(2, 11, 14, 4), ellipse(9, 11, 7, 2.8),
     circle(17, 8, 6)],
    [rect(2, 14.2, 14, 1.3), rect(2, 18.2, 14, 1.3), ellipse(9, 11, 4.4, 1.4), circle(17, 8, 3.6)],
    [])
S["r_supplies"] = (
    [rect(2.5, 7, 19, 14.5, 2.2), poly((3, 7.5), (6.5, 2.5), (17.5, 2.5), (21, 7.5))],
    [rect(10.5, 7, 3, 15), rect(2, 13, 20, 2)],
    [])
S["r_army"] = (
    [circle(12, 7, 4.5), path("M3 22 C3 15 7 12.5 12 12.5 C17 12.5 21 15 21 22 Z")],
    [path("M7.5 6.5 A4.5 4.5 0 0 1 16.5 6.5 Z")],
    [])
S["r_research"] = (
    [circle(12, 15, 7), rect(9.8, 2.5, 4.4, 8, 1.4), rect(8.5, 2, 7, 2.2, 1.1)],
    [path("M5.6 15.5 A6.4 6.4 0 0 0 18.4 15.5 Z")],
    [])
S["r_land"] = (
    [poly((2, 8), (8, 3), (15, 5), (22, 3), (21, 12), (23, 19), (15, 21), (9, 19), (2, 21), (4, 13))],
    [poly((9, 9), (14, 8.5), (15, 13), (10, 14))],
    [])
S["r_upkeep"] = (
    [circle(12, 12, 10)],
    [rect(6.5, 10.5, 11, 3)],
    [])


def svg(parts_white, parts_dark, soft=1.6):
    # Shapes are slightly inset (0.92) so the rounding stroke stays inside the 24-unit box.
    g = 'transform="translate(12 12) scale(0.92) translate(-12 -12)"'
    inner = '<g %s fill="#ffffff" stroke="#ffffff" stroke-width="%g" stroke-linejoin="round" stroke-linecap="round">%s</g>' % (
        g, soft, "".join(parts_white))
    if parts_dark:
        inner += '<g %s fill="%s" stroke="%s" stroke-width="0.7" stroke-linejoin="round" stroke-linecap="round">%s</g>' % (
            g, DARK, DARK, "".join(parts_dark))
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">%s</svg>' % inner


def main():
    out = {"_comment": __doc__.strip().splitlines()[0] + " Generated by tools/symbols/make_symbols.py.",
           "_license": "AGPL-3.0 (VolnaLabs own work)", "symbols": {}}
    for sid, (body, detail, near) in S.items():
        out["symbols"][sid] = {"far": svg(body, [], 2.4), "full": svg(body, detail), "near": svg(body, detail + near)}
    with open(OUT, "w") as f:
        json.dump(out, f, indent="\t")
        f.write("\n")
    print("symbols:", len(S), "->", OUT)


if __name__ == "__main__":
    main()
