#!/bin/sh
set -eu

DEST=/data/weather-modbus
GUI_ROOT=/opt/victronenergy/gui-v2/Victron/VenusOS

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
fi

if [ -x "$DEST/scripts/rollback_gui.py" ]; then
    python3 "$DEST/scripts/rollback_gui.py" --gui-root "$GUI_ROOT"
fi

if [ -d /service/weather-modbus ]; then
    svc -d /service/weather-modbus 2>/dev/null || true
    rm -rf /service/weather-modbus
fi

if [ -d /service/start-gui ]; then
    svc -t /service/start-gui 2>/dev/null || true
elif [ -d /service/gui-v2 ]; then
    svc -t /service/gui-v2 2>/dev/null || true
else
    killall venus-gui-v2 2>/dev/null || true
fi

echo "GUI integration and weather service removed."
echo "$DEST was retained so config and backups are not lost."
