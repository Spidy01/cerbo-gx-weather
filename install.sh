#!/bin/sh
set -eu

INSTALLER_VERSION="2026-08-25.3"
OWNER="${CERBO_WEATHER_OWNER:-Spidy01}"
REPO="${CERBO_WEATHER_REPO:-cerbo-gx-weather}"
REF="${CERBO_WEATHER_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/$OWNER/$REPO/$REF"

DEST=/data/weather-modbus
GUI_ROOT=/opt/victronenergy/gui-v2/Victron/VenusOS
MODEL="$GUI_ROOT/components/SwipePageModel.qml"
QMLDIR="$GUI_ROOT/qmldir"
PAGES="$GUI_ROOT/pages"
CR6_HOST="${1:-}"
UNIT_ID="${2:-}"
TMP="$DEST/.install.$$"
BACKUP=""
GUI_SERVICE=""

echo "cerbo-gx-weather installer $INSTALLER_VERSION"

cleanup() {
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

fetch_file() {
    remote="$1"
    output="$2"
    url="$RAW_BASE/$remote?v=$INSTALLER_VERSION"
    if [ -n "${GH_TOKEN:-}" ]; then
        wget -q --header="Authorization: Bearer $GH_TOKEN" -O "$output" "$url"
    else
        wget -q -O "$output" "$url"
    fi
}

find_gui_service() {
    if [ -d /service/start-gui ]; then
        GUI_SERVICE=/service/start-gui
    elif [ -d /service/gui-v2 ]; then
        GUI_SERVICE=/service/gui-v2
    else
        GUI_SERVICE=""
    fi
}

restart_gui() {
    find_gui_service
    if [ -n "$GUI_SERVICE" ] && command -v svc >/dev/null 2>&1; then
        svc -t "$GUI_SERVICE" 2>/dev/null || true
    else
        killall venus-gui-v2 2>/dev/null || true
    fi
}

restore_gui() {
    echo "Restoring GUI backup: $BACKUP" >&2
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/SwipePageModel.qml" ]; then
        cp "$BACKUP/SwipePageModel.qml" "$MODEL"
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/qmldir" ]; then
        cp "$BACKUP/qmldir" "$QMLDIR"
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/WeatherPage.qml" ]; then
        cp "$BACKUP/WeatherPage.qml" "$PAGES/WeatherPage.qml"
    else
        rm -f "$PAGES/WeatherPage.qml"
    fi
    if [ -n "$BACKUP" ] && [ -f "$BACKUP/weather.svg" ]; then
        cp "$BACKUP/weather.svg" "$PAGES/weather.svg"
    else
        rm -f "$PAGES/weather.svg"
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
fi

for command in python3 wget cp mkdir date wc sed grep sleep; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

if [ ! -f "$MODEL" ] || [ ! -d "$PAGES" ]; then
    echo "Unsupported GUI-v2 filesystem layout." >&2
    echo "Expected: $MODEL" >&2
    exit 1
fi

mkdir -p "$DEST" "$DEST/gui" "$DEST/scripts" "$DEST/backups" "$TMP"

echo "Downloading $OWNER/$REPO@$REF..."
fetch_file service/weather_modbus.py "$TMP/weather_modbus.py"
fetch_file service/config.default.json "$TMP/config.default.json"
fetch_file service/run "$TMP/run"
fetch_file gui/WeatherPage.qml "$TMP/WeatherPage.qml"
fetch_file gui/weather.svg "$TMP/weather.svg"
fetch_file scripts/patch_gui.py "$TMP/patch_gui.py"
fetch_file scripts/rollback_gui.py "$TMP/rollback_gui.py"
fetch_file scripts/verify.sh "$TMP/verify.sh"
fetch_file uninstall.sh "$TMP/uninstall.sh"

echo "Downloads complete."

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/backups/$STAMP"
mkdir -p "$BACKUP"
cp "$MODEL" "$BACKUP/SwipePageModel.qml"
[ -f "$QMLDIR" ] && cp "$QMLDIR" "$BACKUP/qmldir" || true
[ -f "$PAGES/WeatherPage.qml" ] && cp "$PAGES/WeatherPage.qml" "$BACKUP/WeatherPage.qml" || true
[ -f "$PAGES/weather.svg" ] && cp "$PAGES/weather.svg" "$BACKUP/weather.svg" || true
[ -f "$DEST/config.json" ] && cp "$DEST/config.json" "$BACKUP/config.json" || true

echo "GUI backup: $BACKUP"

python3 - "$DEST/config.json" "$TMP/config.default.json" "$CR6_HOST" "$UNIT_ID" <<'PY'
import json
import sys

current_path, default_path, host_arg, unit_arg = sys.argv[1:5]
with open(default_path, "r") as f:
    config = json.load(f)

try:
    with open(current_path, "r") as f:
        old = json.load(f)
except Exception:
    old = None

if old:
    for key in ("host", "port", "unit_id", "poll_seconds", "timeout_seconds", "float_order"):
        if key in old.get("modbus", {}):
            config["modbus"][key] = old["modbus"][key]
    if "device_instance" in old.get("dbus", {}):
        config["dbus"]["device_instance"] = old["dbus"]["device_instance"]

if host_arg:
    config["modbus"]["host"] = host_arg
if unit_arg:
    config["modbus"]["unit_id"] = int(unit_arg)

with open(current_path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY

cp "$TMP/weather_modbus.py" "$DEST/weather_modbus.py"
cp "$TMP/WeatherPage.qml" "$DEST/gui/WeatherPage.qml"
cp "$TMP/weather.svg" "$DEST/gui/weather.svg"
cp "$TMP/patch_gui.py" "$DEST/scripts/patch_gui.py"
cp "$TMP/rollback_gui.py" "$DEST/scripts/rollback_gui.py"
cp "$TMP/verify.sh" "$DEST/scripts/verify.sh"
cp "$TMP/uninstall.sh" "$DEST/uninstall.sh"
chmod +x "$DEST/weather_modbus.py" "$DEST/scripts/patch_gui.py" "$DEST/scripts/rollback_gui.py" "$DEST/scripts/verify.sh" "$DEST/uninstall.sh"

mkdir -p /service/weather-modbus
cp "$TMP/run" /service/weather-modbus/run
chmod +x /service/weather-modbus/run

cp "$TMP/WeatherPage.qml" "$PAGES/WeatherPage.qml"
cp "$TMP/weather.svg" "$PAGES/weather.svg"

if ! python3 "$DEST/scripts/patch_gui.py" --gui-root "$GUI_ROOT"; then
    echo "GUI patcher failed before GUI restart." >&2
    restore_gui
    exit 1
fi

HOST_NOW="$(python3 -c 'import json; print(json.load(open("/data/weather-modbus/config.json"))["modbus"]["host"])')"
if [ "$HOST_NOW" = "CHANGE_ME" ] || [ -z "$HOST_NOW" ]; then
    echo "No CR6 IP configured yet." >&2
    echo "Rerun with: ... | sh -s -- <CR6_IP> [UNIT_ID]" >&2
else
    if command -v svc >/dev/null 2>&1; then
        svc -u /service/weather-modbus 2>/dev/null || true
        sleep 1
        svc -t /service/weather-modbus 2>/dev/null || true
    fi
fi

GUI_LOG=/var/log/start-gui/current
if [ -f "$GUI_LOG" ]; then
    BEFORE_LINES="$(wc -l < "$GUI_LOG")"
else
    BEFORE_LINES=0
fi

echo "Restarting GUI-v2..."
restart_gui
sleep 8

NEWLOG="$TMP/gui-new.log"
if [ -f "$GUI_LOG" ]; then
    AFTER_LINES="$(wc -l < "$GUI_LOG")"
    if [ "$AFTER_LINES" -ge "$BEFORE_LINES" ]; then
        START_LINE=$((BEFORE_LINES + 1))
        sed -n "${START_LINE},\$p" "$GUI_LOG" > "$NEWLOG"
    else
        tail -n 120 "$GUI_LOG" > "$NEWLOG"
    fi
else
    : > "$NEWLOG"
fi

if grep -E 'Type (ApplicationContent|MainView|SwipePageModel) unavailable|WeatherPage is not a type|cerbo-gx-weather: WeatherPage.qml failed to load|cerbo-gx-weather: WeatherPage.qml createObject failed' "$NEWLOG" >/dev/null 2>&1; then
    echo "GUI-v2 reported a weather-page startup error:" >&2
    cat "$NEWLOG" >&2
    restore_gui
    restart_gui
    echo "GUI restored automatically. Weather D-Bus files/config were retained." >&2
    exit 1
fi

echo "cerbo-gx-weather installed successfully."
echo "Installer:      $INSTALLER_VERSION"
echo "CR6:            $HOST_NOW"
echo "D-Bus service:  com.victronenergy.weather.cr6"
echo "Config:         $DEST/config.json"
echo "Verify:         $DEST/scripts/verify.sh"
echo "GUI backup:     $BACKUP"
