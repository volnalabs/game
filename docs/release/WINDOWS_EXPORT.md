# Сборка для Windows (и Linux)

Пресеты экспорта лежат в `godot/export_presets.cfg`: **Windows** (`build/windows/TerraFront.exe`) и
**Linux** (`build/linux/TerraFront.x86_64`). Каталог `build/` в git не попадает. Игра собирается в один
исполняемый файл (PCK встроен), без папки `tests/`; в свойствах `.exe` — «TerraFront», «VolnaLabs»,
версия 0.2.0 и строка «© OpenFront and Contributors; TerraFront © VolnaLabs. GNU AGPL v3».

## Шаги
1. Godot 4.7.2: `GODOT=$(tools/get_godot.sh)`.
2. Шаблоны экспорта той же версии (официальные, MIT) — в
   `~/.local/share/godot/export_templates/4.7.2.stable/` (Windows: `%APPDATA%\Godot\export_templates\4.7.2.stable\`).
   Полный архив `Godot_v4.7.2-stable_export_templates.tpz` весит ~1,3 ГБ; нужны только
   `windows_release_x86_64.exe` (и `linux_release.x86_64` для Linux). В редакторе: «Редактор → Управление
   шаблонами экспорта → Скачать».
3. Импорт и экспорт:
   ```bash
   $GODOT --headless --path godot --import
   $GODOT --headless --path godot --export-release "Windows" ../build/windows/TerraFront.exe
   ```
   Значок и сведения о версии Godot 4.7 записывает в `.exe` сам (`application/modify_resources`),
   rcedit не нужен. Значок приложения пока не задан (`application/icon` пуст) — используется значок Godot.
4. Проверено в облаке (Phase 2G): экспорт Windows и Linux проходит; `.exe` — PE32+ x86-64 со
   сведениями о версии, в пакете данные игры, строки и звуки, тестов нет. Сборка Linux запускается и
   отрабатывает главное меню без ошибок скриптов. Запустить `.exe` в облаке нельзя (нет Windows) —
   это нужно проверить на настоящем ПК: запуск, меню, партия, сохранение в `%APPDATA%\Godot\app_userdata\TerraFront\`.

## Обязательства при распространении (AGPL-3.0 + §7)
- Вместе со сборкой — текст `LICENSE` и предложение исходного кода (ссылка на репозиторий с той же
  версией или архив исходников). Перенос на Godot не снимает требований AGPL.
- Строка «© OpenFront and Contributors» видна в главном меню и титрах (есть в игре и в свойствах `.exe`).
- Игра не называется «OpenFront».
- Сторонние лицензии (Godot MIT, шрифт Rubik OFL, иконки CC BY 3.0 / MIT) выводятся на экране «Титры»;
  перечень — `docs/licensing/ASSET_LICENSES.md`.
- Подпись кода (codesign) не настроена: Windows SmartScreen покажет предупреждение для неподписанного
  файла. Публикация в магазинах и онлайн-сервисы не предусмотрены.
