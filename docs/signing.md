# Подпись и provisioning (TokenTank)

Порядок настройки подписи для локальной разработки и релиза.

## Идентификаторы

| Что | Значение | Где зафиксировано |
|---|---|---|
| Bundle ID (app) | `com.tokentank.app` | `TokenTank.xcodeproj`, `App/TokenTank/Info.plist` |
| Bundle ID (appex) | `com.tokentank.app.widget` | `TokenTank.xcodeproj`, `App/TokenTankWidget/Info.plist` |
| App Group | `group.42WBZP5LHR.tokentank` | build setting `APP_GROUP_ID` (entitlements обоих таргетов и `AppGroupIdentifier` обеих Info.plist) |
| Keychain access group | `$(AppIdentifierPrefix)com.tokentank.shared` | entitlements обоих таргетов |
| Team ID | `42WBZP5LHR` | `DEVELOPMENT_TEAM` в проекте |

Формат access group — `$(AppIdentifierPrefix)com.tokentank.shared`, **не** `group.*`:
`group.*` — это App Groups, keychain access group строится с префиксом команды.

## Локальная разработка

- `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 42WBZP5LHR`.
- Capabilities регистрируются автоматически при сборке (`REGISTER_APP_GROUPS = YES`):
  App Groups и Keychain Sharing для `com.tokentank.app` / `com.tokentank.app.widget`.
- Entitlements обоих таргетов: App Sandbox, `network.client`, общий App Group,
  общий keychain access group; hardened runtime включён (`ENABLE_HARDENED_RUNTIME = YES`).

## Релиз (Developer ID, вне App Store)

1. В developer.apple.com: идентификаторы `com.tokentank.app` и `com.tokentank.app.widget`
   с capabilities App Groups (`group.42WBZP5LHR.tokentank`) и Keychain Sharing
   (`com.tokentank.shared`).
2. Сертификат **Developer ID Application** (учётка владельца команды `42WBZP5LHR`).
3. Provisioning-профиль **Developer ID** для `com.tokentank.app`, включающий обе
   capabilities (appex наследует подписи команды, отдельный профиль для appex не требуется).
4. В проекте: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Developer ID Application: <имя> (<team>)"`.
5. Hardened runtime уже включён; нотаризация и DMG — `scripts/build-dmg.sh` (M8).

Атрибуты ключей в Keychain (используются с M2): `kSecAttrAccessible =
.afterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable = false` — без iCloud Keychain.

## Debug-тулза (Tools/TokenTankProbe)

Отдельный таргет `TokenTankProbe` (command-line tool, вне архива/DMG): entitlements —
`Tools/TokenTankProbe/TokenTankProbe.entitlements`. **Sandbox для standalone-тулзы
не включён**: bare CLI без контейнера/профиля не инициализирует sandbox-профиль
(`libsystem_secinit: invalid sandbox profile data`), это ограничение платформы.
Тулза debug-only, ключ — только через stdin, вывод санитизируется (§9.4/§10).

## Смена команды (team ID)

Заменить значение в одном месте сборки + подпись:

1. `APP_GROUP_ID` в настройках проекта (`TokenTank.xcodeproj`) — значение идёт и в
   entitlements обоих таргетов (`$(APP_GROUP_ID)`), и в `AppGroupIdentifier` обеих
   Info.plist, откуда его читает `AppGroup.identifier` в TokenTankKit;
2. `DEVELOPMENT_TEAM` в настройках проекта.
