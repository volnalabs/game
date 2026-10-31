# Архитектура Godot-проекта

Движок: **Godot 4.7.2 stable** (MIT), язык — GDScript со статической типизацией. Проект — `godot/`.
Оригинальная Luau-реализация остаётся в `src/` как справочная.

## 1. Слои и зависимости

```
          ┌────────────── UI (scenes/menus, scenes/ui, scripts/ui) ──────────────┐
          │                                                                       │
          ▼ команды (Command)                                 события / чтение    │
   ┌─────────────────────────┐      tick()      ┌────────────────────────────┐    │
   │ MatchController (Node)  │ ───────────────► │ Sim (RefCounted, чистая)   │ ───┘
   │ SimClock: 10 Гц, ×speed │                  │  SimState, Territory       │
   └──────────┬──────────────┘                  │  AttackSystem, Naval       │
              │ кадр                            │  EconomySystem, Structures │
              ▼                                 │  SpawnSystem, Victory      │
   ┌─────────────────────────┐   dirty tiles    │  AIDirector (ai/**)        │
   │ MapRenderer (Node2D)    │ ◄─────────────── │  SimEvents (буфер событий) │
   └─────────────────────────┘                  └─────────────┬──────────────┘
                                                              │ читает
                                     ┌────────────────────────┴────────────────┐
                                     │ Rules (data/rules) · MapData (world/)    │
                                     │ MapRegistry/MapLoader (maps/) · SimRng   │
                                     └─────────────────────────────────────────┘
```

Правила зависимостей:
- `simulation/`, `military/`, `economy/`, `buildings/`, `rules/`, `world/`, `ai/` — **без Node**, без
  `Time`, без глобального `randi()`: только `SimRng`. Их можно запускать в headless-тестах и AI-sim.
- AI видит мир только через `ai/perception.gd` и действует только через `Command` — так же, как игрок.
- Рендер и UI читают состояние и `SimEvents`, но ничего не меняют напрямую.
- Числа баланса — в `data/**/*.json`; карты — в `data/maps/<id>/`; строки UI — в `data/i18n/strings.csv`.

## 2. Каталоги

| Каталог | Содержимое |
|---|---|
| `scripts/core` | `app.gd` (autoload `App`: машина состояний экранов), `match_config.gd`, `sim_rng.gd`, `settings.gd` (autoload), `log.gd` |
| `scripts/rules` | `rules.gd` — загрузка JSON, масштаб k_lin; `combat_math.gd` — формулы боя/роста (общие для Sim и AI) |
| `scripts/world` | `map_data.gd` — рельеф и производные массивы (land, water_body, coastal, landmass) |
| `scripts/maps` | `map_definition.gd`, `map_registry.gd` (autoload), `map_loader.gd` |
| `scripts/map_generator` | генератор миров, пресеты, анализ справедливости стартов, имена и флаги |
| `scripts/simulation` | `sim.gd` (оркестратор), `sim_state.gd`, `territory.gd`, `commands.gd`, `spawn_system.gd`, `victory.gd`, `sim_events.gd`, `state_hash.gd` |
| `scripts/military` | `attack_system.gd`, `front_queue.gd`, `naval_system.gd`, `landing_planner.gd`, `water_nav.gd` |
| `scripts/economy` | `economy_system.gd` |
| `scripts/buildings` | `structure_system.gd` (+ правила размещения) |
| `scripts/ai` | `ai_director.gd`, `ai_bot.gd`, `perception.gd`, `personality.gd`, `difficulty.gd`, `decision_log.gd`, `strategy/`, `tactics/`, `economy/`, `baseline/` |
| `scripts/rendering` | `map_renderer.gd`, шейдер территорий, камера, слои построек/надписей/эффектов |
| `scripts/ui` | тема (дизайн-система), контроллеры экранов, виджеты |
| `scripts/save_system` | `save_manager.gd`, формат и миграции |
| `scripts/tools` | CLI: `ai_sim_cli.gd`, `bench_cli.gd`, `bake_maps.gd`, `screenshot_cli.gd` |
| `tests` | мини-раннер `run_tests.gd` + `unit/`, `integration/`, `ai/`, `performance/` |

## 3. Симуляция

### 3.1 Тик (`Sim.step()`), 10 Гц
1. `tick += 1`; применить отложенные старты.
2. `EconomySystem.tick` — доход, содержание армии, рост войск (до приказов, как в оригинале).
3. Применить очередь `Command` (игрок и AI — одинаково, с валидацией).
4. `StructureSystem.tick` — завершение строительства.
5. `AIDirector.tick` — боты думают по своему расписанию и кладут `Command` в очередь следующего тика.
6. `AttackSystem.tick` — наступление фронтов, потери, аннексия, отступления.
7. `NavalSystem.tick` — движение транспортов, возврат отменённых, проверка места высадки (пересчёт маршрута или возврат войск), высадки.
8. Элиминации; `Victory.check` раз в 10 тиков.
9. `SimEvents` получает события (захват, атака, постройка, уничтожение, победа) и список изменённых тайлов.

