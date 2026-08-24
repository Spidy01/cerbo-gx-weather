# CR6 Modbus register map

All values below are read-only by this project and are retrieved from the CR6 with Modbus TCP function 03 (Holding Registers), Unit ID configured in `config.json`.

Standard 4xxxx notation is used: holding register `40001` is Modbus protocol address `0`.

| Holding registers | Signal | Type | Scale | Unit | D-Bus path |
|---:|---|---|---:|---|---|
| 40001/02 | Solar radiation | float32 | 1 | W/m² | `/SolarFlux` |
| 40003/04 | Lifetime precipitation | float32 | 1 | mm | `/PrecipitationTotal` |
| 40005/06 | Lightning strikes | float32 | 1 | count | `/LightningCount` |
| 40007/08 | Strike distance | float32 | 1 | km | `/LightningDistance` |
| 40009/10 | Wind speed | float32 | 1 | m/s | `/WindSpeed` |
| 40011/12 | Wind direction | float32 | 1 | degrees | `/WindDirection` |
| 40013/14 | Gust wind speed | float32 | 1 | m/s | `/WindGust10s` |
| 40015/16 | Air temperature | float32 | 1 | °C | `/AirTemperature` |
| 40017/18 | Vapour pressure | float32 | 1 | kPa | `/VaporPressure` |
| 40019/20 | Atmospheric pressure | float32 | 1 | kPa | `/BarometricPressure` |
| 40021/22 | Sea-level pressure | float32 | 1 | kPa | `/SeaLevelPressure` |
| 40023/24 | Relative humidity | float32 | 1 | % | `/RelativeHumidity` |
| 40025/26 | Humidity sensor temperature | float32 | 1 | °C | `/HumiditySensorTemp` |
| 40027/28 | Tilt north/south | float32 | 1 | degrees | `/TiltNS` |
| 40029/30 | Tilt west/east | float32 | 1 | degrees | `/TiltWE` |
| 40031/32 | Precipitation drop count | float32 | 1 | count | `/PrecipDropCount` |
| 40033/34 | Precipitation tip count | float32 | 1 | count | `/PrecipTipCount` |
| 40035/36 | Precipitation EC | float32 | 1 | µS/cm | `/PrecipitationEC` |
| 40037/38 | Total tilt | float32 | 1 | degrees | `/TotalTilt` |
| 40039/40 | Tmin | float32 | 1 | °C | `/Tmin` |
| 40041/42 | Tmax | float32 | 1 | °C | `/Tmax` |
| 40043/44 | ClimaVue error flag | float32 | 1 | - | `/ClimaVueErrorFlag` |
| 40045/46 | CR6 error word | float32 | 1 | - | `/CR6ErrorWord` |
| 40047/48 | CR6 battery voltage | float32 | 1 | V | `/CR6BatteryVoltage` |
| 40049/50 | CR6 panel temperature | float32 | 1 | °C | `/CR6PanelTemperature` |
| 40051/52 | Precipitation rate | float32 | 1 | mm/h | `/PrecipitationRate` |

Default float order in this project is `ABCD`, matching the values verified against the running CR6 program. It can be changed in `/data/weather-modbus/config.json` if required.
