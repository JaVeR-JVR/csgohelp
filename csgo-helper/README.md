# CSGO Helper

Готовый к сборке помощник для **CS:GO legacy** на macOS: компенсация отдачи,
Snap Tap (SOCD) и авто-банихоп. Работает как меню-бар приложение или как
headless-процесс, умеет запускаться через LaunchAgent и Steam-обёртку.

> **Целевая игра — CS:GO legacy (Steam app 4465480), не CS2.**
> Помощник только синтезирует события ввода через CoreGraphics. Он не читает
> и не пишет память игры, не внедряет dylib, не анализирует сетевой трафик и
> не пытается обходить VAC. Макросы могут нарушать Steam Subscriber Agreement
> и правила серверов: используйте только офлайн или на приватных серверах.

---

## Содержание

1. [Возможности](#возможности)
2. [Быстрый старт](#быстрый-старт)
3. [Архитектура](#архитектура)
4. [Дерево проекта](#дерево-проекта)
5. [Паттерны отдачи](#паттерны-отдачи)
6. [Тайминги](#тайминги)
7. [Конфигурация](#конфигурация)
8. [CLI](#cli)
9. [Разрешения macOS](#разрешения-macos)
10. [LaunchAgent](#launchagent)
11. [Steam-обёртка](#steam-обёртка)
12. [HiDPI, мультимониторы, 64/128 tick](#hidpi-мультимониторы-64128-tick)
13. [Проверка и тесты](#проверка-и-тесты)
14. [Ограничения](#ограничения)
15. [Диагностика проблем](#диагностика-проблем)
16. [Сторонние данные](#сторонние-данные)

---

## Возможности

| Модуль | Что делает | Управление |
|---|---|---|
| Recoil | Компенсирует отдачу по таблице конкретного оружия | `Shift+1`, меню |
| Snap Tap | SOCD «последняя клавиша побеждает» + тормозной тап | `Shift+2`, меню |
| Bunny Hop | Импульсы Space при зажатом Space | `Shift+3`, меню |
| Master | Включает/выключает все модули | `Shift+I`, меню |
| Weapon | Ручной выбор одного из 33 профилей | `Shift+[` / `Shift+]`, меню |
| Echo | Локальный `echo` статуса в консоль игры | `Shift+0`, меню |

Горячие клавиши и инъекция работают **только когда активно окно CS:GO**.
При потере фокуса все синтетические клавиши отпускаются, модули
останавливаются, а незавершённый console echo отменяется.

Event tap работает в режиме `listen-only` и не поглощает нажатия: игра тоже
видит `Shift+1/2/3` и `Shift+I`. Если эти комбинации заняты игровыми биндами,
переназначьте хоткеи в секции `hotkeys` на свободные (например,
`ctrl+alt+1`).

Что принципиально **не** делается:

- чтение/запись памяти игры, поиск указателей, оверлеи;
- инъекция dylib, патчинг бинарника, hooking;
- aimbot, triggerbot, ESP, wallhack;
- анализ трафика, GSI-клиент, сетевое взаимодействие;
- маскировка, антидетект, обход VAC;
- `sv_cheats 1`, игровые консольные команды и отправка сообщений в чат.

Единственное обращение к консоли — локальная команда
`echo csgo-helper ...`, если `feedback.consoleEcho=true`. Она никогда не
использует `say` и не отправляет данные на сервер.

---

## Быстрый старт

Требования:

- macOS 13 или новее (проверено на macOS 27.2, Apple Silicon);
- Xcode Command Line Tools / Swift 5.9+ (проверено на Swift 6.3.1);
- установленный CS:GO legacy;
- Python 3.9+ только для пересборки паттернов и VPK-инструментов.

Сборка одной командой:

```bash
cd csgo-helper
make
```

Результат: `build/CSGOHelper.app` (ad-hoc подпись). Проверка:

```bash
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --selftest
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --list-weapons
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --diagnose
```

Пробный запуск без отправки событий:

```bash
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --dry-run --headless
```

Обычный запуск:

```bash
open build/CSGOHelper.app
```

При первом запуске:

1. Выдайте **Accessibility** и **Input Monitoring** для
   `CSGOHelper.app` в System Settings → Privacy & Security.
2. Перезапустите helper (TCC запоминает путь и подпись приложения).
3. Запустите CS:GO, выберите оружие в меню и проверьте работу на офлайн-карте.

Для постоянной работы:

```bash
make install
```

`make install` копирует приложение в `~/Applications/CSGOHelper.app`,
создаёт конфиг, устанавливает LaunchAgent и Steam-обёртку. После выдачи
разрешений выполните:

```bash
launchctl kickstart -k gui/$(id -u)/local.csgo.helper
```

Удаление:

```bash
make uninstall   # приложение, LaunchAgent и обёртка; конфиг/логи остаются
make purge       # ещё и конфиг/логи
```

---

## Архитектура

```
┌─────────────────────────────────────────────────────────────────────┐
│ NSApplication (LSUIElement, меню-бар)  или  headless CLI            │
│  StatusMenuController · PermissionGuidePanel · CLIOptions           │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────┐
│ HelperEngine (serial queue, timer 2 мс)                             │
│                                                                     │
│  CGEvent tap (listen-only, cgSessionEventTap)                       │
│    └─ PhysicalInputEvent ──► hotkeys / A-D / Space / LMB            │
│                                                                     │
│  GameFocusMonitor ── NSWorkspace + AXObserver + CGWindowList        │
│    └─ shouldInject: игра запущена и её окно активное                │
│                                                                     │
│  RecoilEngine ── таблица профиля + время удержания ЛКМ              │
│  SnapTap      ── SOCD + тормозной тап                               │
│  BunnyHop     ── импульсы Space                                     │
│  ConsoleFeedback ── `echo csgo-helper ...`                          │
│                                                                     │
│  EventInjector ── CGEvent.post(.cghidEventTap) + метка синтетики    │
└─────────────────────────────────────────────────────────────────────┘
          ▲                                      │
          │ config.json + patterns.json          ▼
   ~/Library/Application Support/CSGOHelper   игра получает ввод
```

Ключевые решения:

- **Event tap только слушает.** Физические события всегда доходят до игры;
  коррекции отправляются *после* них через `EventInjector`.
- Синтетические события помечаются `eventSourceUserData = "CSGOHELP"`.
  Event tap игнорирует эту метку, поэтому нет обратной связи и зацикливания.
- Все модули работают в одной serial-очереди `csgo-helper.engine`; таймер
  2 мс вызывает `tick()`, event tap передаёт события в ту же очередь.
- Время дедлайнов берётся из `MonotonicClock` (`mach_continuous_time`), а не
  из `CGEvent.timestamp`: у только что созданных событий timestamp равен 0.
- При потере фокуса, отзыве Accessibility или остановке движка выполняется
  `releaseAll`: синтетические клавиши отпускаются, чтобы не оставить игру в
  состоянии «зажата A» или «зажат Space».
- Если Input Monitoring выдан уже после запуска, движок замечает изменение
  разрешений (проверка раз в 2 с) и повторно поднимает event tap.

---

## Дерево проекта

```
csgo-helper/
├── Package.swift                         SwiftPM: core, CLI, test target
├── Makefile                              сборка .app, тесты, install/uninstall
├── README.md                             этот файл
├── THIRD_PARTY_NOTICES.md                MIT-лицензия spray.training
├── Config/
│   └── config.example.json               полный пример конфига
├── Resources/
│   ├── Info.plist                        LSUIElement, bundle id, версия
│   └── patterns.json                     готовые 33 профиля (генерируется)
├── LaunchAgents/
│   └── local.csgo.helper.plist           шаблон LaunchAgent
├── scripts/
│   └── steam-launch-wrapper.sh           запуск helper вместе с игрой
├── Sources/
│   ├── CSGOHelper/
│   │   ├── main.swift                    CLI, headless/GUI entrypoint, SIGTERM
│   │   ├── AppDelegate.swift             NSApplication lifecycle, фокус-политика
│   │   ├── StatusMenuController.swift    меню-бар, оружие, диагностика
│   │   └── PermissionGuidePanel.swift    немадальное окно разрешений
│   └── CSGOHelperCore/
│       ├── HelperEngine.swift            оркестрация, hotkeys, тик, статус
│       ├── RecoilEngine.swift            continuous / per-shot компенсация
│       ├── SnapTap.swift                 SOCD и тормозной тап
│       ├── BunnyHop.swift                импульсы Space
│       ├── ConsoleFeedback.swift         безопасный локальный echo
│       ├── InputTap.swift                listen-only CGEvent tap
│       ├── Injection.swift               EventInjector + InputInjecting
│       ├── FocusMonitor.swift            NSWorkspace/AXObserver/CGWindowList
│       ├── Weapon.swift                  модель профиля и PatternStore
│       ├── Config.swift                  схема JSON, валидация, ConfigStore
│       ├── KeyCodes.swift                key codes, Hotkey, HotkeyParser
│       ├── Permissions.swift             TCC, Secure Input, System Settings
│       ├── Diagnostics.swift             отчёт --diagnose
│       ├── SelfTest.swift                15 проверок --selftest
│       ├── GameInstall.swift             поиск Steam/CS:GO legacy, VPK
│       ├── Logger.swift                  файл/консоль, ротация
│       ├── InstanceLock.swift            один экземпляр helper
│       ├── Support.swift                 пути, AtomicFile, MonotonicClock
│       └── CLIOptions.swift              разбор аргументов и --help
├── Tests/CSGOHelperCoreTests/
│   ├── TestSupport.swift                 RecordingInjector, пути
│   ├── SmokeTests.swift                  базовый smoke
│   ├── ConfigTests.swift                 JSON, хоткеи, конверсия
│   ├── PatternTests.swift                каталог, интерполяция, provenance
│   └── ModuleTimingTests.swift           SOCD/bhop/recoil/echo тайминги
└── Tools/
    ├── build_patterns.py                 детерминированная сборка patterns.json
    ├── extract_game_data.py              read-only VPK v1/v2 reader
    └── data/
        ├── weapon_catalog.json           каталог 33 оружий и metadata
        └── spray_training_patterns.json  измеренные таблицы spray.training
```

`build/` и `.build/` — генерируемые каталоги, в поставку не входят.

### Назначение ключевых файлов

- `Sources/CSGOHelperCore/HelperEngine.swift` — единственное место, где
  сходятся фокус, хоткеи, ЛКМ и модули. Здесь же проверяется, что игра
  активна, и вызывается `releaseAll` при потере фокуса.
- `Sources/CSGOHelperCore/RecoilEngine.swift` — выбирает режим по
  `weapon.isAutomatic`: continuous по времени или per-shot по кликам.
- `Sources/CSGOHelperCore/InputTap.swift` — `tapCreate(options: .listenOnly)`;
  не может «съесть» ввод и не требует права изменять события, только слушать.
- `Sources/CSGOHelperCore/Config.swift` — все секции имеют `decodeIfPresent`,
  поэтому минимальный конфиг `{"version":1,"sensitivity":3.0}` валиден.
- `Sources/CSGOHelper/StatusMenuController.swift` — меню-бар, подменю 33
  оружий с маркерами `●` (measured) и `~` (heuristic), диагностика.
- `Tools/extract_game_data.py` — не изменяет игру; читает VPK v1/v2,
  поддерживает preload и внешние архивы `pak01_XXX.vpk`.

---

## Паттерны отдачи

### Что лежит в `Resources/patterns.json`

33 профиля, из них:

- **16 measured** — `ak47, m4a1, m4a1s, m4a4, aug, sg553, galil, famas, m249,
  mp9, mp7, ump45, p90, mac10, cz75, bizon`;
- **17 heuristic** — `awp, g3sg1, scar20, negev, mp5sd, glock18, usps, p250,
  deagle, fiveseven, tec9, dualberettas, revolver, p2000, nova, xm1014, mag7`.

У каждого профиля есть:

- `cumulativeDegrees` — кумулятивная поправка в градусах, одна точка на
  выстрел, первая точка всегда `[0, 0]`;
- `perShotDegrees` — разности соседних точек для полуавтоматов;
- `quality`: `measured` или `heuristic`;
- `patternSource` и `sourcePattern` — происхождение данных.

### Измеренные таблицы: spray.training (MIT)

Исходник — проект
[RoyZ-iwnl/spray.training](https://github.com/RoyZ-iwnl/spray.training),
файл `js/weapons.js`, лицензия MIT, copyright (c) 2018 Robin Park.
Таблицы в исходнике заданы в экранных пикселях как
`[horizontal, vertical-up]`. Пересчёт в координаты мыши:

```text
x = -horizontal * 0.029
y = +vertical   * 0.029
```

Почему так:

- `horizontal > 0` — паттерн уходит вправо; компенсация должна двигать мышь
  влево, поэтому знак минус;
- `vertical-up > 0` — паттерн уходит вверх; в координатах macOS `+y` — вниз,
  поэтому компенсация получает положительный `y`;
- `0.029` градуса на исходную единицу подобрана по геометрии таблиц и
  проверяется `--selftest`; при необходимости её можно изменить в
  `Tools/build_patterns.py` (`DEGREES_PER_UNIT`) и пересобрать паттерны.

Скрипт `Tools/build_patterns.py`:

1. читает каталог `Tools/data/weapon_catalog.json`;
2. для оружия с `sourcePattern` берёт измеренную таблицу;
3. обрезает/дополняет её до размера магазина;
4. считает `perShotDegrees`;
5. для остальных строит детерминированную эвристику;
6. пишет `Resources/patterns.json` с provenance и счётчиками.

Запуск:

```bash
make patterns
```

Скрипт детерминирован: одинаковый вход даёт одинаковый JSON (без времени и
случайных зёрен от системы).

### Steam guide 2830373896

Гайд [Steam Community id=2830373896](https://steamcommunity.com/sharedfiles/filedetails/?id=2830373896)
используется как справочник и источник для валидации формы паттернов. В нём
нет машиночитаемых таблиц, поэтому числа из скриншотов не выдумывались и в
поставку не включались. Если вы хотите добавить свои измерения:

1. положите кумулятивную таблицу в `Tools/data/spray_training_patterns.json`
   (или в новый файл) в формате `cumulative_px`;
2. укажите ключ в `sourcePattern` соответствующего оружия в
   `Tools/data/weapon_catalog.json`;
3. выполните `make patterns && make check`;
4. проверьте, что `quality` стало `measured`, а `--selftest` проходит.

### Эвристика

Для 17 профилей используется детерминированная кривая:

- вертикальный подъём `total_y * t^exponent` с небольшим синусоидальным
  возмущением, монотонный по `y`;
- горизонтальное качание из двух синусов и seeded random walk;
- seed = первые 8 байт SHA-256 от `csgo-helper-fallback-v1:<weapon_id>`;
- амплитуда и exponent зависят от класса (`rifle`, `smg`, `lmg`, `sniper`,
  `pistol`, `shotgun`).

Это **не телеметрия** и не выдаётся за неё: `quality=heuristic`,
`patternSource="детерминированная fallback-эвристика v1 (не телеметрия)"`. Для
полуавтоматов и дробовиков эвристика особенно приблизительна; регулируйте
`recoil.intensity` и проверяйте на офлайн-карте.

### VPK и игровые скрипты

`Tools/extract_game_data.py` — read-only читатель VPK v1/v2. Он умеет:

```bash
python3 Tools/extract_game_data.py \
  --game "$HOME/Library/Application Support/Steam/steamapps/common/csgo legacy" --list

python3 Tools/extract_game_data.py \
  --game "$HOME/Library/Application Support/Steam/steamapps/common/csgo legacy" \
  --scan-weapons --out /tmp/weapons.json

python3 Tools/extract_game_data.py \
  --vpk "<...>/csgo/pak01_dir.vpk" \
  --extract "scripts/items/items_game.txt" --out-dir /tmp/csgo_scripts
```

На проверенной установке legacy VPK — версия 2, 133 676 записей, tree size
15 238 319. Файлов `scripts/weapon_*.txt` и `scripts/items/items_game.txt` в
нём нет. Поэтому metadata оружия берётся из каталога, а fallback-эвристика
обязательна: helper не притворяется, что «нашёл» паттерны в игре.

Инструмент никогда не пишет в установку игры и не читает память процесса.

---

## Тайминги

### Движок и фокус

| Параметр | Значение | Где |
|---|---:|---|
| Тик движка | 2 мс, leeway 150 µs | `HelperEngine.startTimer` |
| Проверка TCC | каждые 2 с | `HelperEngine.tick` |
| Опрос фокуса | 500 мс + NSWorkspace/AXObserver | `FocusConfig.pollIntervalMs` |
| Публикация статуса | не чаще 4 раз/с | `HelperEngine.emitStatus` |
| Проверка Secure Input | при каждом `Permissions.status()` | `Diagnostics`/`--permissions` |

### Recoil

| Параметр | Значение по умолчанию | Смысл |
|---|---:|---|
| `holdThresholdMs` | 120 мс | до этого ЛКМ не двигает мышь |
| `semiAutoShotDelayMs` | 18 мс | задержка компенсации полуавтомата |
| `burstResetMs` | 420 мс | пауза, после которой серия полуавтомата начинается с 1-го выстрела |
| `maxCountsPerTick` | 260 | предохранительный clamp на тик |
| `patternTimeScale` | 1.0 | масштаб времени таблицы |
| Интерполяция | по RPM | `60 / rpm` на выстрел |

Автоматические стволы: цель берётся из `cumulative(at: elapsed * scale)`,
где `elapsed` — время с физического нажатия ЛКМ. Первый выстрел не
компенсируется. Полуавтоматы/bolt/pump: один инкремент на клик, без
предположения о темпе магазина.

### Snap Tap

| Параметр | Значение |
|---|---:|
| `holdMs` | 22 мс |
| `cooldownMs` | 65 мс |
| Клавиши по умолчанию | A = 0, D = 2 (ANSI/ISO) |
| Логика | последняя нажатая побеждает; отпускание последней — тормозной тап противоположной |

При одновременном A+D в игру отправляется key-up более старой клавиши.
Когда новая клавиша отпускается, всё ещё физически зажатая старая
восстанавливается. Синтетические события помечены и не участвуют в SOCD.

### Bunny Hop

| Параметр | Значение |
|---|---:|
| `tickRate` | 128 (или 64) |
| `startDelayMs` | 60 мс |
| `pressHoldMs` | 8 мс |
| `pulseIntervalTicks` | 2 |
| Интервал при 128 tick | 15.625 мс |
| `predictiveAirtimeMs` | 760 мс |
| `predictiveWindowMs` | 180 мс |
| Первый импульс в predictive | 760 − 180/2 = 670 мс |
| `maxContinuousHoldMs` | 8000 мс |

Внешний процесс не знает ground state, поэтому bhop — тайминговый помощник,
а не гарантированный auto-jump. `spam` начинает почти сразу, `predictive`
ждёт ожидаемое окно приземления. Оба режима стоит проверять на офлайн-карте.

### Console echo

| Шаг | Задержка |
|---|---:|
| Нажатие/отпускание клавиши консоли | 15 мс |
| Ожидание открытия консоли | `openDelayMs` = 120 мс |
| Печать символа | `typeDelayMs` = 9 мс |
| Ожидание перед закрытием | 120 мс |
| Нажатие/отпускание клавиши консоли | 15 мс |
| `closeConsoleAfterMs` | 900 мс |

Команда: `echo csgo-helper <sanitized>`. Разрешены только строчные ASCII,
цифры и ` -_.=/[]()`; `;`, кавычки, backtick и переводы строк заменяются,
поэтому нельзя выполнить вторую команду или открыть чат. `say` не
используется.

---

## Конфигурация

По умолчанию:

```text
~/Library/Application Support/CSGOHelper/config.json
```

Полный пример — `Config/config.example.json`. Минимальный валидный конфиг:

```json
{"version":1,"sensitivity":3.0}
```

Недостающие секции подставляются значениями по умолчанию.

### Чувствительность

```text
countsPerDegreeX = 1 / (sensitivity * mYaw)
countsPerDegreeY = 1 / (sensitivity * mPitch)
```

`sensitivity` — чувствительность мыши в игре, `mYaw`/`mPitch` — параметры
CS:GO (по умолчанию 0.022). Если в игре стоит `sensitivity 2.5`, оставьте
`2.5`; если меняете — обновите конфиг. `intensity` масштабирует поправку
(0 — выключено, 1 — номинал, >1 — сильнее). Начинайте с `0.8–1.0` и
проверяйте на стене.

### Секции

- `recoil` — оружие, интенсивность, пороги, clamp, `patternTimeScale`,
  `compensateDuringFeedback` (по умолчанию false: во время echo отдача не
  компенсируется, чтобы не печатать в консоль с движущейся мышью).
- `snapTap` — SOCD, тормозной тап, key codes, `requirePhysicalEvent`.
- `bunnyHop` — режим, tick rate, задержки, лимит удержания.
- `hotkeys` — строки вида `"shift+i"`, `"shift+1"`, `"shift+[`,
  `"ctrl+alt+h"`; обязателен хотя бы один модификатор; дубли запрещены.
- `feedback` — `consoleEcho`, `openConsole`, `textMode` (`keycode` —
  US-раскладка, `unicode` — fallback), задержки, key codes.
- `focus` — bundle id, имена процессов, фрагменты заголовков, интервал
  опроса, `releaseKeysOnFocusLoss`.
- `logging` — уровень, файл, консоль, размер до ротации, `dryRun`.

Конфиг валидируется при загрузке и сохранении: отрицательная
чувствительность, tick rate не 64/128, `holdMs` вне 5–100, дубли хоткеев и
т.п. отклоняются с понятной ошибкой.

---

## CLI

```text
csgo-helper [команда] [опции]
```

| Команда | Назначение |
|---|---|
| без команды | GUI меню-бар; с `--headless` — консольный режим |
| `--selftest` | 15 проверок паттернов, конфига, хоткеев, echo |
| `--list-weapons` | таблица 33 профилей и источников |
| `--diagnose` | система, TCC, конфиг, паттерны, игра, LaunchAgent, логи |
| `--print-config` | создать/показать конфиг |
| `--permissions` | состояние Accessibility/Input Monitoring/Secure Input |
| `--request-permissions` | запросить TCC-диалоги и выйти |
| `--help`, `--version` | справка/версия |

Опции:

```text
--config PATH          конфиг JSON
--patterns PATH        patterns.json
--weapon ID            стартовое оружие (ak47, m4a4, ...)
--dry-run              не отправлять события, только логировать
--log [PATH]           писать лог в файл
--log-level LEVEL      trace|debug|info|warn|error|off
--headless             без меню-бара, статус в stdout
--wait-for-game        ждать окно игры (для LaunchAgent)
--exit-on-game-exit    выйти после завершения игры (для Steam-обёртки)
--quiet                не дублировать лог в stderr
--no-log               не писать файл лога
--request-permissions  запросить разрешения при старте
```

Примеры:

```bash
# Полная проверка
make check

# Безопасный прогон
./build/CSGOHelper.app/Contents/MacOS/csgo-helper \
  --headless --dry-run --weapon ak47 --log /tmp/csgo-helper.log

# Диагностика
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --diagnose

# Установка LaunchAgent
make install
```

`--dry-run` логирует решения модулей, но не вызывает `CGEvent.post`.
`--headless` не создаёт NSApplication; сигналы SIGINT/SIGTERM корректно
останавливают движок и отпускают клавиши.

---

## Разрешения macOS

Нужны два разрешения:

1. **Accessibility** — отправка `CGEvent` (клавиши и относительное движение
   мыши).
2. **Input Monitoring** — listen-only event tap для Shift+I, Shift+1/2/3,
   Shift+[ / ], A, D, Space и ЛКМ.

Проверка:

```bash
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --permissions
```

Запрос диалогов:

```bash
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --request-permissions
```

Или вручную:

```text
System Settings → Privacy & Security → Accessibility
System Settings → Privacy & Security → Input Monitoring
```

Важно:

- TCC привязан к **пути и подписи** приложения. Запускайте
  `~/Applications/CSGOHelper.app` (после `make install`) или
  `build/CSGOHelper.app`, но не голый бинарник из `.build`.
- Пересборка и повторная ad-hoc подпись могут потребовать повторной выдачи
  разрешений. После `make install` проверьте путь в списке TCC.
- LaunchAgent не показывает TCC-диалоги надёжно. Выдайте разрешения вручную,
  затем `launchctl kickstart -k`.
- Если включён **Secure Input** (терминал с вводом пароля, менеджер паролей,
  некоторые поля браузера), клавиатурный event tap может не получать
  события. `--permissions` и `--diagnose` показывают `Secure Input: ВКЛ`.
  Закройте такое приложение и перезапустите helper.
- Если разрешение отозвано во время работы, движок отпускает синтетические
  клавиши и останавливает модули. После выдачи заново event tap поднимется
  автоматически, но для надёжности можно нажать «Перезапустить перехват
  ввода» в меню.
- При отказе в разрешениях helper не падает: меню-бар показывает значок
  предупреждения, `--diagnose` объясняет, чего не хватает, а `--dry-run`
  продолжает работать.

### Почему ad-hoc подпись

Проект не использует платный Developer ID. `make` вызывает
`codesign --force --deep --sign -`. Этого достаточно для локального запуска,
но при каждом изменении кода TCC может считать приложение новым. Для
стабильной работы используйте постоянный путь `~/Applications` и не
пересобирайте приложение без необходимости.

---

## LaunchAgent

Шаблон: `LaunchAgents/local.csgo.helper.plist`. `make install` подставляет
пути и загружает агент:

```text
~/Library/LaunchAgents/local.csgo.helper.plist
~/Applications/CSGOHelper.app
~/Library/Application Support/CSGOHelper/config.json
~/Library/Logs/CSGOHelper/
```

Параметры:

- `RunAtLoad` — запуск при входе;
- `KeepAlive.SuccessfulExit=false` — перезапуск после ошибки, но не после
  нормального выхода;
- `ThrottleInterval=10` — не чаще раза в 10 с;
- `LimitLoadToSessionType=Aqua` — только графическая сессия;
- `ProcessType=Interactive` — нормальный приоритет для event tap;
- `--wait-for-game` — helper ждёт игру по фокусу; инъекция заблокирована,
  пока CS:GO не станет активным окном.

Управление:

```bash
launchctl print gui/$(id -u)/local.csgo.helper
launchctl kickstart -k gui/$(id -u)/local.csgo.helper
launchctl bootout gui/$(id -u)/local.csgo.helper
```

Логи: `~/Library/Logs/CSGOHelper/helper.log`, а также
`launchd.out.log`/`launchd.err.log`.

Если helper запущен и из LaunchAgent, и вручную, второй экземпляр
завершится с ошибкой `InstanceLock` — это защита от двойной инъекции.

---

## Steam-обёртка

Альтернатива LaunchAgent — запуск helper вместе с игрой:

```bash
make steam-wrapper
```

Затем в Steam → CS:GO legacy → Properties → Launch Options:

```text
/Users/<you>/Applications/csgo-helper-steam.sh %command%
```

Обёртка:

1. проверяет, не запущен ли helper (`pgrep`);
2. если нет — запускает установленный `.app` через `open -a` с
   `--headless --wait-for-game --exit-on-game-exit`;
3. ждёт 0.4 с, чтобы event tap успел встать;
4. делает `exec "$@"` — запускает игру, не блокируя её;
5. если helper не найден, игра всё равно запускается.

Пути можно переопределить:

```bash
CSGO_HELPER_APP=/path/to/CSGOHelper.app \
CSGO_HELPER_CONFIG=/path/to/config.json \
./scripts/steam-launch-wrapper.sh %command%
```

`--exit-on-game-exit` завершает helper через 2 с после исчезновения игры.

---

## HiDPI, мультимониторы, 64/128 tick

- Компенсация использует **относительные** дельты
  `kCGEventMouseMoved` / `mouseEventDeltaX/Y`, а не абсолютные координаты.
  Поэтому Retina/HiDPI и несколько мониторов не требуют множителя 2×:
  координаты экрана не участвуют в расчёте.
- Позиция курсора запрашивается только как начальная точка для создания
  события; на итоговую дельту она не влияет.
- Игра должна получать raw input (в CS:GO: Mouse → Raw Input = On). При
  оконном режиме и включённом ускорении курсора поведение может отличаться;
  для соревновательной игры используйте полноэкранный режим.
- Паттерн задан в градусах и переводится в counts через `sensitivity`,
  `m_yaw`, `m_pitch`. Разрешение монитора и DPI мыши в формулу не входят.
- 64/128 tick влияет на интервал bhop-импульсов (`bunnyHop.tickRate`,
  `pulseIntervalTicks`). Recoil и Snap Tap работают по времени в
  миллисекундах и не зависят от tick rate сервера.
- При смене монитора или разрешения не нужно менять конфиг; при смене
  чувствительности в игре — нужно.

---

## Проверка и тесты

```bash
make lint          # plutil, bash -n, py_compile
make test          # swift test: 35 тестов
make selftest      # 15 проверок внутри собранного .app
make check         # lint + test + selftest
```

Тесты покрывают:

- загрузку и валидацию 33 профилей, геометрию, алиасы, интерполяцию;
- provenance measured/heuristic и MIT-лицензию;
- round-trip конфига, значения по умолчанию, отклонение неверных значений;
- разбор хоткеев и защиту от дублей;
- SOCD: последняя клавиша, восстановление зажатой, тормозной тап, cooldown,
  disabled/unfocused;
- bhop: spam/predictive, интервалы 128 tick, лимит удержания, потеря фокуса;
- recoil: порог 120 мс, continuous, per-shot, сброс серии, clamp;
- console echo: sanitize, полная последовательность, busy/cancel.

`--diagnose` печатает версию macOS, архитектуру, TCC, Secure Input, конфиг,
паттерны, фокус, найденные установки Steam, LaunchAgent и размер лога.

---

## Ограничения

1. **Оружие выбирается вручную.** Внешний процесс не может узнать текущее
   оружие без чтения памяти или GSI. Меню и Shift+[ / ] переключают профиль;
   после смены оружия в игре выберите его в helper.
2. **Паттерны приблизительны.** 16 таблиц измерены, 17 — эвристика. Даже
   измеренная таблица зависит от чувствительности, `m_yaw`/`m_pitch`,
   положения прицела и особенностей конкретного патча. Это не «идеальный
   аим».
3. **Bhop не гарантирован.** Нет ground state; импульсы могут не совпасть с
   приземлением. `predictive` — только оценка окна.
4. **Snap Tap — макрос.** Он меняет порядок key-up/key-down и может
   нарушать правила серверов; SOCD реализован только для A/D.
5. **CS2 не целевая игра.** CS2 может использовать другие паттерны, тики и
   античит-политики. В `focus` по умолчанию нет процессов и bundle id CS2;
   helper не считает окно CS2 игровым и не инжектит в него.
6. **TCC и Secure Input.** Без Accessibility/Input Monitoring ввод не
   отправляется/не перехватывается. Secure Input, удалённый рабочий стол и
   некоторые fullscreen-режимы могут блокировать синтетику.
7. **Никакого антидетекта.** Проект не маскируется, не обходит VAC и не
   анализирует трафик. Использование макросов может нарушать Steam
   Subscriber Agreement; ответственность на пользователе.
8. **Консольный echo требует включённой консоли** и может быть незаметен,
   если игра перехватывает клавишу `~`. Это только локальная команда, не чат.
9. **LaunchAgent и TCC.** После пересборки/перемещения `.app` разрешения
   могут сброситься; выдайте их заново.
10. **Нет автоматического определения чувствительности.** Если в игре
    изменили `sensitivity`, обновите конфиг, иначе компенсация будет
    смещена.

---

## Диагностика проблем

| Симптом | Что проверить |
|---|---|
| `--permissions` показывает НЕТ | Выдайте Accessibility и Input Monitoring, перезапустите `.app` |
| Хоткеи не работают | Игра действительно frontmost? Input Monitoring OK? Secure Input выкл? |
| Мышь не двигается | Accessibility/Post events OK? `--dry-run` выключен? `injectionAvailable=true`? |
| Отдача компенсируется не туда | Совпадают ли `sensitivity`/`mYaw`/`mPitch` с игрой; `intensity`; выбранный профиль |
| Слишком сильная/слабая компенсация | `recoil.intensity` 0.8–1.0; `patternTimeScale`; проверка на стене |
| Bhop не помогает | Режим `spam`/`predictive`, `tickRate` 64 или 128, задержки; нет ground state |
| Snap Tap «залипает» | Перезапустите перехват в меню; проверьте, что нет второго экземпляра |
| После `make install` нет разрешений | TCC видит другой путь/подпись; выдайте заново для `~/Applications/CSGOHelper.app` |
| LaunchAgent перезапускается | Смотрите `launchd.err.log` и `helper.log`; `KeepAlive` срабатывает при ошибке |
| `event tap` не создаётся | Input Monitoring; иногда требуется перезапуск приложения/сессии |
| В логе `Secure Input: ВКЛ` | Закройте терминал с вводом пароля/менеджер паролей |

Полезные команды:

```bash
./build/CSGOHelper.app/Contents/MacOS/csgo-helper --diagnose
log show --last 5m --predicate 'process == "csgo-helper"' --style compact
tail -f ~/Library/Logs/CSGOHelper/helper.log
```

---

## Сторонние данные

- **spray.training** — MIT, Copyright (c) 2018 Robin Park.
  Полный текст лицензии: `THIRD_PARTY_NOTICES.md`.
- **Steam guide 2830373896** — справочный материал, числа из скриншотов не
  включены в поставку; ссылка и назначение указаны в `patterns.json`.
- **CS:GO / Steam** — товарные знаки Valve Corporation. Проект не связан с
  Valve и не распространяет файлы игры. `extract_game_data.py` читает
  локальную установку только для диагностики metadata.

Используйте helper только в офлайн-режиме или на приватных серверах, где
макросы разрешены. Не применяйте его для получения преимущества в
соревновательных матчах.
