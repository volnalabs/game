#!/usr/bin/env python3
"""Exports the original RoWorld maps (public-domain Natural Earth + NOAA ETOPO1 data, built by
tools/maps/make_maps.py) into the VolnaLabs Godot map format: godot/data/maps/<id>/{map.json,
terrain.png, preview.png}. Also copies the flags those maps use into godot/assets/flags.

Original tile byte (src/shared/Core/WorldMap.luau): bit 7 land, bit 6 shore, bit 5 ocean, bits 0-4
magnitude (land elevation class 0-30, water depth). 0x9F = impassable.
New terrain.png (docs/maps/MAP_SYSTEM.md): R = terrain code (bits 0-3) | river (bit 4),
G = elevation 0-255, B = 0.

Usage (repo root): python3 tools/export_luau_maps.py   (needs numpy, Pillow, zstandard)
"""
import base64
import json
import os
import re
import shutil

import numpy as np
import zstandard
from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "godot", "data", "maps")
FLAGS_SRC = os.path.join(REPO, "assets", "flags")
FLAGS_DST = os.path.join(REPO, "godot", "assets", "flags")

DEEP, SHALLOW, LAKE, PLAINS, FOREST, HILLS, MOUNTAIN, DESERT, TUNDRA, ICE = range(10)

# id, Luau module path, projection (lat_top, tiles per degree of latitude) from tools/maps/make_maps.py MAPS
MAPS = [
    dict(id="earth", src="src/shared/Data/Maps/World.luau", lat_top=90.0 - 10 / (2000 / 360.0), ppd=2000 / 360.0,
         category="real", name=("Земля", "Earth"),
         desc=("Узнаваемая карта мира: шесть континентов, океаны, проливы и острова. 71 государство на выбор.",
               "A recognisable world map: six continents, oceans, straits and islands. 71 nations to choose from."),
         features=["continents", "oceans", "straits", "islands"], bots=(15, 50)),
    dict(id="europe", src="src/server/MapData/Europe.luau", lat_top=72.0, ppd=33.0, category="regional",
         name=("Европа", "Europe"),
         desc=("Плотная Европа с Средиземноморьем, Скандинавией и западом России.",
               "Crowded Europe with the Mediterranean, Scandinavia and western Russia."),
         features=["dense", "peninsulas", "inland_seas"], bots=(15, 40)),
    dict(id="asia", src="src/server/MapData/Asia.luau", lat_top=78.0, ppd=15.0, category="regional",
         name=("Азия", "Asia"),
         desc=("Огромный континент: Сибирь, Гималаи, Китай, Индия и острова Юго-Восточной Азии.",
               "A huge continent: Siberia, the Himalayas, China, India and the islands of South-East Asia."),
         features=["large", "mountains", "islands"], bots=(20, 55)),
    dict(id="africa", src="src/server/MapData/Africa.luau", lat_top=38.0, ppd=18.0, category="regional",
         name=("Африка", "Africa"),
         desc=("Монолитный континент с длинными сухопутными фронтами и Мадагаскаром.",
               "A solid continent with long land fronts and Madagascar."),
         features=["land_war", "large"], bots=(15, 40)),
    dict(id="north_america", src="src/server/MapData/NorthAmerica.luau", lat_top=75.0, ppd=18.0, category="regional",
         name=("Северная Америка", "North America"),
         desc=("Штаты и провинции США, Канады и Мексики, Карибские острова и арктический архипелаг.",
               "States and provinces of the USA, Canada and Mexico, the Caribbean and the Arctic archipelago."),
         features=["large", "arctic_islands", "caribbean"], bots=(15, 45)),
    dict(id="south_america", src="src/server/MapData/SouthAmerica.luau", lat_top=14.0, ppd=20.0, category="regional",
         name=("Южная Америка", "South America"),
         desc=("Анды, Амазония и пампа: длинный узкий континент с горным хребтом вдоль запада.",
               "The Andes, Amazonia and the pampas: a long continent with a mountain wall in the west."),
         features=["mountains", "land_war"], bots=(10, 30)),
]

