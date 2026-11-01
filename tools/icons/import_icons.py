#!/usr/bin/env python3
"""Builds godot/data/ui/icons.json: the game's icon library (white SVGs, tinted in game).

Sources (licences verified, see docs/licensing/ASSET_LICENSES.md):
  - Game-icons.net via npm @iconify-json/game-icons — CC BY 3.0 (Lorc, Delapouite and contributors)
  - Tabler Icons via npm @tabler/icons — MIT (c) Paweł Kuna
Usage (repo root): python3 tools/icons/import_icons.py   (downloads the npm tarballs into build/icons)
"""
import io
import json
import os
import re
import tarfile
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "godot", "data", "ui", "icons.json")
LICENSES = os.path.join(REPO, "godot", "assets", "licenses")

# icon id -> game-icons name
GAME = {
    # (buildings and the main resources use the game's own symbols: tools/symbols/make_symbols.py)
    # weapons
    "w_missile": "incoming-rocket", "w_heavy_missile": "rocket-flight", "w_cluster": "cluster-bomb",
    "w_mirv": "missile-swarm", "w_tactical_nuke": "nuclear-bomb", "w_strategic_nuke": "mushroom-cloud",
    "w_artillery": "cannon-shot", "w_air_strike": "bombing-run", "w_emp": "lightning-dome",
    # resources and stats
    "r_credits": "crown-coin", "r_xp": "star-medal", "r_fragments": "crystal-cluster",
    # menu / meta
    "m_new_game": "planet-conquest", "m_profile": "person", "m_progress": "laurels", "m_cases": "locked-chest",
    "m_case_open": "open-treasure-chest", "m_inventory": "backpack", "m_research": "skills", "m_achievements": "trophy-cup",
    "m_encyclopedia": "open-book", "m_quests": "scroll-unfurled", "m_perks": "upgrade",
    # cosmetics: avatars (a_*), emblems (e_*), effects (fx_*)
    "a_recruit": "visored-helm", "a_soldier": "brodie-helmet", "a_knight": "black-knight-helm", "a_wolf": "wolf-head",
    "a_eagle": "eagle-head", "a_lion": "lion", "a_bear": "bear-head", "a_fox": "fox-head", "a_owl": "owl",
    "a_dragon": "dragon-head", "a_overlord": "overlord-helm", "a_astronaut": "astronaut-helmet", "a_skull": "crowned-skull",
    "a_spartan": "spartan-helmet",
    "e_eagle": "eagle-emblem", "e_hawk": "hawk-emblem", "e_swords": "swords-emblem", "e_wings": "winged-emblem",
    "e_stars": "star-formation", "e_laurel": "laurel-crown", "e_crown": "crown", "e_anchor": "anchor", "e_castle": "castle",
    "e_tower": "tower-flag", "e_banner": "knight-banner", "e_trident": "trident", "e_dragon": "dragon-spiral",
    "e_sun": "sun", "e_snow": "snowflake-2", "e_lightning": "lightning-trio", "e_flame": "flame", "e_oak": "oak",
    "e_compass": "compass", "e_rook": "chess-rook", "e_steelwing": "steelwing-emblem", "e_condor": "condor-emblem",
    "fx_firework": "firework-rocket", "fx_party": "party-flags", "fx_medal": "ribbon-medal", "fx_gem": "diamond-hard",
    # game concepts
    "g_attack": "crossed-swords", "g_defense": "checked-shield", "g_alliance": "shaking-hands", "g_peace": "peace-dove",
    "g_war": "crossed-sabres", "g_landing": "sailboat", "g_target": "on-target", "g_explosion": "spiky-explosion",
    "g_fallout": "nuclear-waste", "g_intel": "spyglass", "g_team": "team-idea", "g_reinforce": "team-upgrade",
    "g_leader": "crown", "g_capital": "flag-objective", "g_economy": "gold-stack", "g_military": "battle-tank",
    "g_logistics": "cargo-ship", "g_diplomacy": "allied-star", "g_strategic": "globe-ring", "g_tribe": "huts-village",
    "g_skull": "death-skull", "g_victory": "laurel-crown", "g_hourglass": "hourglass",
}
# icon id -> tabler outline name
TABLER = {
    "ui_play": "player-play", "ui_pause": "player-pause", "ui_fast": "player-track-next", "ui_close": "x",
    "ui_left": "chevron-left", "ui_right": "chevron-right", "ui_down": "chevron-down", "ui_up": "chevron-up",
    "ui_search": "search", "ui_filter": "filter", "ui_sort": "sort-descending", "ui_lock": "lock", "ui_check": "check",
    "ui_warning": "alert-triangle", "ui_info": "info-circle", "ui_clock": "clock", "ui_eye": "eye", "ui_eye_off": "eye-off",
    "ui_target": "target", "ui_map": "map", "ui_zones": "layers-intersect", "ui_users": "users", "ui_user": "user",
    "ui_settings": "settings", "ui_quit": "logout", "ui_load": "folder-open", "ui_save": "device-floppy",
    "ui_restart": "refresh", "ui_home": "home", "ui_menu": "menu-2", "ui_minus": "minus", "ui_plus": "plus",
    "ui_stats": "chart-bar", "ui_chart": "chart-line", "ui_book": "book", "ui_license": "license", "ui_world": "world",
    "ui_flag": "flag", "ui_swords": "swords", "ui_shield": "shield", "ui_building": "building", "ui_sparkles": "sparkles",
    "ui_gift": "gift", "ui_trophy": "trophy", "ui_star": "star", "ui_coin": "coin", "ui_packages": "packages",
    "ui_back": "arrow-back-up", "ui_keyboard": "keyboard", "ui_volume": "volume", "ui_palette": "palette",
    "ui_language": "language", "ui_adjust": "adjustments", "ui_collapse_left": "layout-sidebar-left-collapse",
    "ui_collapse_right": "layout-sidebar-right-collapse",
}


