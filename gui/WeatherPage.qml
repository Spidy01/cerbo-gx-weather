import QtQuick
import QtQuick.Layouts
import Victron.VenusOS

SwipeViewPage {
    id: root

    navButtonText: "Weather"
    navButtonIcon: Qt.resolvedUrl("weather.svg")
    url: "file:///opt/victronenergy/gui-v2/Victron/VenusOS/pages/WeatherPage.qml"
    backgroundColor: Theme.color_page_background
    fullScreenWhenIdle: true
    topLeftButton: VenusOS.StatusBar_LeftButton_ControlsInactive

    readonly property string weatherService: "dbus/com.victronenergy.weather.cr6"

    VeQuickItem { id: temperature; uid: root.weatherService + "/AirTemperature" }
    VeQuickItem { id: humidity; uid: root.weatherService + "/RelativeHumidity" }
    VeQuickItem { id: pressure; uid: root.weatherService + "/BarometricPressure" }
    VeQuickItem { id: seaPressure; uid: root.weatherService + "/SeaLevelPressure" }
    VeQuickItem { id: solar; uid: root.weatherService + "/SolarFlux" }
    VeQuickItem { id: wind; uid: root.weatherService + "/WindSpeed" }
    VeQuickItem { id: windDirection; uid: root.weatherService + "/WindDirection" }
    VeQuickItem { id: gust; uid: root.weatherService + "/WindGust10s" }
    VeQuickItem { id: rainRate; uid: root.weatherService + "/PrecipitationRate" }
    VeQuickItem { id: rainTotal; uid: root.weatherService + "/PrecipitationTotal" }
    VeQuickItem { id: lightningCount; uid: root.weatherService + "/LightningCount" }
    VeQuickItem { id: lightningDistance; uid: root.weatherService + "/LightningDistance" }
    VeQuickItem { id: tmin; uid: root.weatherService + "/Tmin" }
    VeQuickItem { id: tmax; uid: root.weatherService + "/Tmax" }
    VeQuickItem { id: cr6Battery; uid: root.weatherService + "/CR6BatteryVoltage" }
    VeQuickItem { id: cr6PanelTemp; uid: root.weatherService + "/CR6PanelTemperature" }
    VeQuickItem { id: cr6Error; uid: root.weatherService + "/CR6ErrorWord" }
    VeQuickItem { id: climaError; uid: root.weatherService + "/ClimaVueErrorFlag" }
    VeQuickItem { id: status; uid: root.weatherService + "/Status" }
    VeQuickItem { id: age; uid: root.weatherService + "/UpdateAge" }

    function number(item, decimals) {
        if (!item.valid || item.value === undefined || item.value === null || isNaN(Number(item.value))) {
            return "--"
        }
        return Number(item.value).toFixed(decimals)
    }

    function compass(item) {
        if (!item.valid || item.value === undefined || item.value === null || isNaN(Number(item.value))) {
            return "--"
        }
        const directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        const angle = ((Number(item.value) % 360) + 360) % 360
        return directions[Math.round(angle / 45) % 8]
    }

    function healthy() {
        return status.valid && status.value === "Online"
                && Number(cr6Error.value || 0) === 0
                && Number(climaError.value || 0) === 0
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: Theme.geometry_page_content_horizontalMargin
            rightMargin: Theme.geometry_page_content_horizontalMargin
            topMargin: 10
            bottomMargin: 8
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Text {
                text: "CR6 Weather Station"
                color: Theme.color_font_primary
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.healthy() ? "ONLINE" : (status.valid && status.value === "Online" ? "ALARM" : "OFFLINE")
                color: root.healthy() ? "#64d47b" : "#e7685d"
                font.pixelSize: 13
                font.bold: true
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 4
            rowSpacing: 8
            columnSpacing: 8

            WeatherTile {
                title: "AIR TEMPERATURE"
                valueText: root.number(temperature, 1)
                unitText: "°C"
                detailText: "Min " + root.number(tmin, 1) + "°  Max " + root.number(tmax, 1) + "°"
            }
            WeatherTile {
                title: "HUMIDITY"
                valueText: root.number(humidity, 0)
                unitText: "%"
                detailText: "Relative humidity"
            }
            WeatherTile {
                title: "PRESSURE"
                valueText: root.number(pressure, 1)
                unitText: "kPa"
                detailText: "Sea level " + root.number(seaPressure, 1) + " kPa"
            }
            WeatherTile {
                title: "SOLAR"
                valueText: root.number(solar, 0)
                unitText: "W/m²"
                detailText: "Irradiance"
            }
            WeatherTile {
                title: "WIND"
                valueText: root.number(wind, 1)
                unitText: "m/s"
                detailText: root.number(windDirection, 0) + "° " + root.compass(windDirection) + "  Gust " + root.number(gust, 1)
            }
            WeatherTile {
                title: "RAIN RATE"
                valueText: root.number(rainRate, 1)
                unitText: "mm/h"
                detailText: "Lifetime " + root.number(rainTotal, 1) + " mm"
            }
            WeatherTile {
                title: "LIGHTNING"
                valueText: root.number(lightningCount, 0)
                unitText: ""
                detailText: root.number(lightningDistance, 1) + " km distance"
            }
            WeatherTile {
                title: "CR6 LOGGER"
                valueText: root.number(cr6Battery, 2)
                unitText: "V"
                detailText: "Panel " + root.number(cr6PanelTemp, 1) + " °C"
            }
        }

        Text {
            Layout.alignment: Qt.AlignRight
            Layout.preferredHeight: 15
            text: "Data age " + root.number(age, 0) + " s"
            color: Theme.color_font_secondary
            font.pixelSize: 10
        }
    }

    component WeatherTile: Rectangle {
        property string title: ""
        property string valueText: "--"
        property string unitText: ""
        property string detailText: ""

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: 150
        Layout.minimumHeight: 90
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.055)
        border.color: Qt.rgba(1, 1, 1, 0.10)

        Column {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: title
                color: Theme.color_font_secondary
                font.pixelSize: 10
                font.bold: true
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Text {
                    id: valueLabel
                    text: valueText
                    color: Theme.color_font_primary
                    font.pixelSize: 28
                    font.bold: true
                }
                Text {
                    anchors.baseline: valueLabel.baseline
                    text: unitText
                    color: Theme.color_font_secondary
                    font.pixelSize: 12
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: detailText
                color: Theme.color_font_secondary
                font.pixelSize: 11
            }
        }
    }
}