### 3.2 Данные (`SimState`)
- На тайл: `owner: PackedInt32Array`, `border_next/prev: PackedInt32Array` (интрузивные списки
  границы, как в `SimState.luau`), `in_border: PackedByteArray`, `struct_at: PackedInt32Array`,
  `def_cover: PackedByteArray`, `front_mark: PackedInt32Array`.
- На владельца — packed-массивы по id (≤ 512): тайлы, ценность, войска, золото, снаряжение, кап,
  доход, upkeep, счётчики построек `id*8+kind`, bbox, центроид, статус, тип, характер.
- Структуры, атаки, транспорты — массивы небольших объектов (сотни, не миллионы).

### 3.3 Детерминизм
`SimRng` — обёртка над `RandomNumberGenerator` с явными `seed/state`, единственный источник случайности
Sim и AI. Итерация только по массивам (не по Dictionary с неупорядоченными ключами — у GDScript
порядок вставки детерминирован, но ключи ботов всё равно перебираются по id). `state_hash.gd` считает
хеш состояния для тестов «save → load → N тиков == N тиков» и воспроизводимости.

### 3.4 Готовность к мультиплееру
Все действия — сериализуемые `Command` (`to_dict/from_dict`), применяются в начале тика; Sim не знает,
откуда пришла команда. Для lockstep-сети потребуется только транспорт команд и подтверждение тика.

### Phase 2: модификаторы и исследования
`Sim` владеет `Modifiers` (статы государств из исследований, перков и построек) и `ResearchSystem`;
экономика, бой, флот и постройки читают модификаторы. Перки приходят только из `MatchConfig`. Мета-слой
(`scripts/meta/*`, автозагрузка `Profile`) живёт вне симуляции; см. `docs/progression/PROGRESSION.md`
и `docs/game-design/RESEARCH_AND_PERKS.md`.

## 4. Рендер
- **Рельеф** — одна статичная `ImageTexture` (RGBA8) из `MapData`, считается один раз.
- **Владельцы** — сетка чанков 256×256, у каждого `Image`/`ImageTexture` RGBA8: R,G — id владельца
  (16 бит), B — флаги (граница, выделение). Флаг границы считается на CPU при смене владельца (меняются
  и соседи), поэтому шейдер не читает соседние пиксели и швов между чанками нет. За кадр обновляются
  только грязные чанки (лимит по времени).
- **Цвета** — палитра 512×1 RGBA (id → цвет); подсветка выбранного/наведённого — uniform.
- **Постройки/надписи/фронты/транспорты** — `Node2D` с `_draw()` на десятки-сотни объектов,
  отрисовка только видимых (viewport culling).
- `Camera2D`: зум колесом к курсору, панорама правой/средней кнопкой и краями экрана, ограничение по карте.

## 5. Поток кадра и производительность
`MatchController._process(delta)`: аккумулятор `delta·speed`; пока ≥ 0.1 с — `sim.step()` (не более 4
шагов за кадр и не более 12 мс симуляции за кадр — при ×2/×4 игра чуть замедляется вместо падения
FPS), затем `renderer.flush(4 мс)`. AI-директор детерминированно ограничивает число стратегических
ботов, думающих за один тик (≤ 6).

Симуляция осталась в главном потоке: замеры (`docs/performance/PERFORMANCE.md`) дают на Земле
16 мс/тик в среднем при бюджете 100 мс, а безопасный перенос в `WorkerThreadPool` требует снимка
массивов для рендера (packed-массивы Godot — copy-on-write, параллельное чтение во время записи
копирует 8 МБ). Следующий шаг по измеренному узкому месту — C++ GDExtension для цикла атак.

## 6. Сохранения
`user://saves/<slot>.vsave`: magic `VLSV`, версия формата, JSON-заголовок (карта: id или параметры
генератора + seed + хеш рельефа; конфиг партии; дата; превью-статистика), затем ZSTD-сжатый
`var_to_bytes` словаря состояния (packed-массивы, владельцы, постройки, атаки с очередями фронтов,
транспорты, состояние RNG, память AI). При загрузке карта восстанавливается из реестра или
регенерируется по seed с проверкой хеша. `save_format.gd` содержит цепочку миграций `vN → vN+1`.
Настройки — `ConfigFile` (`user://settings.cfg`).

## 7. Тесты и CI
- `tests/run_tests.gd` (`extends SceneTree`) находит `tests/**/test_*.gd`, вызывает методы `test_*`,
  печатает итоги, код выхода ≠ 0 при падении. Без сторонних плагинов.
- `.github/workflows/godot-ci.yml`: скачивание Godot (`tools/get_godot.sh`), `--import`, тесты,
  smoke-запуск главной сцены, короткая AI-симуляция.
