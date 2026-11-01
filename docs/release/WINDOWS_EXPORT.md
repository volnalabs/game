# Сборка для Windows (и Linux)

Пресеты экспорта лежат в `godot/export_presets.cfg`: **Windows** (`build/windows/TerraFront.exe`) и
**Linux** (`build/linux/TerraFront.x86_64`). Каталог `build/` в git не попадает. Игра собирается в один
исполняемый файл (PCK встроен), без папки `tests/`; в свойствах `.exe` — «TerraFront», «VolnaLabs»,
версия 0.2.0 и строка «© OpenFront and Contributors; TerraFront © VolnaLabs. GNU AGPL v3».

## Шаги
Всё делает один скрипт:
```bash
tools/release/package.sh          # версия берётся из godot/project.godot
```
Он скачивает Godot (`tools/get_godot.sh`) и только два нужных шаблона экспорта (`tools/get_templates.py`
читает из официального архива `Godot_v4.7.2-stable_export_templates.tpz` (~1,3 ГБ) лишь каталог и два
файла — около 180 МБ — HTTP-запросами по диапазонам), экспортирует обе платформы и собирает в
`build/release/`:
- `TerraFront-windows-x64.zip` — `TerraFront.exe`, `LICENSE.txt`, `README.txt`;
- `TerraFront-linux-x64.tar.gz` — `TerraFront.x86_64`, `LICENSE.txt`, `README.txt`;
- `SHA256SUMS.txt`.

Значок приложения — `godot/icon.ico` (в `.exe`, все 7 размеров) и `godot/icon.png` (окно), рисует
`tools/branding/make_icon.py`.

## Публикация
`.github/workflows/release.yml` запускается при пуше тега `vX.Y.Z` **или** при публикации релиза в
интерфейсе GitHub (Releases → Draft a new release → тег `vX.Y.Z` → Publish — тогда архивы
прикрепляются к этому релизу): проверяет, что тег совпадает с
`config/version`, гоняет тесты, собирает архивы этим же скриптом и создаёт GitHub Release с описанием из
раздела `[X.Y.Z]` файла `CHANGELOG.md`. Ссылки «Скачать» в README ведут на
`releases/latest/download/<архив>` и поэтому всегда указывают на последнюю версию.

Проверено в облаке (0.2.0): оба архива собираются; `.exe` — PE32+ x86-64 со значком и сведениями о
версии; Linux-сборка из архива запускается и отрабатывает меню без ошибок скриптов. Запуск `.exe` на
настоящей Windows в облаке недоступен.

## Обязательства при распространении (AGPL-3.0 + §7)
- Вместе со сборкой — текст `LICENSE` и предложение исходного кода (ссылка на репозиторий с той же
  версией или архив исходников). Перенос на Godot не снимает требований AGPL.
- Строка «© OpenFront and Contributors» видна в главном меню и титрах (есть в игре и в свойствах `.exe`).
- Игра не называется «OpenFront».
- Сторонние лицензии (Godot MIT, шрифт Rubik OFL, иконки CC BY 3.0 / MIT) выводятся на экране «Титры»;
  перечень — `docs/licensing/ASSET_LICENSES.md`.
- Подпись кода (codesign) не настроена: Windows SmartScreen покажет предупреждение для неподписанного
  файла. Публикация в магазинах и онлайн-сервисы не предусмотрены.
