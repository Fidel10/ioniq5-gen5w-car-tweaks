// SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
// SPDX-License-Identifier: AGPL-3.0-only
// TWEAKS_PAYLOAD_260128
import QtQuick 2.0
import "common"

Item {
    id: root
    width: 306
    height: 249

    function hasUnit(s) {
        return s.indexOf("\u00b0") >= 0 || s.indexOf("\u2103") >= 0
               || s.indexOf("\u2109") >= 0
    }

    function unitSuffix() {
        if (typeof appClimateModel === "undefined") return ""
        return appClimateModel.tempUnit === 2 ? "\u00b0F" : "\u00b0C"
    }

    // Interior: the driver's set temperature shown by the climate screen.
    // There is no measured cabin-temperature sensor exposed to QML.
    readonly property string intText: {
        if (typeof appClimateModel === "undefined") return "--"
        var v = appClimateModel.levelDriver
        if (typeof v !== "number" || v <= 0) return "--"
        return v + unitSuffix()
    }

    // Exterior: factory ambient temperature string (may already carry a unit).
    readonly property string extText: {
        if (typeof appClimateModel === "undefined") return "--"
        var s = appClimateModel.ambienTemp
        if (s === undefined || s === null) return "--"
        s = String(s).replace(/\s+$/, "")
        if (s.length === 0) return "--"
        if (hasUnit(s)) return s
        return s + unitSuffix()
    }

    Q_ThemeImage {
        anchors.centerIn: parent
        themeSource: defineModel.home_bg_icon_n
    }

    Item {
        x: 0
        y: 0
        width: parent.width / 2
        height: 150

        QText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 60
            text: "INT"
            font.pixelSize: 18
            color: "#9A9A9A"
        }
        QText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 84
            text: root.intText
            font.pixelSize: 36
            textBold: true
            color: "#FFFFFF"
        }
    }

    Rectangle {
        x: parent.width / 2 - 1
        y: 70
        width: 2
        height: 56
        color: "#2E2E2E"
    }

    Item {
        x: parent.width / 2
        y: 0
        width: parent.width / 2
        height: 150

        QText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 60
            text: "EXT"
            font.pixelSize: 18
            color: "#9A9A9A"
        }
        QText {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 84
            text: root.extText
            font.pixelSize: 36
            textBold: true
            color: "#FFFFFF"
        }
    }

    QText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 168
        text: "Clima"
        font.pixelSize: 26
        color: "#FFFFFF"
    }
    QText {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 202
        text: "interior \u00b7 exterior"
        font.pixelSize: 14
        color: "#8A8A8A"
    }
}