RU = {
    "Alaska": "Аляска", "Yukon": "Юкон", "Nunavut": "Нунавут", "Quebec": "Квебек", "California": "Калифорния",
    "Texas": "Техас", "Greenland": "Гренландия", "Siberia": "Сибирь", "Yakutia": "Якутия", "Kamchatka": "Камчатка",
    "Mongolia": "Монголия", "Western Australia": "Западная Австралия", "Patagonia": "Патагония",
    "West Antarctica": "Западная Антарктида", "Antarctica": "Антарктида", "East Antarctica": "Восточная Антарктида",
    "China": "Китай", "India": "Индия", "United States": "США", "Indonesia": "Индонезия", "Pakistan": "Пакистан",
    "Brazil": "Бразилия", "Nigeria": "Нигерия", "Bangladesh": "Бангладеш", "Russia": "Россия", "Mexico": "Мексика",
    "Japan": "Япония", "Ethiopia": "Эфиопия", "Philippines": "Филиппины", "Egypt": "Египет", "Vietnam": "Вьетнам",
    "DR Congo": "ДР Конго", "Türkiye": "Турция", "Germany": "Германия", "Iran": "Иран", "Thailand": "Таиланд",
    "France": "Франция", "United Kingdom": "Великобритания", "Italy": "Италия", "South Africa": "ЮАР",
    "Tanzania": "Танзания", "Myanmar": "Мьянма", "Kenya": "Кения", "South Korea": "Южная Корея",
    "Colombia": "Колумбия", "Spain": "Испания", "Argentina": "Аргентина", "Ukraine": "Украина", "Algeria": "Алжир",
    "Sudan": "Судан", "Iraq": "Ирак", "Poland": "Польша", "Canada": "Канада", "Morocco": "Марокко",
    "Saudi Arabia": "Саудовская Аравия", "Uzbekistan": "Узбекистан", "Peru": "Перу", "Malaysia": "Малайзия",
    "Angola": "Ангола", "Ghana": "Гана", "Mozambique": "Мозамбик", "Yemen": "Йемен", "Nepal": "Непал",
    "Venezuela": "Венесуэла", "Madagascar": "Мадагаскар", "Cameroon": "Камерун", "Australia": "Австралия",
    "Taiwan": "Тайвань", "Sri Lanka": "Шри-Ланка", "Mali": "Мали", "Romania": "Румыния",
    "Uganda": "Уганда", "Ivory Coast": "Кот-д'Ивуар", "Burkina Faso": "Буркина-Фасо", "Malawi": "Малави",
    "Zambia": "Замбия", "Senegal": "Сенегал", "Chad": "Чад", "Zimbabwe": "Зимбабве", "Guinea": "Гвинея",
    "Rwanda": "Руанда", "Benin": "Бенин", "Tunisia": "Тунис", "South Sudan": "Южный Судан", "Somalia": "Сомали",
    "Sierra Leone": "Сьерра-Леоне", "Libya": "Ливия", "Eritrea": "Эритрея", "Congo": "Конго", "Liberia": "Либерия",
    "Central African Republic": "ЦАР", "Mauritania": "Мавритания", "Namibia": "Намибия", "Botswana": "Ботсвана",
    "Gabon": "Габон", "Lesotho": "Лесото", "Guinea-Bissau": "Гвинея-Бисау", "Equatorial Guinea": "Экваториальная Гвинея",
    "Eswatini": "Эсватини", "Djibouti": "Джибути", "Afghanistan": "Афганистан", "North Korea": "КНДР",
    "Syria": "Сирия", "Cambodia": "Камбоджа", "Jordan": "Иордания", "Azerbaijan": "Азербайджан",
    "United Arab Emirates": "ОАЭ", "Tajikistan": "Таджикистан", "Kyrgyzstan": "Киргизия",
    "Turkmenistan": "Туркмения", "Bhutan": "Бутан", "Krasnoyarsk Krai": "Красноярский край",
    "Sakha Republic": "Якутия", "Papua": "Папуа", "Övörkhangai": "Уверхангай",
    "Khanty-Mansi Autonomous Okrug": "Югра", "Altai Republic": "Алтай", "Zabaykalsky Krai": "Забайкалье",
    "East Nusa Tenggara": "Восточные Малые Зондские о-ва", "Shaanxi": "Шэньси", "Chelyabinsk": "Челябинск",
    "West Sumatra": "Западная Суматра", "Maharashtra": "Махараштра", "Irkutsk": "Иркутск", "Amur": "Амур",
    "Qinghai": "Цинхай", "West Kazakhstan": "Западный Казахстан", "Xinjiang": "Синьцзян",
    "Central Java": "Центральная Ява", "Pavlodar": "Павлодар", "Primorsky Krai": "Приморье",
    "Inner Mongolia": "Внутренняя Монголия", "Tomsk": "Томск", "Jiangsu": "Цзянсу",
    "Khabarovsk Krai": "Хабаровский край", "Hunan": "Хунань", "Karaganda": "Караганда",
    "Central Sulawesi": "Центральный Сулавеси", "North Kazakhstan": "Северный Казахстан",
    "Himachal Pradesh": "Химачал-Прадеш", "Khentii": "Хэнтий", "Zavkhan": "Завхан", "Aktobe": "Актобе",
    "Chhattisgarh": "Чхаттисгарх", "Aceh": "Ачех", "Sichuan": "Сычуань",
    "Netherlands": "Нидерланды", "Belgium": "Бельгия", "Greece": "Греция", "Czechia": "Чехия", "Sweden": "Швеция",
    "Portugal": "Португалия", "Hungary": "Венгрия", "Belarus": "Беларусь", "Austria": "Австрия",
    "Switzerland": "Швейцария", "Bulgaria": "Болгария", "Serbia": "Сербия", "Denmark": "Дания",
    "Finland": "Финляндия", "Slovakia": "Словакия", "Norway": "Норвегия", "Ireland": "Ирландия",
    "Croatia": "Хорватия", "Georgia": "Грузия", "Bosnia and Herzegovina": "Босния и Герцеговина",
    "Lithuania": "Литва", "Moldova": "Молдова", "North Macedonia": "Северная Македония", "Latvia": "Латвия",
    "Iceland": "Исландия", "Kostroma": "Кострома", "Volgograd": "Волгоград", "Murmansk": "Мурманск",
    "Tula": "Тула", "Arkhangelsk": "Архангельск", "Novgorod": "Новгород", "Krasnodar Krai": "Кубань",
    "Republic of Mordovia": "Мордовия", "Karelia": "Карелия", "Belgorod": "Белгород", "Bryansk": "Брянск",
    "Yaroslavl": "Ярославль", "Stavropol Krai": "Ставрополье",
    "Guatemala": "Гватемала", "Cuba": "Куба", "Dominican Republic": "Доминиканская Республика",
    "Nicaragua": "Никарагуа", "Panama": "Панама", "Newfoundland and Labrador": "Ньюфаундленд и Лабрадор",
    "Michigan": "Мичиган", "British Columbia": "Британская Колумбия", "Montana": "Монтана",
    "Baja California Sur": "Южная Нижняя Калифорния", "Northwest Territories": "Северо-Западные территории",
    "Nebraska": "Небраска", "Manitoba": "Манитоба", "Michoacán": "Мичоакан", "New Hampshire": "Нью-Гэмпшир",
    "Washington": "Вашингтон", "Alberta": "Альберта", "Ontario": "Онтарио", "Utah": "Юта", "Minnesota": "Миннесота",
    "New Mexico": "Нью-Мексико", "Saskatchewan": "Саскачеван", "Missouri": "Миссури", "Virginia": "Виргиния",
    "Nova Scotia": "Новая Шотландия", "Baja California": "Нижняя Калифорния", "Yucatán": "Юкатан",
    "Nuevo León": "Нуэво-Леон", "Chihuahua": "Чиуауа", "North Dakota": "Северная Дакота", "Louisiana": "Луизиана",
    "Florida": "Флорида", "Kentucky": "Кентукки", "Oaxaca": "Оахака", "Arizona": "Аризона", "Oklahoma": "Оклахома",
    "Colorado": "Колорадо", "Idaho": "Айдахо", "Wyoming": "Вайоминг", "Durango": "Дуранго", "Arkansas": "Арканзас",
    "Oregon": "Орегон", "Iowa": "Айова",
    "Chile": "Чили", "Ecuador": "Эквадор", "Paraguay": "Парагвай", "Uruguay": "Уругвай", "Guyana": "Гайана",
    "Suriname": "Суринам", "Alagoas": "Алагоас", "Tierra del Fuego": "Огненная Земля",
    "Rio de Janeiro": "Рио-де-Жанейро", "La Guajira": "Гуахира", "Apurímac": "Апуримак", "Tocantins": "Токантинс",
    "Amazonas": "Амазонас", "La Rioja": "Ла-Риоха", "Guainía": "Гуайния", "Paraná": "Парана", "Beni": "Бени",
    "Mato Grosso": "Мату-Гросу", "Chubut": "Чубут", "Pará": "Пара", "La Libertad": "Ла-Либертад", "Chocó": "Чоко",
    "Guárico State": "Гуарико", "Potosí": "Потоси", "La Pampa": "Ла-Пампа", "Maranhão": "Мараньян",
    "Goiás": "Гояс", "Acre": "Акри", "Bahia": "Баия", "Buenos Aires": "Буэнос-Айрес", "Santa Fe": "Санта-Фе",
    "Ceará": "Сеара", "Loreto": "Лорето", "Mato Grosso do Sul": "Мату-Гросу-ду-Сул", "Amapá": "Амапа",
    "Salta": "Сальта",
}

