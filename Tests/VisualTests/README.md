# VisualTests — snapshot-рендер виджетов

Чистые SwiftUI-вью (`TokenTankWidgetUI`) + `ImageRenderer` → PNG, сравнение с
эталоном по пикселям с допуском (REQ-UI-15). Проверяются только пиксели:
логика состояний покрыта unit-тестами `ViewStateTests`.

## Политика эталонов (M3.2, решение)

Эталоны **генерируются локально и не коммитятся** (каталог `Reference/` в
`.gitignore`). Регенерация: `scripts/make-reference.sh`. Смысл — регресс визуала
внутри рабочей сессии/CI-кеша, а не хранение бинарных золотников в git.

## Спайк M3.1 (13.11.2026): что форсируется в ImageRenderer

| Механизм | Результат |
|---|---|
| `.environment(\.colorScheme, .light/.dark)` | **работает** — единственный форсинг темы |
| `NSAppearance.performAsCurrentDrawingAppearance` | нет эффекта |
| `NSApplication.appearance = darkAqua` | нет эффекта |
| `AppleIncreaseContrastEnabled` (process UserDefaults и global CFPreferences) | нет эффекта |
| `AppleReduceTransparencyEnabled` (process UserDefaults) | нет эффекта |
| `AppleAquaColorVariant` (process UserDefaults, вариант 6 = Graphite) | нет эффекта |
| `.environment(\.colorSchemeContrast, …)` | недоступно — свойство только для чтения |
| `.tint(.gray)` вместо акцента | работает, но это тинт-аппроксимация, не системный Graphite |

**Вывод:** автоматизированная
матрица — `{light, dark} × {3 обоев}` = 6 комбинаций на layout (вместо 24:
оси Graphite/Increase Contrast/Reduce Transparency через ImageRenderer не
воспроизводимы). Графит, Increase Contrast и Reduce Transparency проверяются
**вручную** в релизном прогоне и на живой системе —
это системные режимы, честнее зафиксировать их отсутствие в рендере, чем
имитировать.

## Обои

Бинарные фикстуры не хранятся: `RenderHarness.Wallpaper` генерирует детерминированные
подложки (`white` `#FFFFFF`, `dark` `#1C1C1E`, `colorful` — процедурный паттерн).
Контраст считается против фикстин (REQ-UI-14), не «в среднем по обоям».

## Локали

Каждый layout дополнительно снимается в `en` и `ru`; тексты
параметризованных вью разрешаются через `\.locale`, значения из `ViewStateBuilder`
форматируются с явной локалью.

## Запуск

```sh
xcodebuild test -scheme TokenTank -destination 'platform=macOS' -only-testing:VisualTests
scripts/make-reference.sh   # регенерация эталонов (VISUAL_TESTS_GENERATE=1)
```
