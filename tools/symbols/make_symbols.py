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
Map variants (Phase 2A.3) separate the layers the map needs to stay readable on any territory colour:
  map_<lod> — the silhouette in white with a thin dark contour baked in (shape slightly smaller so
              the contour fits the 24-unit box),
  det_<lod> — the detail shapes alone in white (tinted in game with a dark shade of the owner colour).
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
# City: a skyline of three separate towers of different heights.
S["b_city"] = (
    [rect(2, 10, 5.5, 12, 1.5), rect(9.2, 2.5, 5.6, 19.5, 1.5), rect(16.5, 7, 5.5, 15, 1.5)],
    [rect(10.5, 6, 3, 2), rect(10.5, 10, 3, 2), rect(10.5, 14, 3, 2), rect(3.2, 13, 3, 2), rect(17.7, 10, 3, 2)],
    [rect(17.7, 14, 3, 2), rect(3.2, 17, 3, 2), rect(10.5, 18, 3, 2)])
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
# Defence post: a shield with a crenellated band.
S["b_defense"] = (
    [path("M12 1.5 L21 4.8 V11.5 C21 17 17.2 20.8 12 22.6 C6.8 20.8 3 17 3 11.5 V4.8 Z")],
    [rect(7, 7, 2.4, 3), rect(10.8, 7, 2.4, 3), rect(14.6, 7, 2.4, 3), path("M7 11.5 H17 V13 C17 16 14.8 18.2 12 19.2 C9.2 18.2 7 16 7 13 Z")],
    [])
# Research centre: a large round-bottomed laboratory flask.
S["b_research_center"] = (
    [circle(12, 15.2, 7.2), rect(9.8, 2.5, 4.4, 8, 1.2), rect(8.4, 1.6, 7.2, 2.4, 1)],
    [path("M5.6 15.8 A6.4 6.4 0 0 0 18.4 15.8 Z")],
    [circle(9.4, 12.6, 1)])
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
# Logistics hub: a supply truck (cargo box, cab, two wheels).
S["b_logistics_hub"] = (
    [rect(1, 5.5, 14, 11.5, 1.2), poly((15.8, 8.5), (19.6, 8.5), (22.6, 12.6), (22.6, 17), (15.8, 17)), rect(1, 15.5, 21.6, 2.6, 1),
     circle(6, 19.4, 2.7), circle(18.4, 19.4, 2.7)],
    [poly((17, 9.8), (19, 9.8), (21, 12.6), (17, 12.6)), circle(6, 19.4, 1), circle(18.4, 19.4, 1), rect(3, 8, 10, 1.5)],
    [rect(3, 11, 10, 1.5)])
# Command centre: a tall staff with a large swallow-tailed command flag on a small base.
S["b_command_center"] = (
    [rect(5, 1.5, 2.4, 20.5, 1), poly((7.4, 2), (21.5, 2), (17.5, 6.5), (21.5, 11), (7.4, 11)), rect(2, 19, 11, 3, 1.2)],
    [circle(12.5, 6.5, 1.6)],
    [])
# Bunker: a low armoured dome flush with the ground, with a firing slit.
S["b_bunker"] = (
    [path("M2 19 A10 8.5 0 0 1 22 19 Z"), rect(1, 18.5, 22, 3.5, 1.5)],
    [rect(6.5, 13.5, 11, 2.2)],
    [rect(11, 7.6, 2, 2)])
# Power plant: a bold lightning bolt.
S["b_power_plant"] = (
    [poly((14.5, 1), (3.5, 13.8), (10.6, 13.8), (7.6, 23), (20.5, 9.2), (13.4, 9.2), (17.4, 1))],
    [],
    [])
# Naval base: an anchor (the warship itself is shown by the ships on the water).
S["b_naval_base"] = (
    [circle(12, 4.6, 2.9), rect(10.8, 6, 2.4, 15.5, 1), rect(6, 8.6, 12, 2.4, 1.2),
     path("M2 12.5 L6.2 11.5 C6.6 16.6 9 19.3 12 19.8 C15 19.3 17.4 16.6 17.8 11.5 L22 12.5 C21.4 19.2 17.2 23 12 23 C6.8 23 2.6 19.2 2 12.5 Z")],
    [circle(12, 4.6, 1.2)],
    [])
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

# --- weapons (Phase 2E) ------------------------------------------------------------------------------
# Missile: a slim rocket climbing to the upper right, with fins.
S["w_missile"] = (
    [path("M19.5 2.5 C20.5 5.5 19.5 9 17 11.5 L9.5 19 L5 14.5 L12.5 7 C15 4.5 16.5 3.5 19.5 2.5 Z"),
     poly((7, 12.5), (3, 12), (1.5, 15), (4.5, 15.5)), poly((11.5, 17), (12, 21), (9, 22.5), (8.5, 19.5)), poly((5.5, 18.5), (2, 22), (3.5, 20.5))],
    [circle(15, 9, 1.4)],
    [])
# Heavy missile: a thick rocket with a blunt nose and four fins.
S["w_heavy_missile"] = (
    [path("M20.5 3.5 C21.5 7.5 20 11.5 17 14.5 L10.5 21 L3 13.5 L9.5 7 C12.5 4 16.5 2.5 20.5 3.5 Z"),
     poly((5.5, 11), (1, 10.5), (1, 15.5), (3, 15.5)), poly((13, 18.5), (13.5, 23), (8.5, 23), (8.5, 21)), rect(2, 19.5, 4, 2.5, 1)],
    [circle(15.5, 8.5, 1.8), rect(8.5, 13, 5, 1.6)],
    [])
