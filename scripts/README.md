# scripts/

- `make-fixture.sh` — probe-ответ → `Fixtures/` (префикс `live-`) + санитизация
  (§9.4). Режимы: `mimo-sk`, `mimo-tp`, `deepseek`, `kimi-cn`, `kimi-intl`,
  `kimi-admin`, `kimi-coding`. Тело
  замаскированного ответа печатается — **просмотреть глазами перед коммитом**
  (см. чек-лист §9.4: санитайзер маскирует только ключи, не идентификаторы).
- `sanitize-fixtures.sh` — маскирование секретных префиксов + провал при
  остатках (CI-гейт). Использует BSD `sed -i ''` — **macOS-only, не «чинить»
  под GNU-синтаксис**.
- `make-reference.sh` — регенерация эталонов VisualTests (M3.2).
- `build-dmg.sh` — сборка, notarization, stapling (M8).
