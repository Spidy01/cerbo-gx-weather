#!/usr/bin/env python3
"""Safely add the weather page to Venus OS GUI-v2 without registering a new QML type."""

import argparse
import re
from pathlib import Path

MARKER_START = "// BEGIN cerbo-gx-weather dynamic page"
MARKER_END = "// END cerbo-gx-weather dynamic page"
CALL_MARKER = "// cerbo-gx-weather: instantiate page"

DYNAMIC_BLOCK = r'''
        // BEGIN cerbo-gx-weather dynamic page
        property var weatherComponent
        property var weatherPage

        function createWeatherPage() {
                if (weatherPage) {
                        return
                }

                weatherComponent = Qt.createComponent("file:///opt/victronenergy/gui-v2/Victron/VenusOS/pages/WeatherPage.qml")
                if (weatherComponent.status !== Component.Ready) {
                        console.error("cerbo-gx-weather: WeatherPage.qml failed to load:", weatherComponent.errorString())
                        return
                }

                weatherPage = weatherComponent.createObject(parent, { "view": root.view })
                if (!weatherPage) {
                        console.error("cerbo-gx-weather: WeatherPage.qml createObject failed")
                        return
                }

                // Levels is inserted at index 2 first. Inserting Weather at 2 pushes Levels to 3.
                // If Levels is absent, Weather simply occupies index 2.
                insert(2, weatherPage)
                console.info("cerbo-gx-weather: Weather page loaded")
        }
        // END cerbo-gx-weather dynamic page
'''

CALL_BLOCK = '''
                // cerbo-gx-weather: instantiate page
                createWeatherPage()

'''


def remove_legacy(text):
    text = re.sub(
        r'\n[ \t]*WeatherPage[ \t]*\{[ \t]*\n[ \t]*view:[ \t]*root\.view[ \t]*\n[ \t]*\}[ \t]*\n',
        '\n',
        text,
        count=1,
    )
    text = text.replace("insert(3, levelsPage)", "insert(2, levelsPage)", 1)
    return text


def remove_marked_patch(text):
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
    return text


def patch(model_path, qmldir_path):
    text = model_path.read_text()

    required_tokens = (
        "import QtQml.Models",
        "ObjectModel {",
        "required property SwipeView view",
        "BriefPage {",
        "OverviewPage {",
        "NotificationsPage {",
        "SettingsPage {",
        "Component.onCompleted:",
        "insert(2, levelsPage)",
        "if (showBoatPage.value)",
    )
    missing = [token for token in required_tokens if token not in text]
    if missing:
        raise SystemExit(
            "Unsupported SwipePageModel.qml layout; refusing to patch. Missing: "
            + ", ".join(missing)
        )

    text = remove_marked_patch(remove_legacy(text))

    completed_match = re.search(r'^[ \t]*property bool completed: false[ \t]*$', text, re.MULTILINE)
    if not completed_match:
        raise SystemExit("Could not locate 'property bool completed: false'; refusing to patch")
    insert_at = completed_match.end()
    text = text[:insert_at] + "\n" + DYNAMIC_BLOCK.rstrip("\n") + text[insert_at:]

    completed_pos = text.index("Component.onCompleted:")
    boat_match = re.search(r'^[ \t]*if \(showBoatPage\.value\) \{', text[completed_pos:], re.MULTILINE)
    if not boat_match:
        raise SystemExit("Could not locate Boat insertion inside Component.onCompleted")
    boat_pos = completed_pos + boat_match.start()
    text = text[:boat_pos] + CALL_BLOCK + text[boat_pos:]

    model_path.write_text(text)

    if qmldir_path.exists():
        lines = qmldir_path.read_text().splitlines()
        cleaned = [line for line in lines if "WeatherPage 2.0 pages/WeatherPage.qml" not in line]
        qmldir_path.write_text("\n".join(cleaned) + "\n")

    print("Patched:", model_path)
    print("Weather page is loaded dynamically; qmldir registration is not used.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--gui-root", default="/opt/victronenergy/gui-v2/Victron/VenusOS")
    args = parser.parse_args()

    gui_root = Path(args.gui_root)
    model = gui_root / "components" / "SwipePageModel.qml"
    qmldir = gui_root / "qmldir"
    if not model.exists():
        raise SystemExit("SwipePageModel.qml not found: %s" % model)
    patch(model, qmldir)


if __name__ == "__main__":
    main()
