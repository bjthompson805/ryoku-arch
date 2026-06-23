pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Networking
import "Singletons"

// Wi-Fi subtab of the Connections section: master on/off, a rescan affordance
// that spins for ~10 s, and the live network list sorted by signal strength.
// Security and known-profile ground truth come from nmcli (the Quickshell
// service does not expose it); clicking a secured unknown network expands an
// inline password row that connects via `nmcli --ask dev wifi connect`, with
// the secret piped through stdin so it never appears in /proc/<pid>/cmdline.
// The page is treated as always-active while it lives, the parent Loader
// recreates it on tab change, so the device scanner runs while shown.
Item {
    id: page

    // ---- state ------------------------------------------------------------

    // The page exists only while it is the visible subtab (the Loader swaps
    // sourceComponent on tab change), so "active" stays true throughout life.
    property bool active: true

    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null
    readonly property bool wifiOn: (typeof Networking !== "undefined" && Networking) ? Networking.wifiEnabled : false
    readonly property var nets: (wifiDev && wifiDev.networks) ? wifiDev.networks.values : []
    readonly property var netsSorted: nets
        .slice()
        .filter(function(n) { return n && n.name && n.name.length > 0; })
        .sort(function(a, b) {
            return ((b ? b.signalStrength : 0) || 0) - ((a ? a.signalStrength : 0) || 0);
        })

    property var securityMap: ({})
    property var knownProfiles: ({})
    property string expandedSsid: ""
    property bool connecting: false
    property bool connectFailed: false
    property bool scanning: false

    // The Repeater model is a fresh array on every NM rescan, which tears down
    // and recreates the delegate mid-typing. The draft lives on the page so the
    // password field restores itself from it when rebuilt.
    property string pwDraft: ""
    property string pendingPw: ""
    property string attemptSsid: ""
    property bool attemptWasKnown: false

    // Width cap for the readable content column on this wide hub page.
    readonly property real colMax: 640

    function isSecured(ssid) {
        var sec = securityMap[ssid];
        return sec !== undefined && sec !== "" && sec !== "--";
    }

    function refresh() {
        secProc.running = true;
        profProc.running = true;
    }

    // Splits one `nmcli -t` line at its last unescaped colon and unescapes the
    // leading field. Returns null for lines without a field separator.
    function splitTerse(line) {
        for (var k = line.length - 1; k >= 0; k--) {
            if (line[k] === ":" && (k === 0 || line[k - 1] !== "\\"))
                return { head: line.slice(0, k).replace(/\\:/g, ":"), tail: line.slice(k + 1) };
        }
        return null;
    }

    // Click dispatch for a network row: disconnect when connected, connect
    // known or open networks directly, otherwise expand the inline password
    // row under that network.
    function activateNetwork(net) {
        if (!net)
            return;
        var ssid = net.name || "";
        if (net.connected) {
            if (typeof net.disconnect === "function")
                net.disconnect();
            return;
        }
        var secKnown = securityMap[ssid] !== undefined;
        if (knownProfiles[ssid] === true || (secKnown && !isSecured(ssid))) {
            expandedSsid = "";
            if (typeof net.connect === "function")
                net.connect();
            refresh();
            return;
        }
        connectFailed = false;
        pwDraft = "";
        expandedSsid = ssid;
    }

    // Connects via `nmcli --ask`, feeding the password through stdin so the
    // secret never appears in the process command line (`/proc/<pid>/cmdline`
    // is world-readable for the whole connection attempt).
    function connectWithPassword(ssid, pw) {
        if (connProc.running || !pw.length)
            return;
        connecting = true;
        connectFailed = false;
        attemptSsid = ssid;
        attemptWasKnown = knownProfiles[ssid] === true;
        pendingPw = pw;
        connProc.command = ["nmcli", "--ask", "dev", "wifi", "connect", ssid];
        connProc.running = true;
    }

    // Reload pulse: forces a fresh nmcli rescan and spins the control for up
    // to 10 s. The device scanner runs while the page is visible, so the list
    // never empties; this refreshes results and drives the spinner.
    function startScan() {
        if (!wifiOn)
            return;
        scanning = true;
        rescanProc.running = true;
        scanTimer.restart();
    }

    function stopScan() {
        scanning = false;
        scanTimer.stop();
    }

    Component.onCompleted: refresh()

    onWifiOnChanged: if (!wifiOn) stopScan()

    Binding {
        target: page.wifiDev
        property: "scannerEnabled"
        value: page.active && page.wifiOn
        when: page.wifiDev !== null
    }

    Timer {
        id: scanTimer
        interval: 10000
        onTriggered: page.stopScan()
    }

    Process {
        id: rescanProc
        command: ["nmcli", "dev", "wifi", "rescan"]
    }

    Process {
        id: secProc
        command: ["nmcli", "-t", "-f", "SSID,SECURITY", "dev", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var map = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (!lines[i].length)
                        continue;
                    var parts = page.splitTerse(lines[i]);
                    if (parts && parts.head.length)
                        map[parts.head] = parts.tail;
                }
                page.securityMap = map;
            }
        }
    }

    Process {
        id: profProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                var set = {};
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var parts = page.splitTerse(lines[i]);
                    if (parts && parts.head.length && parts.tail === "802-11-wireless")
                        set[parts.head] = true;
                }
                page.knownProfiles = set;
            }
        }
    }

    Process {
        id: connProc
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onStarted: {
            write(page.pendingPw + "\n");
            page.pendingPw = "";
        }
        onExited: function(exitCode) {
            page.connecting = false;
            if (exitCode === 0) {
                page.expandedSsid = "";
                page.pwDraft = "";
                page.connectFailed = false;
                page.refresh();
            } else {
                page.connectFailed = true;
                if (!page.attemptWasKnown && page.attemptSsid.length) {
                    cleanupProc.command = ["nmcli", "connection", "delete", "id", page.attemptSsid];
                    cleanupProc.running = true;
                }
            }
        }
    }

    // A failed `nmcli dev wifi connect` still leaves a connection profile
    // named after the SSID behind; without deleting it the network would be
    // treated as known on the next click and silently fail forever.
    Process {
        id: cleanupProc
        onExited: page.refresh()
    }

    onNetsChanged: if (active) secRefresh.restart()

    Timer {
        id: secRefresh
        interval: 1200
        onTriggered: if (page.active) secProc.running = true
    }

    // ---- layout -----------------------------------------------------------

    Item {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Math.min(parent.width, page.colMax)

        // Header row: "WI-FI" label, hairline, Scan/Scanning… button.
        Item {
            id: bar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 40

            Text {
                id: secLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "WI-FI"
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2
            }

            Rectangle {
                anchors.left: secLabel.right
                anchors.leftMargin: 14
                anchors.right: scanBtn.visible ? scanBtn.left : parent.right
                anchors.rightMargin: scanBtn.visible ? 14 : 0
                anchors.verticalCenter: parent.verticalCenter
                height: 1
                color: Theme.lineSoft
            }

            HubButton {
                id: scanBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: page.wifiOn
                label: page.scanning ? "Scanning…" : "Scan"
                icon: "refresh"
                enabled: !page.scanning
                onClicked: page.startScan()
            }
        }

        // Master on/off, the same toggle the link surface offers, but as a
        // labelled row so it reads as a setting on this full-page surface.
        ToggleRow {
            id: wifiToggle
            anchors.top: bar.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            label: "Wi-Fi"
            checked: page.wifiOn
            onToggled: (v) => {
                if (typeof Networking !== "undefined" && Networking)
                    Networking.wifiEnabled = v;
            }
        }

        Rectangle {
            id: divider
            anchors.top: wifiToggle.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.lineSoft
        }

        // Empty states, both share the divider's geometry so we never
        // double-stack a message and a (possibly empty) flickable.
        Text {
            anchors.top: divider.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !page.wifiOn
            text: "Wi-Fi is off."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Row {
            anchors.top: divider.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            visible: page.wifiOn && page.netsSorted.length === 0

            Spinner {
                anchors.verticalCenter: parent.verticalCenter
                size: 14
                tint: Theme.faint
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Searching networks…"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        // Live network list.
        Flickable {
            id: netFlick
            anchors.top: divider.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: page.wifiOn && page.netsSorted.length > 0
            contentHeight: netCol.implicitHeight + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                id: sb
                policy: ScrollBar.AsNeeded
                width: 7
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: Theme.line
                    opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                }
            }

            Column {
                id: netCol
                width: netFlick.width
                topPadding: 2
                spacing: 4

                Repeater {
                    model: page.netsSorted

                    delegate: Column {
                        id: netItem
                        required property var modelData

                        readonly property string ssid: (modelData && modelData.name) ? modelData.name : ""
                        readonly property bool isActive: modelData ? modelData.connected === true : false
                        readonly property bool secured: page.isSecured(ssid)
                        readonly property bool known: page.knownProfiles[ssid] === true
                        readonly property bool expanded: ssid.length > 0 && page.expandedSsid === ssid
                        readonly property int strength: modelData ? Math.round((modelData.signalStrength || 0)) : 0

                        width: netCol.width
                        spacing: 4

                        function syncPwField() {
                            pwField.text = page.pwDraft;
                            pwField.cursorPosition = pwField.text.length;
                            pwField.forceActiveFocus();
                        }

                        onExpandedChanged: if (expanded) Qt.callLater(syncPwField)
                        Component.onCompleted: if (expanded) Qt.callLater(syncPwField)

                        // The network row itself.
                        Rectangle {
                            id: rowBg
                            width: parent.width
                            height: 46
                            radius: 12
                            color: netItem.isActive
                                ? Theme.frameBg
                                : (rowHover.hovered ? Theme.surfaceLo : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.quick } }

                            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.activateNetwork(netItem.modelData) }

                            // Signal bars (4 ascending rectangles), bottom-anchored.
                            Item {
                                id: bars
                                width: 21
                                height: 16
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter

                                readonly property int filled: Math.max(0, Math.min(4, Math.ceil(netItem.strength / 25)))
                                readonly property color litColor: netItem.isActive ? Theme.brand : Theme.cream
                                readonly property color dimColor: Theme.faint

                                Rectangle {
                                    x: 0; width: 3; height: 4
                                    y: bars.height - height
                                    radius: 1.5
                                    color: bars.filled > 0 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 6; width: 3; height: 8
                                    y: bars.height - height
                                    radius: 1.5
                                    color: bars.filled > 1 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 12; width: 3; height: 12
                                    y: bars.height - height
                                    radius: 1.5
                                    color: bars.filled > 2 ? bars.litColor : bars.dimColor
                                }
                                Rectangle {
                                    x: 18; width: 3; height: 16
                                    y: bars.height - height
                                    radius: 1.5
                                    color: bars.filled > 3 ? bars.litColor : bars.dimColor
                                }
                            }

                            // SSID + status hint.
                            Column {
                                anchors.left: bars.right
                                anchors.leftMargin: 14
                                anchors.right: rowRight.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: netItem.ssid
                                    color: netItem.isActive ? Theme.brand : Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: netItem.isActive ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: netItem.isActive
                                        ? "Connected"
                                        : (netItem.known
                                            ? (netItem.secured ? "Saved · Secured" : "Saved · Open")
                                            : (netItem.secured ? "Secured" : "Open"))
                                    color: netItem.isActive ? Theme.ember : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            // Right side: lock + signal percentage.
                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: netItem.secured
                                    name: "lock"
                                    size: 14
                                    weight: 1.7
                                    tint: netItem.isActive ? Theme.ember : Theme.dim
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: netItem.strength + "%"
                                    color: Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        // Inline password row, only secured, unknown networks.
                        Item {
                            visible: netItem.expanded
                            width: parent.width
                            height: 44

                            Rectangle {
                                id: pwBg
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: pwRight.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                height: 32
                                radius: 10
                                color: Theme.surfaceLo
                                border.width: 1
                                border.color: pwField.activeFocus ? Theme.ember : Theme.line
                                Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                                TextField {
                                    id: pwField
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    background: null
                                    padding: 0
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.bright
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    echoMode: TextInput.Password
                                    placeholderText: "Password"
                                    placeholderTextColor: Theme.faint
                                    selectByMouse: true
                                    selectionColor: Theme.ember
                                    onTextEdited: page.pwDraft = text
                                    onAccepted: page.connectWithPassword(netItem.ssid, text)
                                }
                            }

                            Row {
                                id: pwRight
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                Spinner {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: page.connecting
                                    size: 14
                                    tint: Theme.ember
                                }

                                HubButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Connect"
                                    primary: true
                                    enabled: !page.connecting && pwField.text.length > 0
                                    onClicked: page.connectWithPassword(netItem.ssid, pwField.text)
                                }
                            }
                        }

                        Text {
                            visible: netItem.expanded && page.connectFailed
                            text: "Connection failed."
                            color: Theme.bad
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            leftPadding: 16
                        }
                    }
                }
            }
        }
    }
}
