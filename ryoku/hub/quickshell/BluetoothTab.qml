pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Bluetooth
import "Singletons"

// Bluetooth subtab of Connections: adapter toggle, scan with 25 s auto-stop,
// live device list. known devices use Quickshell's connect/disconnect; unpaired
// ones run bluetoothctl pair-trust-connect with an inline ember while running
// and a transient failure line. ported from the shell's narrow LinkBt drill-in
// to a full-width hub page on the warm Theme palette.
Item {
    id: page

    readonly property var adapter: (typeof Bluetooth !== "undefined" && Bluetooth) ? Bluetooth.defaultAdapter : null
    readonly property var devices: (typeof Bluetooth !== "undefined" && Bluetooth && Bluetooth.devices) ? Bluetooth.devices.values : []
    readonly property bool adapterOn: adapter ? adapter.enabled === true : false
    readonly property bool discovering: adapter ? adapter.discovering === true : false
    readonly property int connectedCount: {
        var n = 0;
        for (var i = 0; i < devices.length; i++)
            if (devices[i] && devices[i].connected)
                n++;
        return n;
    }

    // BlueZ hands the cache out in arbitrary order. sort connected first, then
    // paired, then named devices, nameless MACs last. a scan shouldn't churn the
    // useful rows around.
    readonly property var devicesSorted: devices.slice().sort(function(a, b) {
        function rank(d) {
            if (!d) return 3;
            if (d.connected) return 0;
            if (d.paired) return 1;
            return (d.name && d.name.length) ? 2 : 3;
        }
        var r = rank(a) - rank(b);
        if (r !== 0) return r;
        return String((a && a.name) || "").localeCompare(String((b && b.name) || ""));
    })

    property string pairingAddress: ""
    property string failedAddress: ""

    function metaFor(d) {
        if (!d) return "";
        var parts = [];
        if (d.connected) parts.push("connected");
        else if (d.paired) parts.push("paired");
        if (d.state !== undefined && typeof BluetoothDeviceState !== "undefined") {
            var st = BluetoothDeviceState.toString(d.state);
            if (st && st.length > 0 && parts.indexOf(st.toLowerCase()) === -1)
                parts.push(st.toLowerCase());
        }
        return parts.join(" · ");
    }

    function batteryLevel(d) {
        if (!d || d.battery === undefined || d.battery === null) return -1;
        var b = d.battery;
        if (b <= 0) return -1;
        if (b <= 1) b = b * 100;
        return Math.round(b);
    }

    // row click: disconnect if connected, connect if paired, else run the
    // bluetoothctl pair-trust-connect flow.
    function activateDevice(d) {
        if (!d)
            return;
        if (d.connected) {
            if (typeof d.disconnect === "function")
                d.disconnect();
            return;
        }
        if (d.paired) {
            if (typeof d.connect === "function")
                d.connect();
            return;
        }
        pairDevice(d);
    }

    function pairDevice(d) {
        if (!d || !d.address || pairProc.running)
            return;
        page.pairingAddress = d.address;
        page.failedAddress = "";
        pairProc.command = ["sh", "-c",
            'timeout 30 bluetoothctl pair "$1" && bluetoothctl trust "$1" && timeout 30 bluetoothctl connect "$1"',
            "sh", d.address];
        pairProc.running = true;
    }

    // leaving the subtab (or closing the hub) mid-scan stops discovery so BlueZ
    // isn't left chewing the radio in the background.
    Component.onDestruction: {
        scanTimer.stop();
        if (page.adapter && page.adapter.discovering)
            page.adapter.discovering = false;
    }

    Timer {
        id: scanTimer
        interval: 25000
        repeat: false
        onTriggered: if (page.adapter) page.adapter.discovering = false
    }

    Timer {
        id: failTimer
        interval: 4000
        repeat: false
        onTriggered: page.failedAddress = ""
    }

    Process {
        id: pairProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(exitCode) {
            var addr = page.pairingAddress;
            page.pairingAddress = "";
            if (exitCode !== 0) {
                page.failedAddress = addr;
                failTimer.restart();
            }
        }
    }

    // ---------- header band ------------------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 48

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            // BT rune.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    preferredRendererType: Shape.CurveRenderer
                    antialiasing: true
                    ShapePath {
                        strokeColor: page.adapterOn ? Theme.ember : Theme.dim
                        strokeWidth: 1.8
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M6.5 6.5l11 11L12 23V1l5.5 5.5L6.5 17.5" }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BLUETOOTH"
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: 2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.adapterOn
                text: {
                    var known = page.devices.length;
                    if (known === 0)
                        return page.discovering ? "Scanning…" : "No devices yet";
                    if (page.connectedCount > 0)
                        return page.connectedCount + " connected · " + known + " known";
                    return known + " known";
                }
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            // scan toggle (only visible while adapter is on, mirroring the
            // shell). tap flips adapter.discovering and (re)arms the 25 s timer
            // so a forgotten scan doesn't keep the radio busy forever.
            Item {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.adapterOn
                width: scanPill.width
                height: scanPill.height

                Rectangle {
                    id: scanPill
                    radius: height / 2
                    height: 30
                    width: scanLbl.implicitWidth + 28
                    color: page.discovering ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.14)
                        : (scanHov.hovered ? Theme.keyTop : "transparent")
                    border.width: 1
                    border.color: page.discovering ? Theme.ember
                        : (scanHov.hovered ? Theme.ember : Theme.line)
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                    Text {
                        id: scanLbl
                        anchors.centerIn: parent
                        text: page.discovering ? "Scanning…" : "Scan"
                        color: page.discovering ? Theme.ember
                            : (scanHov.hovered ? Theme.bright : Theme.cream)
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: scanHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            if (!page.adapter)
                                return;
                            page.adapter.discovering = !page.adapter.discovering;
                            if (page.adapter.discovering)
                                scanTimer.restart();
                            else
                                scanTimer.stop();
                        }
                    }
                }
            }

            // one primary toggle for the whole adapter.
            ToggleRow {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                label: ""
                checked: page.adapterOn
                onToggled: (v) => { if (page.adapter) page.adapter.enabled = v; }
            }
        }
    }

    Rectangle {
        id: rule
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.lineSoft
    }

    // ---------- body -------------------------------------------------------
    Item {
        id: body
        anchors.top: rule.bottom
        anchors.topMargin: 22
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // off / empty placeholder, centred so the page never looks broken.
        Column {
            anchors.centerIn: parent
            visible: !page.adapterOn || page.devices.length === 0
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: !page.adapterOn
                    ? "Bluetooth is off."
                    : (page.discovering ? "Scanning…" : "No devices yet.")
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !page.adapterOn || (!page.discovering && page.devices.length === 0)
                text: !page.adapterOn
                    ? "Turn the adapter on to see nearby and paired devices."
                    : "Hit Scan to discover nearby devices."
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        Flickable {
            id: devFlick
            visible: page.adapterOn && page.devices.length > 0
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - 48, 640)
            contentWidth: width
            contentHeight: devCol.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                id: sb
                policy: ScrollBar.AsNeeded
                width: 7
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: Theme.radius
                    color: Theme.line
                    opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                    Behavior on opacity { NumberAnimation { duration: Theme.quick } }
                }
            }

            Column {
                id: devCol
                width: devFlick.width
                spacing: 8

                Repeater {
                    model: page.devicesSorted

                    delegate: Column {
                        id: dev

                        required property var modelData
                        readonly property bool isConnected: modelData ? modelData.connected === true : false
                        readonly property bool isPaired: modelData ? modelData.paired === true : false
                        readonly property string addr: (modelData && modelData.address) ? modelData.address : ""
                        readonly property bool pairing: addr.length > 0 && page.pairingAddress === addr
                        readonly property bool failed: addr.length > 0 && page.failedAddress === addr
                        readonly property int battery: page.batteryLevel(modelData)

                        width: parent.width
                        spacing: 4

                        Rectangle {
                            id: tile
                            width: parent.width
                            height: 64
                            radius: Theme.radius
                            color: dev.isConnected ? Theme.frameBg
                                : (rowHov.hovered ? Theme.keyTop : Theme.surfaceLo)
                            border.width: 1
                            border.color: dev.isConnected ? Theme.ember
                                : (rowHov.hovered ? Theme.line : Theme.lineSoft)
                            Behavior on color { ColorAnimation { duration: Theme.quick } }
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            HoverHandler { id: rowHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.activateDevice(dev.modelData) }

                            // BT rune tile.
                            Rectangle {
                                id: iconTile
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: Theme.radius
                                color: dev.isConnected ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.16) : Theme.keyTop
                                border.width: 1
                                border.color: dev.isConnected ? Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.40) : Theme.line

                                Shape {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    preferredRendererType: Shape.CurveRenderer
                                    antialiasing: true
                                    ShapePath {
                                        strokeColor: dev.isConnected ? Theme.ember : Theme.subtle
                                        strokeWidth: 1.7
                                        fillColor: "transparent"
                                        capStyle: ShapePath.RoundCap
                                        joinStyle: ShapePath.RoundJoin
                                        PathSvg { path: "M6.5 6.5l11 11L12 23V1l5.5 5.5L6.5 17.5" }
                                    }
                                }
                            }

                            Column {
                                anchors.left: iconTile.right
                                anchors.leftMargin: 14
                                anchors.right: rowRight.left
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: dev.modelData
                                        ? (dev.modelData.deviceName
                                            || dev.modelData.name
                                            || dev.addr
                                            || "Unknown")
                                        : "Unknown"
                                    color: dev.isConnected ? Theme.bright : Theme.cream
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: dev.isConnected ? Font.DemiBold : Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: dev.pairing ? "pairing…" : page.metaFor(dev.modelData)
                                    color: dev.pairing ? Theme.ember : Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: rowRight
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                // pairing pulse.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.pairing
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Theme.ember

                                    SequentialAnimation on opacity {
                                        running: dev.pairing
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.35; to: 1; duration: 600; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1; to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                                    }
                                }

                                // battery pill (connected + has a level).
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.isConnected && dev.battery >= 0
                                    radius: 999
                                    color: Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.32)
                                    height: 22
                                    width: battTxt.implicitWidth + 18

                                    Text {
                                        id: battTxt
                                        anchors.centerIn: parent
                                        text: Math.max(0, dev.battery) + "%"
                                        color: Theme.ember
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // pair pill (unpaired, not currently pairing).
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !dev.isPaired && !dev.pairing
                                    radius: 999
                                    color: Theme.keyTop
                                    border.width: 1
                                    border.color: rowHov.hovered ? Theme.subtle : Theme.line
                                    height: 22
                                    width: pairTxt.implicitWidth + 18

                                    Text {
                                        id: pairTxt
                                        anchors.centerIn: parent
                                        text: "Pair"
                                        color: rowHov.hovered ? Theme.bright : Theme.cream
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }

                                // disconnect hint.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dev.isConnected
                                    radius: 999
                                    color: rowHov.hovered ? Theme.keyTop : "transparent"
                                    border.width: 1
                                    border.color: rowHov.hovered ? Theme.ember
                                        : Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.30)
                                    height: 22
                                    width: discTxt.implicitWidth + 18
                                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                                    Text {
                                        id: discTxt
                                        anchors.centerIn: parent
                                        text: "Disconnect"
                                        color: Theme.ember
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        Text {
                            visible: dev.failed
                            width: parent.width
                            leftPadding: 66
                            text: "Pairing failed"
                            color: Theme.ember
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
