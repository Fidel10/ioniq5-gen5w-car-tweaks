// SPDX-FileCopyrightText: 2026 The SCOURGE Project contributors
// SPDX-License-Identifier: AGPL-3.0-only
// WIFI_PAYLOAD_260128
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

    // ---- foreground / home-key handling --------------------------------
    property bool requested: false
    property bool atOtherApp: typeof AppHomeModel !== "undefined"
                               ? AppHomeModel.isAtOtherApp : false
    property int homeSeq: 0
    property string homeSource: "none"
    property int lastAppKey: -1
    property bool homeMonitor: false

    visible: requested && !atOtherApp
    focus: visible
    /* Stock rule: never fight a system popup for input (styleguide §4.6). */
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
        onRequestHomeByPPChanged: if (AppHomeModel.requestHomeByPP) root.close()
    }
    onHomeSeqChanged: if (homeSeq > 0) close()

    // ---- daemon state (wifi_daemon, HTTP 127.0.0.1:8090) ---------------
    property bool serviceOk: false
    property string mode: "off"          // client | carplay | off
    property bool applying: false
    property bool wlanOn: false
    property bool driver: false
    property string ip: ""
    property string ssid: ""
    // Optional: SSID that should preselect the 2.x subnet. Leave empty and
    // use the "IOT 2.x" preset button in the join dialog instead.
    property string iotSsid: ""
    property int wlanSignal: 0
    property bool sshActive: false
    property bool sshEnabled: false
    property int sshPort: 2222
    property bool sshPortFallback: false
    property bool debugConsole: false
    property string clientSsid: ""
    property string clientBssid: ""
    property string clientFreq: ""
    property string daemonMessage: ""
    property string daemonVer: ""

    // ---- tabs ----------------------------------------------------------
    property int currentTab: 0     // 0 WiFi | 1 Redes | 2 Ping | 3 SSH | 4 Log

    // ---- scan / join ---------------------------------------------------
    property bool scanning: false
    property string scanError: ""
    property bool joinDialog: false
    property string joinSsid: ""
    property string joinSecurity: "WPA2"
    property string joinIp: ""
    property string joinGw: ""
    property bool kbShift: false
    property bool kbSym: false

    // ---- ping ----------------------------------------------------------
    readonly property var pingTargets: ["google.com", "192.168.1.1",
                                        "192.168.2.1", "1.1.1.1"]
    property var pingStates: ({})
    property var pingQueue: []
    property bool pingBusy: false
    property string pingResult: "Sem testes. Prime em Ping all ou num alvo."

    // ---- logs ----------------------------------------------------------
    property string consoleSource: "daemon"   // daemon | wpa | ssh
    property string dumpState: "idle"
    property string dumpMessage: ""
    property string dumpDir: ""
    readonly property bool dumpBusy: dumpState === "saving"

    // ---- helpers -------------------------------------------------------
    readonly property string modeText: mode === "client" ? "Client"
                                     : mode === "carplay" ? "CarPlay AP"
                                     : "Off"
    readonly property string sshCommand: "ssh car@" + (ip !== "" ? ip : "<car-ip>")
                                         + " -p " + sshPort
    readonly property bool band5g: clientFreq.length > 0 && clientFreq.charAt(0) === "5"

    function signalPct(dbm) {
        if (dbm >= -50) return 100
        if (dbm <= -100) return 0
        return Math.round(2 * (dbm + 100))
    }

    function signalWord(dbm) {
        if (dbm >= -55) return "Excelente"
        if (dbm >= -67) return "Bom"
        if (dbm >= -75) return "Razo\u00e1vel"
        return "Fraco"
    }

    function applyStatus(d) {
        mode = d.mode || "off"
        applying = d.applying === true
        wlanOn = d.wlan_on === true
        driver = d.driver === true
        ip = d.ip || ""
        ssid = d.ssid || ""
        wlanSignal = (typeof d.signal === "number") ? d.signal : 0
        sshActive = d.ssh_active === true
        sshEnabled = d.ssh_enabled === true
        sshPort = (typeof d.ssh_port === "number") ? d.ssh_port : 2222
        sshPortFallback = d.ssh_port_fallback === true
        debugConsole = d.debug_console === true
        clientSsid = d.client_ssid || ""
        clientBssid = d.client_bssid || ""
        clientFreq = d.client_freq || ""
        daemonMessage = d.message || ""
        daemonVer = d.version || ""
        dumpState = d.dump_state || "idle"
        dumpMessage = d.dump_message || ""
        dumpDir = d.dump_dir || ""
    }

    // ---- daemon I/O ----------------------------------------------------
    function refreshFromFile() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        applyStatus(JSON.parse(xhr.responseText))
                        serviceOk = true
                    } catch (e) {
                        serviceOk = false
                    }
                } else {
                    serviceOk = false
                }
            }
        }
        xhr.open("GET", "file:///rw_data/wifi/status.json")
        xhr.send()
    }

    function refresh() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        applyStatus(JSON.parse(xhr.responseText))
                        serviceOk = true
                        return
                    } catch (e) {
                        // fall through to the file mirror
                    }
                }
                refreshFromFile()
            }
        }
        xhr.open("GET", "http://127.0.0.1:8090/status")
        xhr.send()
    }

    // Fast-path Home/Star poll: the daemon writes home.json on every
    // steering-wheel Home/Star press (session bus).  A new seq closes the
    // overlay without waiting for the full status cycle.
    function refreshHome() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200 && xhr.status !== 0) return
            try {
                var d = JSON.parse(xhr.responseText)
                var seq = (typeof d.seq === "number") ? d.seq : 0
                if (seq > 0 && seq !== root.homeSeq)
                    root.homeSeq = seq
            } catch (e) {}
        }
        xhr.open("GET", "file:///rw_data/wifi/home.json")
        xhr.send()
    }

    function refreshConsole() {
        if (root.currentTab !== 4) return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            try {
                var d = JSON.parse(xhr.responseText)
                var t = d.log || ""
                var lines = t.split("\n")
                var start = Math.max(0, lines.length - 60)
                consoleModel.clear()
                for (var i = start; i < lines.length; i++) {
                    if (lines[i].length > 0)
                        consoleModel.append({ line: lines[i] })
                }
            } catch (e) {}
        }
        xhr.open("GET", "http://127.0.0.1:8090/logs?source=" + consoleSource)
        xhr.send()
    }

    function post(path) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) refresh()
        }
        xhr.open("POST", "http://127.0.0.1:8090" + path)
        xhr.send()
    }

    // ---- scan ----------------------------------------------------------
    function scan() {
        if (scanning || mode === "carplay") return
        scanning = true
        scanError = ""
        scanModel.clear()
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            scanning = false
            var d = null
            try { d = JSON.parse(xhr.responseText) } catch (e) {
                scanError = "Resposta invalida do daemon"
                return
            }
            if (d.ok !== true) {
                scanError = d.error || "Scan falhou"
                return
            }
            var list = d.networks || []
            list.sort(function(a, b) {
                return (b.signal || -100) - (a.signal || -100)
            })
            for (var i = 0; i < list.length; i++) {
                var n = list[i]
                scanModel.append({
                    ssid: n.ssid || "",
                    bssid: n.bssid || "",
                    freq: n.freq || "",
                    signal: (typeof n.signal === "number") ? n.signal : -100,
                    security: n.security || "Open"
                })
            }
            if (scanModel.count === 0) scanError = "Nenhuma rede encontrada"
        }
        xhr.open("GET", "http://127.0.0.1:8090/scan")
        xhr.send()
    }

    function openJoin(ssidName, security) {
        joinSsid = ssidName
        joinSecurity = security
        joinDialog = true
        kbShift = false
        kbSym = false
        pskField.text = ""
        if (iotSsid !== "" && ssidName === iotSsid) {
            joinIp = "192.168.2.228"
            joinGw = "192.168.2.1"
        } else {
            joinIp = "192.168.1.228"
            joinGw = "192.168.1.1"
        }
        joinNote.text = "IP " + joinIp + "  \u00b7  gw " + joinGw
        joinNote.color = "#9A9A9A"
        pskField.forceActiveFocus()
    }

    function setJoinPreset(ip, gw) {
        joinIp = ip
        joinGw = gw
        joinNote.text = ip === "" ? "Manter o IP atual"
                                  : "IP " + ip + "  \u00b7  gw " + gw
        joinNote.color = "#9A9A9A"
    }

    function joinNetwork() {
        var p = pskField.text
        if (joinSecurity !== "Open" && p.length > 0 && p.length < 8) {
            joinNote.text = "A password WPA2 tem de ter 8 a 63 caracteres."
            joinNote.color = "#EF5350"
            return
        }
        var url = "http://127.0.0.1:8090/client/join?ssid=" + encodeURIComponent(joinSsid)
        if (p.length > 0) url += "&psk=" + encodeURIComponent(p)
        if (root.joinIp !== "") {
            url += "&ip=" + encodeURIComponent(root.joinIp)
                 + "&gw=" + encodeURIComponent(root.joinGw)
                 + "&mask=255.255.255.0"
        }
        joinDialog = false
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) refresh()
        }
        xhr.open("POST", url)
        xhr.send()
    }

    function kbKey(k) {
        if (k === "SHIFT") { kbShift = !kbShift; return }
        if (k === "SYM") { kbSym = !kbSym; return }
        if (k === "SPACE") { pskField.text += " "; return }
        if (k === "BKSP") {
            pskField.text = pskField.text.substring(0, pskField.text.length - 1)
            return
        }
        var ch = k
        if (!kbSym && kbShift) ch = k.toUpperCase()
        pskField.text += ch
    }

    // ---- ping ----------------------------------------------------------
    function pingStateText(host) {
        var s = root.pingStates[host]
        return s ? s.text : "por testar"
    }

    function pingStateOk(host) {
        var s = root.pingStates[host]
        return s ? s.reachable === true : false
    }

    function pingHost(host) {
        if (root.pingBusy) return
        root.pingBusy = true
        root.pingResult = "A fazer ping a " + host + "\u2026"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            var reach = false
            var summ = "sem resposta"
            var out = ""
            try {
                var d = JSON.parse(xhr.responseText)
                reach = d.reachable === true
                summ = d.summary || (reach ? "ok" : "sem resposta")
                out = d.out || ""
            } catch (e) {
                summ = "erro do daemon"
            }
            var st = root.pingStates
            st[host] = { reachable: reach, text: summ }
            root.pingStates = st
            root.pingResult = host + ": " + summ + (out !== "" ? "\n" + out : "")
            root.pingBusy = false
            if (root.pingQueue.length > 0) {
                var next = root.pingQueue.shift()
                root.pingHost(next)
            }
        }
        xhr.open("GET", "http://127.0.0.1:8090/ping?host=" + encodeURIComponent(host))
        xhr.send()
    }

    function pingAll() {
        if (root.pingBusy) return
        root.pingStates = ({})
        root.pingQueue = ["192.168.1.1", "192.168.2.1", "1.1.1.1"]
        root.pingHost("google.com")
    }

    function scanModelEmpty() {
        return scanModel.count === 0
    }

    // ---- polling timers ------------------------------------------------
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshHome()
    }

    Timer {
        interval: 1500
        running: root.visible && root.currentTab === 4
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshConsole()
    }

    // ---- background: the stock themed home background (styleguide §3) ----
    Q_ThemeImage {
        anchors.fill: parent
        themeSource: AppHomeModel.isWideScr
                      ? defineModel.home_main_bg_01 : defineModel.home_main_bg_02
    }

    // Full-screen input shield: accept every press/release/wheel so no
    // event reaches the home grid or another app's surface underneath.
    MouseArea {
        id: shield
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

        Image {
            id: headerIcon
            x: 0
            y: 8
            width: 56
            height: 56
            smooth: true
            source: "file:///app/share/AppHomeScreen/wifi/wifi_icon_n.png"
        }

        QText {
            id: title
            x: 74
            y: 2
            text: "WiFi"
            font.pixelSize: ConstantModel.FONT_SIZE_42
            textBold: true
            color: HomeThemeHelper.normalTextColor
        }

        QText {
            id: subtitle
            x: 76
            y: 56
            text: {
                var svc = root.serviceOk ? "ok" : "sem servico"
                return (root.wlanOn ? "WiFi ligado" : "WiFi desligado")
                       + "   \u00b7   " + root.modeText
                       + "   \u00b7   " + svc
            }
            font.pixelSize: ConstantModel.FONT_SIZE_21
            color: HomeThemeHelper.normalTextColor
        }

        // ---- top buttons --------------------------------------------------
        Rectangle {
            id: closeButton
            property bool pressActive: false
            anchors.right: parent.right
            y: 22
            width: 130
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
                font.pixelSize: ConstantModel.FONT_SIZE_21
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

        Rectangle {
            id: saveLogsButton
            property bool pressActive: false
            anchors.right: closeButton.left
            anchors.rightMargin: 10
            y: 22
            width: 150
            height: 46
            radius: 23
            color: saveLogsMouse.pressed && pressActive
                   ? ConstantModel.GENERAL_COLOR_FOCUS_GREY
                   : ConstantModel.GENERAL_COLOR_BUTTON_GREY
            border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
            border.width: 1
            opacity: (root.serviceOk && !root.dumpBusy) ? 1.0 : 0.55

            QText {
                anchors.centerIn: parent
                text: root.dumpBusy ? "A guardar\u2026" : "Guardar logs"
                font.pixelSize: ConstantModel.FONT_SIZE_21
                color: HomeThemeHelper.normalTextColor
            }

            MouseArea {
                id: saveLogsMouse
                anchors.fill: parent
                onPressed: saveLogsButton.pressActive = true
                onPositionChanged:
                    if (!containsMouse) saveLogsButton.pressActive = false
                onReleased: {
                    if (saveLogsButton.pressActive && root.serviceOk && !root.dumpBusy)
                        root.post("/logs/dump")
                    saveLogsButton.pressActive = false
                }
            }
        }

        // ---- tab row (VISIBLE, above the content) -------------------------
        Row {
            id: tabRow
            x: 0
            y: 100
            spacing: 10

            Repeater {
                model: ["WiFi", "Redes", "Ping", "SSH", "Log"]
                delegate: Rectangle {
                    width: 170
                    height: 46
                    radius: 23
                    color: root.currentTab === index
                           ? "#3A3A3A" : ConstantModel.GENERAL_COLOR_BUTTON_GREY
                    border.color: root.currentTab === index
                                  ? "#8A8A8A" : ConstantModel.GENERAL_COLOR_FOCUS_GREY
                    border.width: root.currentTab === index ? 2 : 1

                    QText {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: ConstantModel.FONT_SIZE_21
                        textBold: root.currentTab === index
                        color: root.currentTab === index
                               ? "#FFFFFF" : HomeThemeHelper.normalTextColor
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                            root.currentTab = index
                            if (index === 1 && root.wlanOn && !root.scanning
                                && root.scanModelEmpty())
                                root.scan()
                            if (index === 4) root.refreshConsole()
                            if (index === 2 && Object.keys(root.pingStates).length === 0
                                && !root.pingBusy)
                                root.pingAll()
                        }
                    }
                }
            }
        }

        // =================================================================
        // WiFi tab: one compact summary panel
        // =================================================================
        Item {
            visible: root.currentTab === 0

            Rectangle {
                x: 0
                y: 166
                width: 1180
                height: 150
                radius: 14
                color: ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                // WiFi on/off
                QText {
                    x: 28
                    y: 14
                    text: "WiFi"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 28
                    y: 40
                    text: root.wlanOn ? "On" : "Off"
                    font.pixelSize: 34
                    textBold: true
                    color: root.wlanOn ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }
                WifiSwitch {
                    x: 28
                    y: 88
                    checked: root.wlanOn
                    switchEnabled: root.serviceOk && !root.applying
                    onToggled: root.post("/wlan?on=" + (root.wlanOn ? "0" : "1"))
                }

                Rectangle { x: 220; y: 16; width: 1; height: 118; color: "#3A3A3A" }

                // SSID
                QText {
                    x: 252
                    y: 14
                    text: "SSID"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 252
                    y: 40
                    width: 250
                    text: root.clientSsid !== "" ? root.clientSsid
                         : (root.ssid !== "" ? root.ssid : "--")
                    font.pixelSize: ConstantModel.FONT_SIZE_30
                    textBold: true
                    elide: Text.ElideRight
                    color: HomeThemeHelper.normalTextColor
                }
                QText {
                    x: 252
                    y: 88
                    width: 250
                    text: root.ip !== "" ? root.ip : "sem IP"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    elide: Text.ElideRight
                    color: root.ip !== "" ? "#4CAF50" : "#9A9A9A"
                }

                Rectangle { x: 534; y: 16; width: 1; height: 118; color: "#3A3A3A" }

                // Signal
                QText {
                    x: 566
                    y: 14
                    text: "Sinal"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 566
                    y: 40
                    width: 200
                    text: (root.wlanOn && root.driver) ? root.signalWord(root.wlanSignal) : "--"
                    font.pixelSize: ConstantModel.FONT_SIZE_30
                    textBold: true
                    elide: Text.ElideRight
                    color: (root.wlanOn && root.wlanSignal >= -67)
                           ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }
                QText {
                    x: 566
                    y: 88
                    text: (root.wlanOn && root.driver)
                          ? root.wlanSignal + " dBm" : "--"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                // signal bar
                Rectangle {
                    x: 566
                    y: 118
                    width: 200
                    height: 6
                    radius: 3
                    color: "#2A2A2E"
                    Rectangle {
                        width: (root.wlanOn && root.driver)
                               ? parent.width * root.signalPct(root.wlanSignal) / 100 : 0
                        height: parent.height
                        radius: 3
                        color: root.wlanSignal >= -67 ? "#4CAF50"
                             : root.wlanSignal >= -75 ? "#FFB300" : "#EF5350"
                    }
                }

                Rectangle { x: 806; y: 16; width: 1; height: 118; color: "#3A3A3A" }

                // SSH
                QText {
                    x: 838
                    y: 14
                    text: "SSH"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 838
                    y: 40
                    width: 300
                    text: root.sshActive ? "On" : "Off"
                    font.pixelSize: ConstantModel.FONT_SIZE_30
                    textBold: true
                    color: root.sshActive ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }
                QText {
                    x: 838
                    y: 88
                    width: 300
                    text: root.sshActive ? root.sshCommand : "inativo"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    elide: Text.ElideRight
                    color: "#9A9A9A"
                }
            }

            // connection actions, compact
            Rectangle {
                x: 0
                y: 330
                width: 1180
                height: 100
                radius: 14
                color: ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                QText {
                    x: 28
                    y: 12
                    text: root.mode === "client" && root.ip !== ""
                          ? "Ligado a " + (root.clientSsid !== "" ? root.clientSsid : root.ssid)
                            + (root.clientFreq !== "" ? "   \u00b7   " + root.clientFreq : "")
                          : (root.wlanOn ? "A ligar\u2026" : "WiFi desligado")
                    font.pixelSize: ConstantModel.FONT_SIZE_21
                    elide: Text.ElideRight
                    width: 600
                    color: root.mode === "client" && root.ip !== ""
                           ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }
                QText {
                    x: 28
                    y: 52
                    width: 600
                    text: root.daemonMessage !== "" ? root.daemonMessage
                          : (root.serviceOk ? "Servico ligado" : "Servico indisponivel")
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    elide: Text.ElideRight
                    color: root.applying ? "#FFB300" : "#9A9A9A"
                }

                WifiButton {
                    x: 780
                    y: 26
                    width: 120
                    label: "Ligar"
                    buttonEnabled: root.serviceOk && !root.applying
                    onClicked: root.post("/client/connect")
                }
                WifiButton {
                    x: 910
                    y: 26
                    width: 120
                    label: "Desligar"
                    buttonEnabled: root.serviceOk && !root.applying
                    onClicked: root.post("/client/disconnect")
                }
                WifiButton {
                    x: 1040
                    y: 26
                    width: 110
                    label: root.band5g ? "5 GHz" : "2.4 GHz"
                    buttonEnabled: root.serviceOk && !root.applying
                    onClicked: root.post("/client/band?value="
                                         + (root.band5g ? "2.4" : "5"))
                }
            }
        }

        // =================================================================
        // Redes tab: scan with signal strength + join
        // =================================================================
        Item {
            visible: root.currentTab === 1

            WifiButton {
                id: scanButton
                x: 0
                y: 166
                width: 150
                label: root.scanning ? "A procurar\u2026" : "Procurar"
                buttonEnabled: root.serviceOk && root.wlanOn && !root.scanning
                               && root.mode !== "carplay"
                onClicked: root.scan()
            }
            QText {
                x: 166
                y: 176
                width: 500
                text: !root.wlanOn ? "WiFi desligado \u2014 liga no separador WiFi"
                      : root.scanError !== "" ? root.scanError
                      : (root.scanning ? "A procurar redes\u2026"
                         : scanModel.count + " rede(s)")
                font.pixelSize: ConstantModel.FONT_SIZE_18
                elide: Text.ElideRight
                color: (!root.wlanOn || root.scanError !== "")
                       ? "#FFB300" : "#9A9A9A"
            }
            QText {
                x: 700
                y: 176
                width: 480
                horizontalAlignment: Text.AlignRight
                text: root.clientSsid !== ""
                      ? "ligado a " + root.clientSsid : ""
                font.pixelSize: ConstantModel.FONT_SIZE_18
                elide: Text.ElideRight
                color: "#4CAF50"
            }

            Rectangle {
                x: 0
                y: 224
                width: 1180
                height: 406
                radius: 14
                color: ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                ListView {
                    id: scanView
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    spacing: 6
                    model: scanModel

                    QText {
                        anchors.centerIn: parent
                        visible: scanModel.count === 0 && !root.scanning
                        text: "Sem redes. Prime Procurar."
                        font.pixelSize: ConstantModel.FONT_SIZE_18
                        color: "#9A9A9A"
                    }

                    delegate: Rectangle {
                        width: scanView.width
                        height: 62
                        radius: 10
                        color: rowMouse.pressed && pressActive
                               ? "#3A3A3A" : "#23252A"
                        border.color: root.clientBssid !== ""
                                      && ("" + bssid).toLowerCase()
                                         === root.clientBssid.toLowerCase()
                                      ? "#4CAF50" : "#2E3138"
                        border.width: 1

                        property bool pressActive: false

                        QText {
                            x: 18
                            y: 8
                            width: 420
                            text: ssid
                            font.pixelSize: ConstantModel.FONT_SIZE_21
                            elide: Text.ElideRight
                            color: HomeThemeHelper.normalTextColor
                        }
                        QText {
                            x: 18
                            y: 34
                            width: 520
                            text: security + "   \u00b7   " + signal
                                  + " dBm   \u00b7   " + root.signalPct(signal) + "%"
                                  + (freq !== undefined && freq !== ""
                                     ? "   \u00b7   " + freq + " MHz" : "")
                                  + (bssid !== undefined && bssid !== ""
                                     ? "   \u00b7   \u2026" + ("" + bssid).slice(-5) : "")
                            font.pixelSize: ConstantModel.FONT_SIZE_18
                            elide: Text.ElideRight
                            color: "#9A9A9A"
                        }

                        // strength bar
                        Rectangle {
                            x: 560
                            y: 26
                            width: 300
                            height: 10
                            radius: 5
                            color: "#15171B"
                            Rectangle {
                                width: parent.width * root.signalPct(signal) / 100
                                height: parent.height
                                radius: 5
                                color: signal >= -67 ? "#4CAF50"
                                     : signal >= -75 ? "#FFB300" : "#EF5350"
                            }
                        }

                        QText {
                            x: 890
                            y: 20
                            width: 200
                            horizontalAlignment: Text.AlignRight
                            text: (root.clientBssid !== ""
                                   && ("" + bssid).toLowerCase()
                                      === root.clientBssid.toLowerCase())
                                  ? "ligado"
                                  : (root.scanning ? "" : "Ligar  \u203a")
                            font.pixelSize: ConstantModel.FONT_SIZE_18
                            color: (root.clientBssid !== ""
                                    && ("" + bssid).toLowerCase()
                                       === root.clientBssid.toLowerCase())
                                   ? "#4CAF50" : "#CFCFD4"
                        }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            onPressed: parent.pressActive = true
                            onPositionChanged: if (!containsMouse) parent.pressActive = false
                            onReleased: {
                                if (parent.pressActive) {
                                    QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                                    root.openJoin(ssid, security)
                                }
                                parent.pressActive = false
                            }
                        }
                    }
                }
            }
        }

        // =================================================================
        // Ping tab
        // =================================================================
        Item {
            visible: root.currentTab === 2

            Row {
                x: 0
                y: 166
                spacing: 8

                Repeater {
                    model: root.pingTargets
                    delegate: Rectangle {
                        width: 218
                        height: 68
                        radius: 12
                        color: "#23252A"
                        border.color: root.pingStateOk(modelData)
                                      ? "#4CAF50" : "#2E3138"
                        border.width: 1

                        QText {
                            x: 14
                            y: 8
                            width: parent.width - 28
                            text: modelData
                            font.pixelSize: ConstantModel.FONT_SIZE_21
                            elide: Text.ElideRight
                            color: HomeThemeHelper.normalTextColor
                        }
                        QText {
                            x: 14
                            y: 38
                            width: parent.width - 28
                            text: root.pingStateText(modelData)
                            font.pixelSize: ConstantModel.FONT_SIZE_18
                            elide: Text.ElideRight
                            color: root.pingStateOk(modelData) ? "#4CAF50" : "#9A9A9A"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                                root.pingHost(modelData)
                            }
                        }
                    }
                }
            }

            WifiButton {
                x: 1040
                y: 166
                width: 140
                height: 68
                label: "Ping all"
                buttonEnabled: root.serviceOk && !root.pingBusy
                onClicked: root.pingAll()
            }

            Rectangle {
                x: 0
                y: 250
                width: 1180
                height: 380
                radius: 14
                color: "#141518"
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                QText {
                    x: 20
                    y: 12
                    text: "Resultado"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 20
                    y: 42
                    width: parent.width - 40
                    height: parent.height - 56
                    text: root.pingResult
                    font.pixelSize: 17
                    wrapMode: Text.WordWrap
                    clip: true
                    color: "#D8D8DC"
                }
            }
        }

        // =================================================================
        // SSH tab
        // =================================================================
        Item {
            visible: root.currentTab === 3

            Rectangle {
                x: 0
                y: 166
                width: 1180
                height: 160
                radius: 14
                color: ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                QText {
                    x: 28
                    y: 14
                    text: "Servidor SSH (dropbear)"
                    font.pixelSize: ConstantModel.FONT_SIZE_21
                    color: "#9A9A9A"
                }
                QText {
                    x: 28
                    y: 44
                    text: root.sshActive ? "On" : "Off"
                    font.pixelSize: ConstantModel.FONT_SIZE_30
                    textBold: true
                    color: root.sshActive ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }
                QText {
                    x: 28
                    y: 88
                    text: root.sshEnabled
                          ? "porta " + root.sshPort
                            + (root.sshPortFallback ? " (fallback)" : "")
                          : "desativado"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#9A9A9A"
                }
                QText {
                    x: 28
                    y: 120
                    width: 700
                    text: root.sshCommand
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    textBold: true
                    elide: Text.ElideRight
                    color: root.sshActive ? "#4CAF50" : HomeThemeHelper.normalTextColor
                }

                WifiSwitch {
                    anchors.right: parent.right
                    anchors.rightMargin: 28
                    y: 30
                    checked: root.sshEnabled
                    switchEnabled: root.serviceOk
                    onToggled: root.post("/ssh?enabled=" + (root.sshEnabled ? "0" : "1"))
                }
            }

            Rectangle {
                x: 0
                y: 342
                width: 1180
                height: 100
                radius: 14
                color: ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1

                QText {
                    x: 28
                    y: 14
                    text: "user car   \u00b7   password inicial electric   \u00b7   muda-a"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: "#FFB300"
                }
                QText {
                    x: 28
                    y: 46
                    width: 700
                    text: root.debugConsole
                          ? "consola segura do vendor DESATIVADA"
                          : "consola do vendor pode restringir o acesso"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    elide: Text.ElideRight
                    color: root.debugConsole ? "#4CAF50" : "#9A9A9A"
                }
                WifiButton {
                    anchors.right: parent.right
                    anchors.rightMargin: 28
                    y: 26
                    width: 150
                    label: "Chaves USB"
                    buttonEnabled: root.serviceOk
                    onClicked: root.post("/ssh/import")
                }
            }
        }

        // =================================================================
        // Log tab (full width, larger)
        // =================================================================
        Item {
            visible: root.currentTab === 4

            Row {
                x: 0
                y: 166
                spacing: 8

                Repeater {
                    model: [["Daemon", "daemon"], ["WPA", "wpa"], ["SSH", "ssh"]]
                    delegate: Rectangle {
                        width: 120
                        height: 44
                        radius: 22
                        color: root.consoleSource === modelData[1]
                               ? "#3A3A3A" : ConstantModel.GENERAL_COLOR_BUTTON_GREY
                        border.color: root.consoleSource === modelData[1]
                                      ? "#8A8A8A" : ConstantModel.GENERAL_COLOR_FOCUS_GREY
                        border.width: 1

                        QText {
                            anchors.centerIn: parent
                            text: modelData[0]
                            font.pixelSize: ConstantModel.FONT_SIZE_18
                            color: HomeThemeHelper.normalTextColor
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                                root.consoleSource = modelData[1]
                                root.refreshConsole()
                            }
                        }
                    }
                }
            }

            Rectangle {
                x: 0
                y: 224
                width: 1180
                height: 406
                radius: 14
                color: "#0B0B0B"
                border.color: "#333333"
                border.width: 1

                ListView {
                    id: consoleView
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    model: consoleModel
                    delegate: QText {
                        width: consoleView.width
                        text: line
                        font.pixelSize: 14
                        color: "#8FD18F"
                        wrapMode: Text.WrapAnywhere
                    }
                    onCountChanged: positionViewAtEnd()
                    Component.onCompleted: positionViewAtEnd()
                }
            }
        }

        // =================================================================
        // Join dialog + on-screen keyboard
        // =================================================================
        Rectangle {
            visible: root.joinDialog
            x: 0
            y: 0
            width: 1180
            height: 630
            color: "#000000"
            opacity: 0.55
            z: 20

            MouseArea { anchors.fill: parent }
        }

        Rectangle {
            visible: root.joinDialog
            x: 180
            y: 35
            width: 820
            height: 560
            radius: 16
            color: "#1A1C21"
            border.color: "#4A4E58"
            border.width: 1
            z: 21

            QText {
                x: 28
                y: 16
                width: 600
                text: "Ligar a " + root.joinSsid
                font.pixelSize: ConstantModel.FONT_SIZE_24
                textBold: true
                elide: Text.ElideRight
                color: "#FFFFFF"
            }
            QText {
                x: 28
                y: 50
                text: root.joinSecurity
                      + (root.joinSecurity === "Open"
                         ? "   \u00b7   sem password" : "   \u00b7   password da rede")
                font.pixelSize: ConstantModel.FONT_SIZE_18
                color: "#9A9A9A"
            }

            Rectangle {
                x: 28
                y: 80
                width: 764
                height: 54
                radius: 10
                color: "#101114"
                border.color: pskField.activeFocus ? "#4CAF50" : "#3A3E47"
                border.width: 2

                TextInput {
                    id: pskField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    height: 34
                    font.pixelSize: 24
                    color: "#FFFFFF"
                    echoMode: (root.joinSecurity === "Open")
                              ? TextInput.Normal : TextInput.Password
                    selectByMouse: true
                    onAccepted: if (root.joinSecurity === "Open"
                                    || text.length >= 8)
                                    root.joinNetwork()
                }
            }

            QText {
                id: joinNote
                x: 28
                y: 176
                width: 764
                text: root.joinSecurity === "Open"
                      ? "Rede aberta: prime Ligar."
                      : "8 a 63 caracteres (WPA2)"
                font.pixelSize: ConstantModel.FONT_SIZE_18
                color: "#9A9A9A"
            }

            Rectangle {
                x: 28
                y: 140
                width: 170
                height: 32
                radius: 16
                color: root.joinIp === "192.168.1.228"
                       ? "#3A3A3A" : ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: root.joinIp === "192.168.1.228"
                              ? "#8A8A8A" : ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1
                QText {
                    anchors.centerIn: parent
                    text: "LAN 1.x"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: HomeThemeHelper.normalTextColor
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                        root.setJoinPreset("192.168.1.228", "192.168.1.1")
                    }
                }
            }
            Rectangle {
                x: 208
                y: 140
                width: 170
                height: 32
                radius: 16
                color: root.joinIp === "192.168.2.228"
                       ? "#3A3A3A" : ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: root.joinIp === "192.168.2.228"
                              ? "#8A8A8A" : ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1
                QText {
                    anchors.centerIn: parent
                    text: "IOT 2.x"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: HomeThemeHelper.normalTextColor
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                        root.setJoinPreset("192.168.2.228", "192.168.2.1")
                    }
                }
            }
            Rectangle {
                x: 388
                y: 140
                width: 110
                height: 32
                radius: 16
                color: root.joinIp === ""
                       ? "#3A3A3A" : ConstantModel.GENERAL_COLOR_BUTTON_GREY
                border.color: root.joinIp === ""
                              ? "#8A8A8A" : ConstantModel.GENERAL_COLOR_FOCUS_GREY
                border.width: 1
                QText {
                    anchors.centerIn: parent
                    text: "Atual"
                    font.pixelSize: ConstantModel.FONT_SIZE_18
                    color: HomeThemeHelper.normalTextColor
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        QML_Handler.qmlSendEvtKey(HMIEVENTS.EVT_HOME_SOUND_BEEP_PLAY)
                        root.setJoinPreset("", "")
                    }
                }
            }

            // keyboard
            Item {
                id: kbPanel
                x: 28
                y: 196
                width: 764
                height: 250

                property var rows: root.kbSym
                    ? [["!", "@", "#", "$", "%", "&", "*", "-", "_", "+"],
                       ["(", ")", ".", ",", "?", "/", "=", ":", ";", "~"],
                       ["abc", "SPACE", "BKSP"]]
                    : [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                       ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                       ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                       ["SHIFT", "z", "x", "c", "v", "b", "n", "m", "BKSP"],
                       ["SYM", ",", "SPACE", "."]]

                Column {
                    spacing: 8

                    Repeater {
                        model: kbPanel.rows
                        delegate: Row {
                            spacing: 8

                            Repeater {
                                model: modelData
                                delegate: Rectangle {
                                    width: (modelData === "SPACE") ? 300
                                         : (modelData === "SHIFT"
                                            || modelData === "BKSP"
                                            || modelData === "SYM"
                                            || modelData === "abc") ? 86 : 64
                                    height: 46
                                    radius: 8
                                    color: keyMouse.pressed && pressActive
                                           ? "#3E424B" : "#262A31"
                                    border.color: "#3A3E47"
                                    border.width: 1

                                    property bool pressActive: false

                                    QText {
                                        anchors.centerIn: parent
                                        text: {
                                            if (modelData === "BKSP") return "\u232b"
                                            if (modelData === "SHIFT")
                                                return "\u21e7"
                                            if (modelData === "SPACE") return "espaco"
                                            if (modelData === "SYM") return "?123"
                                            if (modelData === "abc") return "abc"
                                            return (!root.kbSym && root.kbShift)
                                                   ? modelData.toUpperCase() : modelData
                                        }
                                        font.pixelSize: ConstantModel.FONT_SIZE_18
                                        color: "#E8E8EA"
                                    }

                                    MouseArea {
                                        id: keyMouse
                                        anchors.fill: parent
                                        onPressed: parent.pressActive = true
                                        onPositionChanged: if (!containsMouse) parent.pressActive = false
                                        onReleased: {
                                            if (parent.pressActive) {
                                                root.kbKey(modelData)
                                                pskField.forceActiveFocus()
                                            }
                                            parent.pressActive = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            WifiButton {
                x: 28
                y: 490
                width: 180
                height: 48
                label: "Cancelar"
                onClicked: root.joinDialog = false
            }
            WifiButton {
                x: 612
                y: 490
                width: 180
                height: 48
                label: "Ligar"
                buttonEnabled: root.joinSecurity === "Open"
                               || pskField.text.length >= 8
                onClicked: root.joinNetwork()
            }
        }
    }

    ListModel { id: scanModel }
    ListModel { id: consoleModel }
}
