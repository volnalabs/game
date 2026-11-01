# TerraFront

Стратегия от студии VolnaLabs (прежнее рабочее название — «VolnaLabs: World Strategy»).

Однопользовательская офлайн-стратегия захвата территорий на Godot 4: реальная карта Земли и
регионы, вымышленные миры (Пелагия, Аварис, Расколотые миры), генератор новых миров и
стратегические AI-противники с разными характерами и уровнями сложности.

В игре: захват земли атаками и морскими десантами (в том числе вглубь чужой страны), экономика и
15 зданий, исследования и перки, оружие и ПВО (ракеты, авиаудары, артиллерия, ЭМИ, ядерное оружие с
радиоактивными осадками), дипломатия (союзы, пакты о ненападении, предательство, посылки и помощь
союзникам, командные партии), мета-прогрессия, справочник и подсказки, синтезированный звук,
переназначаемые клавиши, режимы цветов для нарушений цветового зрения.

Проект вырос из форка **RoWorld** (Roblox/Luau), который сам является модифицированной версией
**OpenFront**. Оригинальная Luau-реализация сохранена в `src/` как справочная. Новая игра — в `godot/`.

© OpenFront and Contributors · основано на RoWorld (© 2026 Snick Co.) · TerraFront от VolnaLabs · GNU AGPL v3 с
дополнительными условиями (см. `LICENSE`).

## Запуск

```bash
tools/get_godot.sh
```

Скрипт скачивает Godot 4.7.2 (MIT) в `~/.local/godot` и печатает путь. Дальше:

```bash
GODOT=$(tools/get_godot.sh)
$GODOT --path godot --import
$GODOT --path godot
```

Или откройте `godot/project.godot` в редакторе Godot 4.7 и нажмите F5.

Управление: ЛКМ по чужой/ничьей земле — атака выбранной долей армии (Q/E), по чужой земле без общей
границы — морской десант; ПКМ — информация о государстве, перетаскивание ПКМ/СКМ — камера; колесо —
масштаб; WASD — камера; B — строительство, 1–6 — быстрые постройки; пробел — пауза; +/− — скорость;
F1 — справочник; F3 — отладка AI; F5 — сохранить; Esc — меню. Все клавиши, кроме Esc, можно
переназначить: «Настройки → Управление».

Сборка для Windows/Linux — `docs/release/WINDOWS_EXPORT.md`.

## Проверки (headless)

```bash
$GODOT --headless --path godot -s res://tests/run_tests.gd
```

Unit-, интеграционные, UI- и AI-тесты (~7 мин).

```bash
$GODOT --headless --path godot -s res://scripts/tools/ai_sim_cli.gd -- --games 20 --map gen:continents:S --bots 8 --mode strategic_vs_legacy --seed 1
```

Серия AI-партий; режимы: `mixed`, `strategic_vs_legacy`, `hard_vs_easy`, `personalities`.

```bash
$GODOT --headless --path godot -s res://scripts/tools/bench_cli.gd -- --map earth --bots 40 --tribes 60
```

Замер производительности симуляции и рендера территорий.

```bash
xvfb-run -a $GODOT --rendering-driver opengl3 --path godot -s res://scripts/tools/screenshot_cli.gd -- /tmp/shots earth
```

Скриншоты всех экранов без участия человека.

```bash
$GODOT --headless --path godot -s res://scripts/tools/bake_maps.gd
```

Пересобирает вымышленные карты из `godot/data/map_specs/*.json`.

```bash
python3 tools/export_luau_maps.py
```

Повторный экспорт карт Земли и регионов из Luau-данных (нужны numpy, Pillow, zstandard).

## Документация

- `docs/original-project/REPOSITORY_AUDIT.md` — аудит оригинала и таблица соответствия механик
- `docs/game-design/GAME_DESIGN.md` — правила и экономика
- `docs/architecture/ARCHITECTURE.md` — устройство проекта
- `docs/ai/AI_DESIGN.md`, `docs/ai/AI_RESULTS.md` — устройство AI и результаты AI-симуляций
- `docs/maps/MAP_SYSTEM.md` — формат карт и генератор
- `docs/game-design/NAVAL_LANDINGS.md`, `WEAPONS.md`, `RESEARCH_AND_PERKS.md`, `DIPLOMACY.md`,
  `AUDIO.md`, `SETTINGS.md` — отдельные системы
- `docs/ui/UI_DESIGN.md` — интерфейс
- `docs/performance/PERFORMANCE.md` — замеры
- `docs/release/WINDOWS_EXPORT.md` — сборка и обязательства при распространении
- `docs/licensing/ASSET_LICENSES.md` — происхождение и лицензии ресурсов