NATION_RE = re.compile(r'\{ name = "([^"]*)", flag = "([^"]*)", x = (\d+), y = (\d+) \}')


def read_luau(path):
    text = open(os.path.join(REPO, path), encoding="utf-8").read()
    w = int(re.search(r"\bwidth = (\d+)", text).group(1))
    h = int(re.search(r"\bheight = (\d+)", text).group(1))
    blob = re.search(r'\bterrain = "([^"]+)"', text).group(1)
    raw = zstandard.ZstdDecompressor().decompress(base64.b64decode(blob), max_output_size=w * h)
    tiles = np.frombuffer(raw, dtype=np.uint8).reshape(h, w)
    nations = [(m.group(1), m.group(2), int(m.group(3)), int(m.group(4))) for m in NATION_RE.finditer(text)]
    return w, h, tiles, nations


def convert(tiles, lat_top, ppd):
    h, w = tiles.shape
    land = (tiles & 0x80) != 0
    ocean = (tiles & 0x20) != 0
    mag = (tiles & 0x1F).astype(np.int32)
    lat = lat_top - (np.arange(h, dtype=np.float64) + 0.5) / ppd
    polar = np.repeat((np.abs(lat) > 62.0)[:, None], w, axis=1)
    code = np.full((h, w), DEEP, dtype=np.uint8)
    code[~land & ocean & (mag <= 2)] = SHALLOW
    code[~land & ~ocean] = LAKE
    code[land & (mag < 10)] = PLAINS
    code[land & (mag >= 10) & (mag < 20)] = HILLS
    code[land & (mag >= 20)] = MOUNTAIN
    code[land & polar & (mag < 20)] = TUNDRA
    code[tiles == 0x9F] = ICE
    elev = np.zeros((h, w), dtype=np.uint8)
    elev[land] = np.clip(mag[land] * 8, 0, 255).astype(np.uint8)
    rgb = np.zeros((h, w, 3), dtype=np.uint8)
    rgb[..., 0] = code
    rgb[..., 1] = elev
    return rgb


