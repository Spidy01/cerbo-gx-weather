#!/bin/sh
set -eu

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

cleanup() {
    rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

fetch_file() {
    remote="$1"
    output="$2"
    if [ -n "${GH_TOKEN:-}" ]; then
        wget -q --header="Authorization: Bearer $GH_TOKEN" -O "$output" "$RAW_BASE/$remote"
    else
        wget -q -O "$output" "$RAW_BASE/$remote"
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
        svc -t "$GUI_SERVICE" || true
    else
        killall venus-gui-v2 2>/dev/null || true
    fi
}

rollback_gui() {
    echo "Rolling GUI changes back to the pre-install backup..." >&2
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
    restart_gui
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
fi

for command in python3 wget cp mkdir date wc sed grep; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command not found: $command" >&2
        exit 1
    fi
done

if [ ! -d /opt/victronenergy/gui-v2 ]; then
    echo "This does not look like a Venus OS GX device with gui-v2 installed." >&2
    exit 1
fi

if [ ! -f "$MODEL" ] || [ ! -d "$PAGES" ]; then
    echo "Unsupported GUI-v2 filesystem layout. Expected: $MODEL" >&2
    exit 1
fi

mkdir -p "$DEST" "$DEST/gui" "$DEST/scripts" "$DEST/backups" "$TMP"

echo "Downloading cerbo-gx-weather from $OWNER/$REPO@$REF..."
fetch_file service/weather_modbus.py "$TMP/weather_modbus.py"
fetch_file service/config.default.json "$TMP/config.default.json"
fetch_file service/run "$TMP/run"
fetch_file gui/WeatherPage.qml "$TMP/WeatherPage.qml"
fetch_file gui/weather.svg "$TMP/weather.svg"
fetch_file scripts/patch_gui.py "$TMP/patch_gui.py"
fetch_file scripts/rollback_gui.py "$TMP/rollback_gui.py"
fetch_file scripts/verify.sh "$TMP/verify.sh"
fetch_file uninstall.sh "$TMP/uninstall.sh"

python3 -m py_compile "$TMP/weather_modbus.py" "$TMP/patch_gui.py" "$TMP/rollback_gui.py"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/backups/$STAMP"
mkdir -p "$BACKUP"
cp "$MODEL" "$BACKUP/SwipePageModel.qml"
[ -f "$QMLDIR" ] && cp "$QMLDIR" "$BACKUP/qmldir" || true
[ -f "$PAGES/WeatherPage.qml" ] && cp "$PAGES/WeatherPage.qml" "$BACKUP/WeatherPage.qml" || true
[ -f "$PAGES/weather.svg" ] && cp "$PAGES/weather.svg" "$BACKUP/weather.svg" || true
[ -f "$DEST/config.json" ] && cp "$DEST/config.json" "$BACKUP/config.json" || true

echo "Backup: $BACKUP"

python3 - "$DEST/config.json" "$TMP/config.default.json" "$CR6_HOST" "$UNIT_ID" <<'PY'
import json
from pathlib import Path
import sys

current_path = Path(sys.argv[1])
default_path = Path(sys.argv[2])
host_arg = sys.argv[3]
unit_arg = sys.argv[4]

config = json.loads(default_path.read_text())
if current_path.exists():
    try:
        old = json.loads(current_path.read_text())
        for key in ("host", "port", "unit_id", "poll_seconds", "timeout_seconds", "float_order"):
            if key in old.get("modbus", {}):
                config["modbus"][key] = old["modbus"][key]
        if "device_instance" in old.get("dbus", {}):
            config["dbus"]["device_instance"] = old["dbus"]["device_instance"]
    except Exception as exc:
        print("Warning: could not merge old config:", exc)

if host_arg:
    config["modbus"]["host"] = host_arg
if unit_arg:
    config["modbus"]["unit_id"] = int(unit_arg)

current_path.write_text(json.dumps(config, indent=2) + "\n")
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

python3 "$DEST/scripts/patch_gui.py" --gui-root "$GUI_ROOT"

HOST_NOW="$(python3 -c 'import json; print(json.load(open("/data/weather-modbus/config.json"))["modbus"]["host"])')"
if [ "$HOST_NOW" = "CHANGE_ME" ] || [ -z "$HOST_NOW" ]; then
    echo "Weather files are installed, but no CR6 IP is configured." >&2
    echo "Run again with: ... | sh -s -- <CR6_IP> [UNIT_ID]" >&2
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

GUI_FAILED=0
if grep -E 'Type (ApplicationContent|MainView|SwipePageModel) unavailable|WeatherPage is not a type|cerbo-gx-weather: WeatherPage.qml failed to load|cerbo-gx-weather: WeatherPage.qml createObject failed' "$NEWLOG" >/dev/null 2>&1; then
    GUI_FAILED=1
fi

find_gui_service
if [ -n "$GUI_SERVICE" ] && command -v svstat >/dev/null 2>&1; then
    if ! svstat "$GUI_SERVICE" 2>/dev/null | grep -q '^.*up '; then
        GUI_FAILED=1
    fi
fi

if [ "$GUI_FAILED" -ne 0 ]; then
    echo "GUI-v2 reported an error after the weather-page patch." >&2
    echo "New GUI log:" >&2
    cat "$NEWLOG" >&2
    rollback_gui
    echo "The weather D-Bus service/config was retained, but the GUI patch was rolled back." >&2
    exit 1
fi

echo
echo "cerbo-gx-weather installed successfully."
echo "CR6:           $HOST_NOW"
echo "D-Bus service: com.victronenergy.weather.cr6"
echo "Config:        $DEST/config.json"
echo "Verify:        $DEST/scripts/verify.sh"
echo "GUI backup:    $BACKUP"
echo
echo "The Weather page is loaded dynamically from a file URL; no qmldir/QML type registration is used."
