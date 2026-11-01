# TerraFront (VolnaLabs)

Игра называется **TerraFront** (прежнее рабочее название — «VolnaLabs: World Strategy»); VolnaLabs —
студия-разработчик.

Самостоятельная однопользовательская офлайн-стратегия на Godot 4 (папка `godot/`), выросшая из форка
RoWorld (Roblox/Luau). Исходники RoWorld удалены из рабочей ветки по решению владельца (релиз 0.2.0) и
доступны в истории git: коммит `8854e68` (`git show 8854e68:src/...`).

## Жёсткие правила

- **Никаких сторонних публикаций и деплоев**: Roblox (Open Cloud, Studio), `snick-announce`, вебхуки
  Discord — скрипты прежнего автора удалены, их инструкции (`docs/original-project/CLAUDE_UPSTREAM.md`)
  не действуют. Релиз TerraFront публикуется только workflow `.github/workflows/release.yml` по тегу
  `v*` и только с одобрения владельца.
- Код RoWorld в ветке больше не хранится; ссылки на `*.luau` в комментариях указывают на коммит `8854e68`.
- Лицензия: весь проект AGPL-3.0 с дополнительными условиями §7 (`LICENSE`): строка
  «© OpenFront and Contributors» должна оставаться видимой в главном меню/титрах; игра не может
  называться «OpenFront». Перенос кода с Luau на GDScript не снимает требований AGPL.
- Новые внешние ресурсы (шрифты, иконки, звуки, геоданные) — только с проверенной лицензией и записью
  в `docs/licensing/ASSET_LICENSES.md`. Непроверенные ресурсы оригинала не переносить.
- Git: работать в отдельной ветке, никогда не коммитить в `main`, не делать force push, не мерджить в
  `main` без одобрения владельца. Небольшие понятные коммиты.

## Проект

- Godot 4.7.2 stable: `tools/get_godot.sh` скачивает его в `~/.local/godot` и печатает путь.
- GDScript со статической типизацией; код и комментарии на английском, документация (`docs/`) — на
  русском, UI — русский с локализацией через `godot/data/i18n/strings.csv`.
- Симуляция (`godot/scripts/simulation`, `military`, `economy`, `buildings`, `rules`) — чистые
  `RefCounted`-классы: не трогают Node, сцены, время кадра и глобальный RNG. Все действия игрока и AI
  проходят через `Command`. Детерминизм по seed обязателен.
- Балансные числа — в `godot/data/**/*.json`, не в коде. Условия победы задаются только в `VictoryConfig`.

## Проверки перед коммитом

```bash
GODOT=$(tools/get_godot.sh)
$GODOT --headless --path godot --import
$GODOT --headless --path godot -s res://tests/run_tests.gd
```

Сводка архитектуры: `docs/architecture/ARCHITECTURE.md`; AI: `docs/ai/AI_DESIGN.md`; карты:
`docs/maps/MAP_SYSTEM.md`.