PREVIEW_COLORS = {
    DEEP: (38, 74, 112), SHALLOW: (58, 104, 142), LAKE: (64, 112, 150), PLAINS: (126, 160, 92),
    FOREST: (74, 118, 70), HILLS: (160, 150, 104), MOUNTAIN: (176, 170, 160), DESERT: (210, 188, 130),
    TUNDRA: (176, 186, 170), ICE: (232, 238, 242),
}


def preview(rgb, max_w=480):
    code = rgb[..., 0] & 0x0F
    img = np.zeros(rgb.shape, dtype=np.uint8)
    for c, col in PREVIEW_COLORS.items():
        img[code == c] = col
    im = Image.fromarray(img, "RGB")
    h, w = code.shape
    scale = max_w / w
    return im.resize((max_w, max(1, int(round(h * scale)))), Image.LANCZOS)


def landmass_stats(rgb):
    from collections import deque
    code = rgb[..., 0] & 0x0F
    land = (code >= PLAINS) & (code != ICE)
    h, w = land.shape
    seen = np.zeros_like(land, dtype=bool)
    sizes = []
    flat = land.ravel()
    seen_f = seen.ravel()
    for start in np.flatnonzero(flat):
        if seen_f[start]:
            continue
        q = deque([start])
        seen_f[start] = True
        n = 0
        while q:
            i = q.popleft()
            n += 1
            x, y = i % w, i // w
            for j, ok in ((i - 1, x > 0), (i + 1, x < w - 1), (i - w, y > 0), (i + w, y < h - 1)):
                if ok and flat[j] and not seen_f[j]:
                    seen_f[j] = True
                    q.append(j)
        sizes.append(n)
    total = int(land.sum())
    continents = sum(1 for s in sizes if s >= 0.02 * total)
    islands = sum(1 for s in sizes if s < 0.02 * total)
    return total, continents, islands


