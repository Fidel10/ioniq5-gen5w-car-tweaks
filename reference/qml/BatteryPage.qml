// SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
// SPDX-License-Identifier: AGPL-3.0-only
// TWEAKS_PAYLOAD_260128
import QtQuick 2.0
import "../component"
import "../component/common"
import HMIEVENTS 1.0
import AppHome_Enum 1.0

Item {
    id: root
    width: AppHomeModel.isWideScr ? DEVICE_WIDTH : ConstantModel.SCREEN_WIDTH
    height: DEVICE_HEIGHT - ConstantModel.MENU_BAR_Y

    signal goHome()

    property bool requested: false
    property bool atOtherApp: typeof AppHomeModel !== "undefined"
                               ? AppHomeModel.isAtOtherApp : false
    property int homeSeq: 0

    visible: requested && !atOtherApp
    focus: visible
    enabled: !(typeof AppHomeModel !== "undefined"
               && AppHomeModel.sysPopupShowing)

    function open() {
        requested = true
        refresh()
    }
    function close() {
        requested = false
    }

    Connections {
        target: (typeof AppHomeModel !== "undefined") ? AppHomeModel : null
        onButtonBackClicked: root.close()
        onIsAtOtherAppChanged: if (AppHomeModel.isAtOtherApp) root.close()
        onCurrentScreenChanged: root.close()
        onCurrentHomeAdvancedPageIdxChanged: root.close()
    }
    onHomeSeqChanged: if (homeSeq > 0) close()

    // ---- battery_daemon state (HTTP 127.0.0.1:8088) --------------------
    property bool serviceOk: false
    property bool socValid: false
    property real socPct: 0
    property bool battValid: false
    property int battMinC: 0
    property bool cable: false
    property bool cableKnown: false
    property bool chargingDaemon: false
    property bool ready: false
    property bool utility: false
    property string heaterState: ""

    readonly property int idealC: 21
    readonly property string daemonBase: "http://127.0.0.1:8088"

    // ---- factory model values (no extra CAN work required) ------------
    readonly property real modelSoc: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.batLevel
        return (typeof v === "number" && v >= 0) ? v : -1
    }
    readonly property bool socKnown: modelSoc >= 0 || socValid
    readonly property real socShown: modelSoc >= 0 ? modelSoc : socPct

    readonly property real heatW: {
        if (typeof AppPHEVModel === "undefined") return -1
        var h = AppPHEVModel.pwrInstantHeat
        var b = AppPHEVModel.pwrInstantBattery
        if ((typeof h !== "number" || h < 0) && (typeof b !== "number" || b < 0))
            return -1
        return (typeof h === "number" && h > 0 ? h : 0)
             + (typeof b === "number" && b > 0 ? b : 0)
    }
    readonly property string heatText: {
        if (heatW < 0) return "\u2014"
        if (heatW <= 0) return "0 W"
        return (heatW / 1000).toFixed(2) + " kW"
    }

    readonly property bool driveValid: {
        if (typeof AppPHEVModel === "undefined") return false
        var v = AppPHEVModel.pwrInstantDrivingKw
        return typeof v === "number" && v > -512
    }
    readonly property real driveKw: {
        if (!driveValid) return 0
        return AppPHEVModel.pwrInstantDrivingKw
    }
    readonly property string driveText: driveValid ? driveKw.toFixed(1) + " kW"
                                                  : "\u2014"
    property real peakDriveKw: -1e9
    property real minDriveKw: 1e9
    onDriveKwChanged: {
        if (!driveValid) return
        if (driveKw > peakDriveKw) peakDriveKw = driveKw
        if (driveKw < minDriveKw) minDriveKw = driveKw
    }
    readonly property string peakText: peakDriveKw > 0
                                       ? peakDriveKw.toFixed(1) + " kW" : "\u2014"
    readonly property string regenText: (minDriveKw < 1e8 && minDriveKw < 0)
                                        ? minDriveKw.toFixed(1) + " kW" : "\u2014"

    readonly property real consumptionKw: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.consumptionPower
        return (typeof v === "number" && v >= 0) ? v / 1000 : -1
    }
    readonly property string consumptionText: consumptionKw < 0
                                              ? "\u2014"
                                              : consumptionKw.toFixed(2) + " kW"

    readonly property bool evCharging: {
        if (typeof AppPHEVModel === "undefined") return false
        return AppPHEVModel.batChgSts === true
               && (AppPHEVModel.fastChgSts === true
                   || AppPHEVModel.stdChgSts === true)
    }
    readonly property bool evFast: {
        if (typeof AppPHEVModel === "undefined") return false
        return AppPHEVModel.fastChgSts === true
               && AppPHEVModel.stdChgSts !== true
    }
    readonly property int evTarget: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = evFast ? AppPHEVModel.batChgLvlFast
                       : AppPHEVModel.batChgLvlNormal
        return (typeof v === "number" && v >= 0 && v !== 65535) ? v : -1
    }
    readonly property int evRemain: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = evFast ? AppPHEVModel.fastChgRemTime
                       : AppPHEVModel.portChgRemTime
        return (typeof v === "number" && v >= 0 && v !== 65535) ? v : -1
    }

    readonly property string chargeStatus: {
        if (evCharging) return evFast ? "Charging \u00b7 fast" : "Charging \u00b7 normal"
        if (chargingDaemon) return "Charging (0x326)"
        if (cableKnown && cable) return "Cable connected \u00b7 not charging"
        if (cableKnown && !cable) return "Not charging \u00b7 no cable"
        return "Not charging"
    }
    readonly property string targetText: evTarget >= 0
                                         ? "Target " + evTarget + "%" : "Target \u2014"
    readonly property string remainText: evRemain < 0 ? "\u2014"
                                         : fmtMinutes(evRemain) + " left"

    readonly property int v2lTarget: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.dischargingLevel
        return (typeof v === "number" && v > 0) ? v : -1
    }
    readonly property int v2lRemain: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.V2LDischargeTime
        return (typeof v === "number" && v >= 0 && v !== 65535) ? v : -1
    }
    readonly property string v2lText: {
        if (v2lTarget < 0 && v2lRemain < 0) return "Idle"
        var parts = []
        if (v2lTarget >= 0) parts.push("target " + v2lTarget + "%")
        if (v2lRemain >= 0) parts.push(fmtMinutes(v2lRemain))
        return "V2L \u00b7 " + parts.join(" \u00b7 ")
    }
    readonly property string conditioningText: {
        if (typeof AppPHEVModel === "undefined") return "\u2014"
        var v = AppPHEVModel.batteryConditionMode
        if (typeof v !== "number" && typeof v !== "boolean") return "\u2014"
        return v ? "On" : "Off"
    }
    readonly property string winterText: {
        if (typeof AppPHEVModel === "undefined") return "\u2014"
        if (AppPHEVModel.winterModeAvailable === false) return "\u2014"
        var v = AppPHEVModel.winterMode
        if (typeof v !== "number" && typeof v !== "boolean") return "\u2014"
        return v ? "On" : "Off"
    }
    readonly property real capacityKwh: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.batCapacity
        return (typeof v === "number" && v > 0) ? v : -1
    }
    readonly property string capacityText: capacityKwh > 0
                                             ? capacityKwh.toFixed(1) + " kWh"
                                             : "\u2014"
    readonly property int lowSocPct: {
        if (typeof AppPHEVModel === "undefined") return -1
        var v = AppPHEVModel.percentLowSoc
        return (typeof v === "number" && v >= 0 && v <= 100) ? v : -1
    }
    readonly property string supportText: {
        if (typeof AppPHEVModel === "undefined") return "\u2014"
        var l = AppPHEVModel.supportV2L === true ? "V2L yes" : "V2L no"
        var g = AppPHEVModel.supportV2G === true ? "V2G yes" : "V2G no"
        return l + " \u00b7 " + g
    }
    readonly property string heaterText: {
        var s = heaterState
        if (s === "" || s === "unknown") return "\u2014"
        return s.charAt(0).toUpperCase() + s.substring(1)
    }

    function fmtMinutes(t) {
        if (t < 0 || t === 65535) return "\u2014"
        if (t === 0) return "0 min"
        if (t < 60) return t + " min"
        var h = Math.floor(t / 60)
        var m = t % 60
        return h + " h " + (m < 10 ? "0" : "") + m
    }

    function refresh() {
        var x = new XMLHttpRequest()
        x.open("GET", daemonBase + "/status", true)
        x.onreadystatechange = function() {
            if (x.readyState !== 4) return
            if (x.status !== 200) { root.serviceOk = false; return }
            try {
                var d = JSON.parse(x.responseText)
                root.serviceOk = d.ok === true
                root.socValid = d.soc_valid === true
                root.socPct = (typeof d.soc_pct === "number") ? d.soc_pct : 0
                root.battValid = d.batt_valid === true
                root.battMinC = (typeof d.batt_min_c === "number") ? d.batt_min_c : 0
                root.cable = d.cable === true
                root.cableKnown = d.cable_known === true
                root.chargingDaemon = d.charging === true
                root.ready = d.ready === true
                root.utility = d.utility === true
                root.heaterState = (typeof d.state === "string") ? d.state : ""
            } catch (e) { root.serviceOk = false }
        }
        x.send()
    }

    Timer {
        interval: 1500
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // ---- background ----------------------------------------------------
    Q_ThemeImage {
        anchors.fill: parent
        themeSource: AppHomeModel.isWideScr
                      ? defineModel.home_main_bg_01 : defineModel.home_main_bg_02
    }

    MouseArea {
        anchors.fill: parent
        z: 1
        preventStealing: true
        acceptedButtons: Qt.AllButtons
        onPressed: mouse.accepted = true
        onReleased: mouse.accepted = true
        onClicked: mouse.accepted = true
        onWheel: wheel.accepted = true
    }

    Item {
        id: content
        z: 2
        width: 1180
        height: 630
        x: (root.width - width) / 2

        QText {
            id: title
            x: 0
            y: 2
            text: "Battery"
            font.pixelSize: ConstantModel.FONT_SIZE_42
            textBold: true
            color: HomeThemeHelper.normalTextColor
        }

        QText {
            id: subtitle
            x: 2
            y: 56
            text: root.serviceOk ? "traction battery \u00b7 live"
                                 : "battery service unavailable"
            font.pixelSize: ConstantModel.FONT_SIZE_21
            color: HomeThemeHelper.normalTextColor
        }

        Rectangle {
            id: closeButton
            property bool pressActive: false
            anchors.right: parent.right
            y: 22
            width: 140
            height: 46
            radius: 23
            color: closeMouse.pressed && pressActive
                   ? ConstantModel.GENERAL_COLOR_FOCUS_GREY
                   : ConstantModel.GENERAL_COLOR_BUTTON_GREY
            border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
            border.width: 1

            QText {
                anchors.centerIn: parent
                text: "\u2715  Exit"
                font.pixelSize: ConstantModel.FONT_SIZE_24
                color: HomeThemeHelper.normalTextColor
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                onPressed: closeButton.pressActive = true
                onPositionChanged:
                    if (!containsMouse) closeButton.pressActive = false
                onReleased: {
                    if (closeButton.pressActive) {
                        QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                        root.close()
                    }
                    closeButton.pressActive = false
                }
            }
        }

        // ---- State of charge -------------------------------------------
        Rectangle {
            x: 0
            y: 120
            width: 370
            height: 190
            radius: 14
            color: "#1B1B1B"
            border.color: "#333333"
            border.width: 1

            QText {
                x: 20
                y: 14
                text: "State of charge"
                font.pixelSize: 20
                color: "#B0B0B0"
            }
            QText {
                x: 20
                y: 44
                text: root.socKnown ? root.socShown.toFixed(0) + "%" : "--"
                font.pixelSize: 64
                textBold: true
                color: "#FFFFFF"
            }
            QText {
                x: 20
                y: 128
                width: 330
                text: root.ready ? "vehicle READY" : "vehicle not ready"
                font.pixelSize: 18
                color: root.ready ? "#4CAF50" : "#B0B0B0"
            }
            QText {
                x: 20
                y: 156
                width: 330
                text: root.utility ? "utility mode" : "traction battery"
                font.pixelSize: 15
                color: "#7A7A7A"
            }
            QText {
                x: 20
                y: 174
                width: 330
                text: "capacity " + root.capacityText
                      + (root.lowSocPct >= 0 ? " \u00b7 low " + root.lowSocPct + "%" : "")
                font.pixelSize: 13
                elide: Text.ElideRight
                color: "#666666"
            }
        }

        // ---- Minimum cell temperature ----------------------------------
        Rectangle {
            x: 390
            y: 120
            width: 370
            height: 190
            radius: 14
            color: "#1B1B1B"
            border.color: "#333333"
            border.width: 1

            QText {
                x: 20
                y: 14
                text: "Minimum cell temperature"
                font.pixelSize: 20
                color: "#B0B0B0"
            }
            QText {
                x: 20
                y: 44
                text: root.battValid ? root.battMinC + " \u00b0C" : "--"
                font.pixelSize: 56
                textBold: true
                color: root.battValid && root.battMinC >= root.idealC
                       ? "#4CAF50" : "#FFFFFF"
            }

            Rectangle {
                x: 20
                y: 124
                width: 330
                height: 10
                radius: 5
                color: "#2A2A2A"

                Rectangle {
                    width: 330 * Math.max(0, Math.min(1, root.battMinC / 30))
                    height: 10
                    radius: 5
                    color: root.battMinC >= root.idealC ? "#4CAF50" : "#FFB300"
                }
                Rectangle {
                    x: 330 * (root.idealC / 30) - 1
                    y: -3
                    width: 3
                    height: 16
                    color: "#FFFFFF"
                }
            }
            QText {
                x: 20
                y: 144
                width: 330
                text: "ideal for charging " + root.idealC + " \u00b0C"
                font.pixelSize: 16
                color: "#7A7A7A"
            }
            QText {
                x: 20
                y: 166
                width: 330
                text: "only minimum on 0x2FC \u00b7 no max"
                font.pixelSize: 13
                color: "#666666"
            }
        }

        // ---- Power ------------------------------------------------------
        Rectangle {
            x: 780
            y: 120
            width: 400
            height: 190
            radius: 14
            color: "#1B1B1B"
            border.color: "#333333"
            border.width: 1

            QText {
                x: 20
                y: 10
                text: "Power \u00b7 drive / regen"
                font.pixelSize: 18
                color: "#B0B0B0"
            }

            Item {
                id: gauge
                x: 60
                y: 22
                width: 280
                height: 92

                readonly property real gaugeMin: -100
                readonly property real gaugeMax: 160
                readonly property real gaugeSpan: gaugeMax - gaugeMin
                readonly property real zeroFrac: (0 - gaugeMin) / gaugeSpan
                readonly property real val: root.driveValid
                                           ? Math.max(gaugeMin, Math.min(gaugeMax, root.driveKw))
                                           : gaugeMin
                readonly property real frac: (val - gaugeMin) / gaugeSpan
                readonly property real angle: -90 + 180 * frac

                Repeater {
                    model: 53
                    delegate: Rectangle {
                        x: gauge.width / 2 - 1
                        y: gauge.height - 70
                        width: 2
                        height: 9
                        color: (index / 52) < gauge.zeroFrac ? "#4CAF50"
                             : (index / 52) > 0.9615 ? "#FFB300" : "#7A7A7A"
                        transform: Rotation {
                            origin.x: 1
                            origin.y: 70
                            angle: -90 + index * (180 / 52)
                        }
                    }
                }

                Rectangle {
                    x: gauge.width / 2 - 1
                    y: gauge.height - 58
                    width: 2
                    height: 58
                    color: (root.driveValid && root.driveKw < 0)
                           ? "#4CAF50" : "#FFFFFF"
                    transform: Rotation {
                        origin.x: 1
                        origin.y: 58
                        angle: gauge.angle
                    }
                }

                Rectangle {
                    x: gauge.width / 2 - 4
                    y: gauge.height - 4
                    width: 8
                    height: 8
                    radius: 4
                    color: "#E0E0E0"
                }

                QText {
                    x: 6
                    y: 74
                    text: "-100"
                    font.pixelSize: 11
                    color: "#666666"
                }
                QText {
                    x: 240
                    y: 74
                    text: "160"
                    font.pixelSize: 11
                    color: "#666666"
                }
            }

            QText {
                x: 0
                y: 114
                width: 400
                horizontalAlignment: Text.AlignHCenter
                text: root.driveText
                font.pixelSize: 30
                textBold: true
                color: (root.driveValid && root.driveKw < 0)
                       ? "#4CAF50" : "#FFFFFF"
            }

            QText {
                x: 0
                y: 152
                width: 400
                horizontalAlignment: Text.AlignHCenter
                text: "peak " + root.peakText + " \u00b7 regen " + root.regenText
                font.pixelSize: 12
                color: "#8A8A8A"
            }

            QText {
                x: 0
                y: 170
                width: 400
                horizontalAlignment: Text.AlignHCenter
                text: "care " + root.heatText + " \u00b7 cons " + root.consumptionText
                font.pixelSize: 12
                color: "#666666"
            }
        }

        // ---- Charging ---------------------------------------------------
        Rectangle {
            x: 0
            y: 330
            width: 570
            height: 190
            radius: 14
            color: "#1B1B1B"
            border.color: root.evCharging ? "#2E7D32" : "#333333"
            border.width: 1

            QText {
                x: 20
                y: 14
                text: "Charging"
                font.pixelSize: 20
                color: "#B0B0B0"
            }
            QText {
                x: 20
                y: 44
                width: 530
                text: root.chargeStatus
                font.pixelSize: 30
                textBold: true
                elide: Text.ElideRight
                color: root.evCharging ? "#4CAF50" : "#FFFFFF"
            }
            QText {
                x: 20
                y: 96
                text: root.targetText
                font.pixelSize: 22
                color: "#DDDDDD"
            }
            QText {
                x: 300
                y: 96
                width: 250
                horizontalAlignment: Text.AlignRight
                text: root.remainText
                font.pixelSize: 22
                color: "#DDDDDD"
            }
            QText {
                x: 20
                y: 134
                width: 530
                text: "fast " + (root.evFast ? "yes" : "no")
                      + " \u00b7 std " + (root.evCharging && !root.evFast ? "yes" : "no")
                      + " \u00b7 cable " + (root.cableKnown
                                            ? (root.cable ? "yes" : "no") : "?")
                font.pixelSize: 16
                color: "#7A7A7A"
            }
            QText {
                x: 20
                y: 162
                width: 530
                text: "AppPHEVModel \u00b7 0x326 cable state"
                font.pixelSize: 13
                color: "#666666"
            }
        }

        // ---- Heater / V2L / care ---------------------------------------
        Rectangle {
            x: 590
            y: 330
            width: 590
            height: 190
            radius: 14
            color: "#1B1B1B"
            border.color: "#333333"
            border.width: 1

            QText {
                x: 20
                y: 14
                text: "Heater, V2L and settings"
                font.pixelSize: 20
                color: "#B0B0B0"
            }

            QText {
                x: 20
                y: 48
                text: "Heater"
                font.pixelSize: 17
                color: "#9A9A9A"
            }
            QText {
                x: 180
                y: 44
                width: 390
                horizontalAlignment: Text.AlignRight
                text: root.heaterText + " \u00b7 " + root.heatText
                font.pixelSize: 22
                textBold: true
                elide: Text.ElideRight
                color: root.heatW > 0 ? "#4CAF50" : "#FFFFFF"
            }

            QText {
                x: 20
                y: 88
                text: "V2L"
                font.pixelSize: 17
                color: "#9A9A9A"
            }
            QText {
                x: 180
                y: 84
                width: 390
                horizontalAlignment: Text.AlignRight
                text: root.v2lText
                font.pixelSize: 22
                textBold: true
                elide: Text.ElideRight
                color: root.v2lTarget >= 0 ? "#4CAF50" : "#FFFFFF"
            }

            QText {
                x: 20
                y: 122
                text: "Conditioning"
                font.pixelSize: 17
                color: "#9A9A9A"
            }
            QText {
                x: 180
                y: 118
                width: 390
                horizontalAlignment: Text.AlignRight
                text: root.conditioningText
                font.pixelSize: 22
                textBold: true
                color: "#FFFFFF"
            }

            QText {
                x: 20
                y: 160
                text: "Winter mode"
                font.pixelSize: 17
                color: "#9A9A9A"
            }
            QText {
                x: 180
                y: 156
                width: 390
                horizontalAlignment: Text.AlignRight
                text: root.winterText
                font.pixelSize: 22
                textBold: true
                color: "#FFFFFF"
            }
        }

        QText {
            id: footer
            x: 0
            y: 540
            width: 1180
            text: (root.serviceOk ? "daemon online" : "daemon unavailable")
                  + " \u00b7 " + (root.ready ? "READY" : "not ready")
                  + " \u00b7 utility " + (root.utility ? "on" : "off")
                  + " \u00b7 heater " + root.heaterText
                  + " \u00b7 " + root.supportText
                  + " \u00b7 SOH/12V not exposed"
                  + " \u00b7 temp source 0x2FC b2"
            font.pixelSize: 15
            color: root.serviceOk ? "#7A7A7A" : "#FF7043"
            elide: Text.ElideRight
        }
    }
}
