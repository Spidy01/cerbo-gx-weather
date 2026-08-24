# Cerbo GX CR6 Weather Page

Custom weather dashboard for a Victron Cerbo GX running Venus OS GUI-v2.

The weather source is a Campbell Scientific CR6 / ClimaVue 50 G2 exposed over Modbus TCP. A small Python service reads the CR6, publishes the values onto the Venus OS D-Bus, and a custom GUI-v2 swipe page displays them on the local GX screen.

## Target

- Victron Cerbo GX
- Venus OS v3.75
- GUI-v2 layout matching Victron `gui-v2` v1.2.40
- Campbell Scientific CR6 Modbus TCP server
- ClimaVue 50 G2 weather measurements

## Architecture

```text
ClimaVue 50 G2
      |
    SDI-12
      |
Campbell CR6
      |
  Modbus TCP / FC03
      |
weather_modbus.py
      |
com.victronenergy.weather.cr6
      |
Venus OS D-Bus / VeQuickItem
      |
WeatherPage.qml
```

## Safety design

This version intentionally does **not** register `WeatherPage` as a new `Victron.VenusOS` QML type.

A previous approach produced:

```text
SwipePageModel.qml:62 WeatherPage is not a type
```

which prevented GUI-v2 from starting.

This project instead uses `Qt.createComponent()` with a direct `file:///` URL from `SwipePageModel.qml`. If `WeatherPage.qml` has a syntax/load error, the existing GUI module can still load and the dynamic component reports the error instead of making `SwipePageModel` unavailable.

The installer also:

- backs up modified Victron files before patching;
- refuses a GUI layout it does not recognize;
- leaves the factory `SwipeViewPage.qml` untouched;
- does not add `WeatherPage` to `qmldir`;
- checks `/var/log/start-gui/current` after restarting GUI-v2;
- automatically restores the pre-install GUI backup if startup errors are detected.

## Repository layout

```text
cerbo-gx-weather/
├── install.sh
├── uninstall.sh
├── README.md
├── REGISTER_MAP.md
├── service/
│   ├── config.default.json
│   ├── run
│   └── weather_modbus.py
├── gui/
│   ├── WeatherPage.qml
│   └── weather.svg
└── scripts/
    ├── patch_gui.py
    ├── rollback_gui.py
    └── verify.sh
```

## One-line install

### Public repository

If this repository is public, install or update with:

```sh
wget -qO- https://raw.githubusercontent.com/Spidy01/cerbo-gx-weather/main/install.sh | sh
```

On the first install, provide the CR6 IP address and optional Modbus Unit ID:

```sh
wget -qO- https://raw.githubusercontent.com/Spidy01/cerbo-gx-weather/main/install.sh | sh -s -- 192.168.1.50 1
```

After that, the installer preserves the current CR6 host, port, Unit ID, polling interval and float order, so the short update command can be used.

### Private repository

This repository is currently private, so anonymous `raw.githubusercontent.com` downloads will not work.

The installer supports a `GH_TOKEN` environment variable for authenticated downloads, but placing a token directly on a shell command line can expose it in shell history. For a Cerbo intended to update without credentials, making this code-only repository public is the simplest option. Do not commit site IP addresses or credentials.

## Installed locations

Persistent project files:

```text
/data/weather-modbus/
```

Weather D-Bus service:

```text
com.victronenergy.weather.cr6
```

Runit service:

```text
/service/weather-modbus
```

GUI files:

```text
/opt/victronenergy/gui-v2/Victron/VenusOS/pages/WeatherPage.qml
/opt/victronenergy/gui-v2/Victron/VenusOS/pages/weather.svg
```

The only existing GUI source file patched is:

```text
/opt/victronenergy/gui-v2/Victron/VenusOS/components/SwipePageModel.qml
```

Backups are stored under:

```text
/data/weather-modbus/backups/YYYYMMDD-HHMMSS/
```

## Page order

The factory v3.75 logic inserts Levels at index 2. This package deliberately leaves that factory logic unchanged, then inserts Weather at index 2 afterwards.

Result:

```text
Brief -> Overview -> Weather -> Levels -> Notifications -> Settings
```

If Levels is not present:

```text
Brief -> Overview -> Weather -> Notifications -> Settings
```

If Boat mode is enabled, the factory Boat page remains at the beginning.

## Verify D-Bus data

```sh
/data/weather-modbus/scripts/verify.sh
```

Examples:

```sh
dbus -y com.victronenergy.weather.cr6 /AirTemperature GetValue
dbus -y com.victronenergy.weather.cr6 /RelativeHumidity GetValue
dbus -y com.victronenergy.weather.cr6 /BarometricPressure GetValue
dbus -y com.victronenergy.weather.cr6 /PrecipitationRate GetValue
```

## Corrected CR6 mapping

Key signals are:

| Signal | Holding registers | Type | Unit | D-Bus path |
|---|---:|---|---|---|
| Solar radiation | 40001/02 | float32 | W/m² | `/SolarFlux` |
| Lifetime precipitation | 40003/04 | float32 | mm | `/PrecipitationTotal` |
| Lightning count | 40005/06 | float32 | count | `/LightningCount` |
| Lightning distance | 40007/08 | float32 | km | `/LightningDistance` |
| Wind speed | 40009/10 | float32 | m/s | `/WindSpeed` |
| Wind direction | 40011/12 | float32 | ° | `/WindDirection` |
| 10 s gust | 40013/14 | float32 | m/s | `/WindGust10s` |
| Air temperature | 40015/16 | float32 | °C | `/AirTemperature` |
| Vapour pressure | 40017/18 | float32 | kPa | `/VaporPressure` |
| Atmospheric pressure | 40019/20 | float32 | kPa | `/BarometricPressure` |
| Sea-level pressure | 40021/22 | float32 | kPa | `/SeaLevelPressure` |
| Relative humidity | 40023/24 | float32 | % | `/RelativeHumidity` |
| Humidity sensor temp | 40025/26 | float32 | °C | `/HumiditySensorTemp` |
| Tilt N/S | 40027/28 | float32 | ° | `/TiltNS` |
| Tilt W/E | 40029/30 | float32 | ° | `/TiltWE` |
| Tmin | 40039/40 | float32 | °C | `/Tmin` |
| Tmax | 40041/42 | float32 | °C | `/Tmax` |
| ClimaVue error flag | 40043/44 | float32 | - | `/ClimaVueErrorFlag` |
| CR6 error word | 40045/46 | float32 | - | `/CR6ErrorWord` |
| CR6 battery voltage | 40047/48 | float32 | V | `/CR6BatteryVoltage` |
| CR6 panel temperature | 40049/50 | float32 | °C | `/CR6PanelTemperature` |
| Precipitation rate | 40051/52 | float32 | mm/h | `/PrecipitationRate` |

The bridge uses Modbus TCP function 03. Standard 4xxxx notation is converted correctly: **40001 is protocol address 0**.

Relative humidity from this CR6 program is already percent and is **not multiplied by 100**.

## Uninstall GUI/service

```sh
/data/weather-modbus/uninstall.sh
```

Or, if the repository directory is not retained, run the rollback script then remove the runit service:

```sh
python3 /data/weather-modbus/scripts/rollback_gui.py
svc -d /service/weather-modbus
rm -rf /service/weather-modbus
```

`/data/weather-modbus` is deliberately retained so configuration and backups are not lost.

## Firmware upgrades

A Venus OS update may replace GUI-v2 files. Re-run the installer after an upgrade. The patcher checks for the expected `SwipePageModel.qml` structure and aborts rather than applying a guessed patch to an unknown future layout.
