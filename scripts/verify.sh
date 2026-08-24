#!/bin/sh
SERVICE=com.victronenergy.weather.cr6

printf '%-25s %s\n' "D-Bus path" "Value"
printf '%-25s %s\n' "-------------------------" "----------------"
for p in \
    Status Error AirTemperature RelativeHumidity BarometricPressure SeaLevelPressure \
    SolarFlux WindSpeed WindDirection WindGust10s PrecipitationRate PrecipitationTotal \
    LightningCount LightningDistance Tmin Tmax CR6BatteryVoltage CR6PanelTemperature \
    ClimaVueErrorFlag CR6ErrorWord TiltNS TiltWE UpdateAge
do
    printf '%-25s ' "/$p"
    dbus -y "$SERVICE" "/$p" GetValue 2>/dev/null || echo "(unavailable)"
done
