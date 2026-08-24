#!/usr/bin/env python3
"""Remove cerbo-gx-weather GUI changes while retaining the D-Bus service/config."""

import argparse
import re
from pathlib import Path

MARKER_START = "// BEGIN cerbo-gx-weather dynamic page"
MARKER_END = "// END cerbo-gx-weather dynamic page"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gui-root", default="/opt/victronenergy/gui-v2/Victron/VenusOS")
    args = parser.parse_args()

    gui = Path(args.gui_root)
    model = gui / "components" / "SwipePageModel.qml"
    qmldir = gui / "qmldir"
    if not model.exists():
        raise SystemExit("SwipePageModel.qml not found")

    text = model.read_text()

    if MARKER_START in text and MARKER_END in text:
        start = text.index(MARKER_START)
        line_start = text.rfind("\n", 0, start) + 1
        end = text.index(MARKER_END, start) + len(MARKER_END)
        line_end = text.find("\n", end)
        if line_end < 0:
            line_end = len(text)
        else:
            line_end += 1
        text = text[:line_start] + text[line_end:]

    text = re.sub(
        r'\n[ \t]*// cerbo-gx-weather: instantiate page[ \t]*\n[ \t]*createWeatherPage\(\)[ \t]*\n',
        '\n',
        text,
        count=1,
    )
    text = re.sub(
        r'\n[ \t]*WeatherPage[ \t]*\{[ \t]*\n[ \t]*view:[ \t]*root\.view[ \t]*\n[ \t]*\}[ \t]*\n',
        '\n',
        text,
        count=1,
    )
    text = text.replace("insert(3, levelsPage)", "insert(2, levelsPage)", 1)
    model.write_text(text)

    if qmldir.exists():
        lines = qmldir.read_text().splitlines()
        lines = [line for line in lines if "WeatherPage 2.0 pages/WeatherPage.qml" not in line]
        qmldir.write_text("\n".join(lines) + "\n")

    weather_page = gui / "pages" / "WeatherPage.qml"
    weather_icon = gui / "pages" / "weather.svg"
    weather_page.unlink(missing_ok=True)
    weather_icon.unlink(missing_ok=True)
    print("cerbo-gx-weather GUI changes removed")


if __name__ == "__main__":
    main()
