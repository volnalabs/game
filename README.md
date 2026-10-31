# TerraFront

Стратегия от студии VolnaLabs (прежнее рабочее название — «VolnaLabs: World Strategy»).

Однопользовательская офлайн-стратегия захвата территорий на Godot 4: реальная карта Земли и
регионы, вымышленные миры (Пелагия, Аварис, Расколотые миры), генератор новых миров и
стратегические AI-противники с разными характерами и уровнями сложности.

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

Управление: ЛКМ по чужой/ничьей земле — атака выбранной долей армии (Q/E), по чужому побережью
без общей границы — морской десант; ПКМ — информация о государстве, перетаскивание ПКМ/СКМ —
камера; колесо — масштаб; WASD — камера; 1–4 — постройки; пробел — пауза; +/− — скорость; F3 —
отладка AI; F5 — сохранить; Esc — меню.

## Проверки (headless)

```bash
$GODOT --headless --path godot -s res://tests/run_tests.gd
```

Unit-, интеграционные и AI-тесты (~4 мин).

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
- `docs/performance/PERFORMANCE.md` — замеры
- `docs/licensing/ASSET_LICENSES.md` — происхождение и лицензии ресурсов