def npm_tarball(pkg):
    meta = json.load(urllib.request.urlopen("https://registry.npmjs.org/" + pkg))
    ver = meta["dist-tags"]["latest"]
    url = meta["versions"][ver]["dist"]["tarball"]
    data = urllib.request.urlopen(url).read()
    return ver, tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")


def main():
    gver, gtar = npm_tarball("@iconify-json/game-icons")
    gi = json.load(gtar.extractfile("package/icons.json"))
    size = gi.get("width", 512)
    tver, ttar = npm_tarball("@tabler/icons")
    out = {"_sources": {
        "game-icons": {"package": "@iconify-json/game-icons@" + gver, "license": "CC BY 3.0",
                        "attribution": "Icons by Lorc, Delapouite and contributors, https://game-icons.net (CC BY 3.0)"},
        "tabler": {"package": "@tabler/icons@" + tver, "license": "MIT", "attribution": "Tabler Icons (c) Pawel Kuna, MIT"}},
        "icons": {}}
    for key, name in sorted(GAME.items()):
        body = gi["icons"][name]["body"].replace("currentColor", "#ffffff")
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">%s</svg>' % (size, size, body)
        out["icons"][key] = {"svg": svg, "source": "game-icons", "name": name}
    for key, name in sorted(TABLER.items()):
        raw = ttar.extractfile("package/icons/outline/%s.svg" % name).read().decode()
        raw = raw.replace("currentColor", "#ffffff")
        raw = re.sub(r'\s+class="[^"]*"', "", raw)
        raw = re.sub(r"\s+", " ", raw).strip()
        out["icons"][key] = {"svg": raw, "source": "tabler", "name": name}
    # Keep the licence texts shipped with the packages next to the game's other licences.
    os.makedirs(LICENSES, exist_ok=True)
    # (@iconify-json/game-icons ships no licence file: game-icons_LICENSE.txt is a written notice.)
    with open(os.path.join(LICENSES, "tabler-icons_LICENSE.txt"), "wb") as f:
        f.write(ttar.extractfile("package/LICENSE").read())
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=0)
    print("icons:", len(out["icons"]), "->", OUT)


if __name__ == "__main__":
    main()