def main():
    os.makedirs(FLAGS_DST, exist_ok=True)
    used_flags = set()
    for spec in MAPS:
        w, h, tiles, nations = read_luau(spec["src"])
        rgb = convert(tiles, spec["lat_top"], spec["ppd"])
        out = os.path.join(OUT, spec["id"])
        os.makedirs(out, exist_ok=True)
        Image.fromarray(rgb, "RGB").save(os.path.join(out, "terrain.png"), optimize=True)
        preview(rgb).save(os.path.join(out, "preview.png"), optimize=True)
        land, continents, islands = landmass_stats(rgb)
        rows = []
        for i, (name, flag, x, y) in enumerate(nations):
            if not os.path.exists(os.path.join(FLAGS_SRC, flag + ".svg")):
                flag = ""
            if flag:
                used_flags.add(flag)
            rows.append({"id": "%s_%d" % (spec["id"], i), "name": {"ru": RU.get(name, name), "en": name},
                         "flag": flag, "x": x, "y": y})
        doc = {
            "id": spec["id"], "category": spec["category"],
            "name": {"ru": spec["name"][0], "en": spec["name"][1]},
            "description": {"ru": spec["desc"][0], "en": spec["desc"][1]},
            "features": spec["features"], "width": w, "height": h, "k_lin": 1.0,
            "recommended_bots": list(spec["bots"]), "max_bots": len(rows),
            "nations": rows, "balance": {"tribes_default": 60},
            "stats": {"land_tiles": land, "continents": continents, "islands": islands},
            "source": "Natural Earth + NOAA ETOPO1 via tools/maps/make_maps.py (exported by tools/export_luau_maps.py)",
            "license": "Public domain (map data)",
        }
        with open(os.path.join(out, "map.json"), "w", encoding="utf-8") as f:
            json.dump(doc, f, ensure_ascii=False, indent=1)
        print("%-14s %dx%d land=%d continents=%d islands=%d nations=%d" % (
            spec["id"], w, h, land, continents, islands, len(rows)))
    for flag in sorted(used_flags):
        shutil.copyfile(os.path.join(FLAGS_SRC, flag + ".svg"), os.path.join(FLAGS_DST, flag + ".svg"))
    with open(os.path.join(FLAGS_DST, "SOURCE.txt"), "w", encoding="utf-8") as f:
        f.write("Copied from assets/flags/ (see assets/flags/SOURCE.txt for each file's Wikimedia Commons source;\n"
                "all public domain or CC0). Only the flags used by the exported maps are copied.\n")
    print("flags:", len(used_flags))


if __name__ == "__main__":
    main()