# Cluster: a warhead opening into a fan of bomblets.
S["w_cluster"] = (
    [path("M3 21 L3 15 C3 11 6 8 10 8 L12 8 L12 14 C12 18 8 21 3 21 Z"), circle(16.5, 5, 2.4), circle(19.5, 11, 2.4), circle(15.5, 15.5, 2.4),
     circle(21, 18.5, 1.9)],
    [rect(6, 13, 3, 1.6)],
    [])
# Artillery: a field gun on a wheel, barrel raised.
S["w_artillery"] = (
    [poly((5, 15.5), (19.5, 4), (21.5, 6.5), (8, 18)), circle(8.5, 17.5, 4.6), rect(1.5, 20.5, 14, 2.5, 1.2)],
    [circle(8.5, 17.5, 1.6)],
    [])
# Air strike: a swept-wing jet diving to the lower left with a falling bomb.
S["w_air_strike"] = (
    [poly((21.5, 2.5), (14, 10), (5.5, 9), (4, 10.5), (12, 13), (10, 18.5), (12, 18.5), (15, 14), (17.5, 20), (19, 18.5), (17, 11.5)),
     path("M5 15.5 C6.5 15.5 7.5 17 7.5 18.5 L5.5 22 L3.5 18.5 C3.5 17 4 15.5 5 15.5 Z")],
    [],
    [])
# EMP: a ring with a lightning bolt across it.
S["w_emp"] = (
    [path("M12 2 A10 10 0 1 1 11.99 2 Z M12 5.2 A6.8 6.8 0 1 0 12.01 5.2 Z"),
     poly((13.5, 3), (7.5, 12.5), (11.2, 12.5), (9.5, 21), (16.5, 10.5), (12.8, 10.5), (15, 3))],
    [],
    [])
# Tactical nuke: the radiation trefoil.
S["w_tactical_nuke"] = (
    [circle(12, 12, 2.6), path("M12 9.4 L8.4 3.2 A10 10 0 0 1 15.6 3.2 Z"),
     path("M14.25 13.3 L20.8 13.3 A10 10 0 0 1 17.2 19.5 Z"), path("M9.75 13.3 L6.8 19.5 A10 10 0 0 1 3.2 13.3 Z")],
    [],
    [])
# Strategic nuke: a mushroom cloud.
S["w_strategic_nuke"] = (
    [path("M3 10.5 C3 5 7 2 12 2 C17 2 21 5 21 10.5 C21 12.5 19 13.5 16.5 13 C15.5 13 14.5 13.5 14.5 14.5 L14.5 18.5 L9.5 18.5 L9.5 14.5 C9.5 13.5 8.5 13 7.5 13 C5 13.5 3 12.5 3 10.5 Z"),
     rect(2, 19.5, 20, 3, 1.4)],
    [rect(7, 8, 10, 1.6)],
    [])
# MIRV: a bus releasing three warheads.
S["w_mirv"] = (
    [path("M12 1.5 C14 3 14.5 5 14.5 7 L14.5 10 L9.5 10 L9.5 7 C9.5 5 10 3 12 1.5 Z"),
     path("M4.5 13 C6 14 6.5 15.5 6.5 17 L6.5 21 L2.5 21 L2.5 17 C2.5 15.5 3 14 4.5 13 Z"),
     path("M12 13 C13.5 14 14 15.5 14 17 L14 21 L10 21 L10 17 C10 15.5 10.5 14 12 13 Z"),
     path("M19.5 13 C21 14 21.5 15.5 21.5 17 L21.5 21 L17.5 21 L17.5 17 C17.5 15.5 18 14 19.5 13 Z")],
    [],
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


OUTLINE = "#1c1a17"
MAP_SCALE = 0.8


def _group(parts, fill, stroke_w, scale, opacity=1.0):
    g = 'transform="translate(12 12) scale(%g) translate(-12 -12)"' % scale
    op = ' opacity="%g"' % opacity if opacity < 1.0 else ""
    return '<g %s%s fill="%s" stroke="%s" stroke-width="%g" stroke-linejoin="round" stroke-linecap="round">%s</g>' % (
        g, op, fill, fill, stroke_w, "".join(parts))


def map_svg(parts_white, soft, contour):
    # Contour first (same shapes, wider stroke, dark), the white silhouette on top.
    inner = _group(parts_white, OUTLINE, soft + 2.0 * contour, MAP_SCALE, 0.92) + _group(parts_white, "#ffffff", soft, MAP_SCALE)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">%s</svg>' % inner


def detail_svg(parts_dark):
    inner = _group(parts_dark, "#ffffff", 0.7, MAP_SCALE)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">%s</svg>' % inner


def main():
    out = {"_comment": __doc__.strip().splitlines()[0] + " Generated by tools/symbols/make_symbols.py.",
           "_license": "AGPL-3.0 (VolnaLabs own work)", "symbols": {}}
    for sid, (body, detail, near) in S.items():
        e = {"far": svg(body, [], 2.4), "full": svg(body, detail), "near": svg(body, detail + near)}
        if sid.startswith("b_"):
            e["map_far"] = map_svg(body, 1.0, 1.7)
            e["map_full"] = map_svg(body, 0.9, 1.3)
            e["map_near"] = map_svg(body, 0.9, 1.1)
            e["det_full"] = detail_svg(detail)
            e["det_near"] = detail_svg(detail + near)
        out["symbols"][sid] = e
    with open(OUT, "w") as f:
        json.dump(out, f, indent="\t")
        f.write("\n")
    print("symbols:", len(S), "->", OUT)


if __name__ == "__main__":
    main()
