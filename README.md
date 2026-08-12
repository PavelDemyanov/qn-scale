# QN Scale — свои весы вместо Feelfit

Разбор протокола умных напольных весов на чипе Qingniu (QN) и приложение для iPhone
взамен родного. Весы такие продаются под десятком имён — Libra, RENPHO, FitIndex,
Kamtron и другие; общее у них то, что в списке Bluetooth они видны как **`QN-Scale`**.

Разобрано на Libra CS20C1 (родное приложение — Feelfit).
Полный разбор протокола: **[PROTOCOL.md](PROTOCOL.md)**.

## Коротко о протоколе

Вес не вещается в рекламе — его отдают только по соединению, после рукопожатия
с синхронизацией времени:

```
весы → 0x12  привет: MAC, версия протокола
мы   → 0x13  единицы измерения (кг)
мы   → 0x02  текущее время
весы → 0x14  настройки приняты
мы   → 0x20  синхронизация времени
весы → 0x10  измерение: вес, признак стабильности, импеданс
```

Три места, где легко застрять:

1. **Реклама врёт про сервис.** Весы объявляют `FFE0`, а работают через `FFF0`:
   сканировать надо по одному UUID, характеристики брать из другого.
2. **Запись только `withResponse`.** `FFF2` объявлена как `write`; записи «без ответа»
   весы молча игнорируют, и рукопожатие выглядит непринятым.
3. **Без синхронизации времени поток измерений не начинается вообще** — весы отвечают
   на настройку единиц, подтверждают её и замолкают.

## Приложение для iPhone

`ios/` — SwiftUI-приложение: живой вес, история с графиком, состав тела по импедансу,
запись в «Здоровье». iOS 17+.

```bash
cd ios && xcodegen generate && open Libra.xcodeproj
```

Проект собирается [xcodegen](https://github.com/yonaskolb/XcodeGen)'ом из `project.yml`;
подставьте свой `DEVELOPMENT_TEAM` и запускайте на устройстве — в симуляторе
нет Bluetooth, и проверить приложение там нельзя.

Состав тела считается уравнением, выведенным именно для весов «нога–нога»
(Lu et al., Nutrition Journal 2015, сверка по DXA, n=554), вода — 73% тощей массы,
кости — 5%, обмен веществ — по Кетчу–Макардлу. Формул производителя нет ни у кого,
кроме производителя, так что абсолютные цифры расходятся с родным приложением;
в настройках есть поправка в процентных пунктах, чтобы привязаться к DXA или InBody.

## Инструменты для macOS

Питон-клиент протокола и инструменты, которыми всё это разбиралось.

```bash
./scripts/make-ble-app.sh                              # разово: venv + BLEScan.app
open -n -a "$PWD/BLEScan.app" --args "$PWD/qnscale.py" 8
```

| Скрипт | Что делает |
|---|---|
| `qnscale.py` | полный протокол, пишет измерения в `measurements.csv` |
| `scan.py` | сниффер BLE-рекламы |
| `connect.py` | подключение, дамп GATT, лог всех notify |
| `watch.py` | демон: ждёт пробуждения весов, переподключается |

**Почему нельзя запустить просто `python3 qnscale.py`.** macOS убивает процесс,
который трогает Bluetooth без `NSBluetoothAlwaysUsageDescription` в Info.plist
(падение с SIGABRT, `namespace: TCC`), а у интерпретатора такого ключа нет.
`BLEScan.app` — минимальная обёртка с этим ключом; `Contents/pyvenv.cfg` делает
её же корнем venv, поэтому питон внутри сам находит `bleak`. Флаг `-n` обязателен:
без него второй `open` не запускает новую копию, а активирует уже открытую,
и аргументы уходят в никуда.

## In English

Reverse-engineered BLE protocol of Qingniu (QN) smart scales — sold as Libra, RENPHO,
FitIndex, Kamtron and others, all advertising as `QN-Scale` — plus a SwiftUI iPhone app
replacing the stock Feelfit application.

Key findings, in case you are debugging your own: the scale **advertises service `FFE0`
but implements `FFF0`**; the write characteristic `FFF2` accepts **write-with-response
only**, silently ignoring write-without-response; and the measurement stream never starts
until the host completes the **time synchronisation** (`0x02` and `0x20` frames), even
though the scale acknowledges the unit configuration before that. Weight lives in bytes
3–4 of the `0x10` frame, big-endian, hundredths of a kilogram; bytes 6–9 carry two
impedance values in ohms. Every frame ends with a checksum — the sum of preceding bytes
modulo 256. Full details in [PROTOCOL.md](PROTOCOL.md) (Russian, but the packet dumps
and tables speak for themselves).

Prior art this builds on: the `QNHandler.kt` driver in
[openScale](https://github.com/oliexdev/openScale) and the
[QN-Scale thread](https://community.openmqttgateway.com/t/integrate-qn-scale-with-bluetooth-ble-help-wanted/1586)
at the OpenMQTTGateway forum.

## Лицензия

MIT — см. [LICENSE](LICENSE).
