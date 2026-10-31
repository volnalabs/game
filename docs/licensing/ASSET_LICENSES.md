# Лицензии и происхождение ресурсов

Правило проекта: в Godot-игру (`godot/`) попадают только ресурсы с проверенной лицензией, каждый —
строкой в этой таблице. Непроверенные ресурсы оригинала не переносятся; вместо них — собственные
процедурные/кодовые временные ресурсы.

## 1. Код и движок

| Компонент | Лицензия | Примечание |
|---|---|---|
| Код проекта (`godot/`, `tools/`, `src/`) | **AGPL-3.0 + доп. условия §7** (`LICENSE`) | производная работа от RoWorld / OpenFront. В главном меню и титрах — «© OpenFront and Contributors»; название «OpenFront» не используется |
| RoWorld (оригинальный Luau-код в `src/`) | AGPL-3.0 (© 2026 Snick Co., модификации OpenFront) | сохранён как справочная реализация |
| OpenFront | AGPL-3.0 + §7 | © OpenFront and Contributors |
| Godot Engine 4.7.2 | MIT (© 2014-present Godot Engine contributors; © 2007-2014 Juan Linietsky, Ariel Manzur) | текст лицензии и сторонние компоненты движка выводятся в экране «Титры» через `Engine.get_license_text()` / `Engine.get_copyright_info()`; копия — `godot/licenses/GODOT_LICENSE.txt` |

## 2. Ресурсы, используемые в Godot-игре

| Ресурс | Путь | Источник | Лицензия |
|---|---|---|---|
| Шрифт Rubik (Regular/Medium/Bold) | `godot/assets/fonts/Rubik-*.ttf` | Google Fonts (`fonts.gstatic.com/s/rubik/v31`), © 2015 The Rubik Project Authors | SIL OFL 1.1 (`godot/assets/fonts/OFL.txt`) |
| Флаги стран (SVG) | `godot/assets/flags/*.svg` | копия нужных файлов из `assets/flags/` — Wikimedia Commons, по `assets/flags/SOURCE.txt` | Public domain / CC0 (по файлу, см. `SOURCE.txt`; многие — «insignia»: официальные символы, свободны от авторского права, но их использование может ограничиваться иными законами) |
| Карта Земли и региональные карты | `godot/data/maps/{earth,europe,asia,africa,north_america,south_america}/` | экспорт из `src/shared/Data/Maps/World.luau`, `src/server/MapData/*.luau`, построенных `tools/maps/make_maps.py` из Natural Earth (1:10m/1:50m) и NOAA ETOPO1 | Public domain (Natural Earth — public domain; ETOPO1 — U.S. Government work). Атрибуция в титрах: «Made with Natural Earth. NOAA ETOPO1.» |
| Названия стран/регионов | `map.json` реальных карт | Natural Earth + ручной перевод на русский | Public domain / собственный перевод |
| Вымышленные карты (Pelagia, Avaris, Shattered Worlds) | `godot/data/maps/{pelagia,avaris,shattered_worlds}/` | собственные спецификации `godot/data/map_specs/*.json`, выпечка генератором проекта | AGPL-3.0 (собственная работа) |
| Процедурные флаги, иконки построек, эффекты | генерируются кодом (`flag_gen.gd`, `_draw()` в слоях рендера) | собственная работа | AGPL-3.0 |
| Тексты интерфейса | `godot/data/i18n/strings.csv` | собственная работа | AGPL-3.0 |

Звуков и музыки в первой версии нет.

## 3. Ресурсы оригинала, которые НЕ переносятся

| Ресурс оригинала | Почему не переносится |
|---|---|
| `assets/ui_icons/*` (47 PNG) | растеризованы из SVG Airfront неизвестного происхождения (возможно OpenFront) — лицензия не подтверждена |
| `assets/branding/*` | из `app_icon.svg` Airfront, происхождение неизвестно; бренд другого продукта |
| `assets/globe/*` | спутниковые текстуры Airfront неизвестного происхождения; 3D-глобус не нужен |
| `tools/glyphs`, `tools/fx` | из Airfront, происхождение неизвестно |
| Звуки (ids в `src/shared/Assets/*.luau`) | частично BedWars / Airship BedWars (проприетарные, не наши), частично Airfront без лицензии |
| Музыка Rodrigo Flores «Orchestral Ambients Bundle» | CC BY 4.0, купленный пакет — файлов в репозитории нет; не нужна в v0.1 |
| `src/client/.../CrateModel.luau` | меш сундука BedWars — проприетарный |
| `src/server/BotFaces.luau`, `make_bot_faces.py` | аватары реальных пользователей Roblox |
| `assets/shop_flags/art/*`, `assets/arsenal/renders/*` | AI-генерация под Roblox-магазин; к игре не относится |
| `assets/map_sprites`, `map_fx`, `rails`, `crate`, `ui_shapes`, `arsenal/fx|ui` | собственные процедурные ресурсы RoWorld (AGPL) — переносить можно, но стиль Roblox; в v0.1 заменены своим рендером |
| `assets/icons_src/github.svg` | торговая марка GitHub |
| Карты OpenFront в истории git (до коммита `3810059`) | не используются |

## 4. Атрибуция в игре
Экран «Титры» (`scenes/menus/credits.tscn`) и футер главного меню показывают:
- «© OpenFront and Contributors · основано на RoWorld (© 2026 Snick Co.) · GNU AGPL v3»;
- «Карты: Natural Earth, NOAA ETOPO1 (public domain)»;
- «Шрифт Rubik — SIL Open Font License 1.1»;
- «Флаги — Wikimedia Commons (public domain / CC0)»;
- «Godot Engine — MIT License» + полный текст лицензии движка и его сторонних компонентов.
