pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Networking
import "Singletons"

// Hotspot subtab of Connections: brings the persistent `RyokuHotspot`
// NetworkManager profile up/down through nmcli, with an editable SSID + WPA2
// password. state and credentials read straight from NM on entry, so the page
// always reflects what the system thinks.
//
// wire protocol (nmcli command shapes, positional args for the secret-bearing
// apply, WPA2 minimum) is identical to the pill's LinkWifi hotspot block.
// only the layout was recast for the full hub content area + warm Theme.
Item {
    id: page

    // --- Networking lookup (wifi interface name only) ----------------------
    readonly property var devices: (typeof Networking !== "undefined" && Networking && Networking.devices) ? Networking.devices.values : []
    readonly property var wifiDev: page.devices.find(function(d) { return d && d.type === DeviceType.Wifi }) || null

    // --- hotspot state -----------------------------------------------------
    // hsCon = the NM profile name we own; everything else is read from that
    // profile or driven into it by applyHotspot / stopHotspot.
    readonly property string hsCon: "RyokuHotspot"
    readonly property string hsIface: page.wifiDev ? (page.wifiDev.name || "wlan0") : "wlan0"
    property string hsName: "Ryoku"
    property string hsPw: ""
    property bool hsActive: false
    property bool hsBusy: false
    property string hsEdit: ""
    property string hsDraft: ""

    // bring the shared AP up with the current name + password. creates the
    // persistent connection on first use, modifies it after. name + password
    // ride in as positional args ($1/$2/$3), NEVER spliced into the shell
    // string -- an odd character can't break or inject the command.
    function applyHotspot() {
        if (page.hsBusy || page.hsPw.length < 8)
            return;
        page.hsBusy = true;
        hsApplyProc.command = ["sh", "-c",
            'c="' + page.hsCon + '"; '
            + 'if nmcli -t connection show "$c" >/dev/null 2>&1; then '
            +   'nmcli connection modify "$c" 802-11-wireless.ssid "$1" 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2"; '
            + 'else '
            +   'nmcli connection add type wifi ifname "$3" con-name "$c" autoconnect no 802-11-wireless.ssid "$1" 802-11-wireless.mode ap 802-11-wireless-security.key-mgmt wpa-psk 802-11-wireless-security.psk "$2" ipv4.method shared; '
            + 'fi; '
            + 'nmcli connection up "$c"',
            "sh", page.hsName, page.hsPw, page.hsIface];
        hsApplyProc.running = true;
    }

    function stopHotspot() {
        if (page.hsBusy)
            return;
        page.hsBusy = true;
        hsDownProc.running = true;
    }

    function refreshHotspot() {
        hsStateProc.running = true;
        hsReadProc.running = true;
    }

    // commit an inline name or password edit. password shorter than the WPA2
    // 8-char minimum is dropped silently. a live hotspot is re-applied so the
    // change takes effect at once.
    function commitHotspotEdit() {
        if (page.hsEdit === "name") {
            if (page.hsDraft.length)
                page.hsName = page.hsDraft;
        } else if (page.hsEdit === "pw") {
            if (page.hsDraft.length >= 8)
                page.hsPw = page.hsDraft;
        }
        page.hsEdit = "";
        page.hsDraft = "";
        if (page.hsActive)
            page.applyHotspot();
    }

    // 8-char WPA2 password from an unambiguous alphabet (no 0/O/1/l/I). used
    // when the hotspot is switched on before a password has been set.
    function generatePw() {
        var cs = "abcdefghijkmnpqrstuvwxyz23456789";
        var s = "";
        for (var i = 0; i < 8; i++)
            s += cs.charAt(Math.floor(Math.random() * cs.length));
        return s;
    }

    Component.onCompleted: page.refreshHotspot()

    // --- nmcli processes ---------------------------------------------------

    Process {
        id: hsApplyProc
        onExited: {
            page.hsBusy = false;
            page.refreshHotspot();
        }
    }

    Process {
        id: hsDownProc
        command: ["nmcli", "connection", "down", page.hsCon]
        onExited: {
            page.hsBusy = false;
            page.refreshHotspot();
        }
    }

    Process {
        id: hsStateProc
        command: ["sh", "-c", "nmcli -t -f NAME connection show --active | grep -qxF -- \"$1\" && echo on || echo off", "sh", page.hsCon]
        stdout: StdioCollector {
            onStreamFinished: page.hsActive = this.text.trim() === "on"
        }
    }

    Process {
        id: hsReadProc
        command: ["nmcli", "-t", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "connection", "show", page.hsCon]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length >= 1 && lines[0].length)
                    page.hsName = lines[0];
                if (lines.length >= 2 && lines[1].length)
                    page.hsPw = lines[1];
            }
        }
    }

    // --- header explainer --------------------------------------------------
    Column {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6

        Text {
            text: "Share this machine's connection as a Wi-Fi hotspot. NetworkManager owns the profile (named " + page.hsCon + "); changes to the network name or password apply at once when the hotspot is live."
            color: Theme.faint
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
            width: Math.min(parent.width, 640)
            wrapMode: Text.WordWrap
        }
    }

    // --- form column -------------------------------------------------------
    Column {
        id: form
        anchors.left: parent.left
        anchors.top: head.bottom
        anchors.topMargin: 28
        width: Math.min(parent.width, 600)
        spacing: 30

        // -- big toggle card: icon, label, live status, switch -------------
        Rectangle {
            width: parent.width
            height: 76
            radius: Theme.radius
            color: page.hsActive ? Theme.frameBg : Theme.surfaceLo
            border.width: 1
            border.color: page.hsActive ? Theme.ember : Theme.line
            Behavior on color { ColorAnimation { duration: Theme.quick } }
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Icon {
                id: hsGlyph
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                name: "wifi"
                size: 22
                weight: 1.8
                tint: page.hsActive ? Theme.ember : Theme.subtle
                Behavior on tint { ColorAnimation { duration: Theme.quick } }
            }

            Column {
                anchors.left: hsGlyph.right
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    text: "Hotspot"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    text: page.hsBusy ? "Working\u2026"
                        : (page.hsActive ? ("Active on " + page.hsIface) : "Off")
                    color: page.hsActive ? Theme.ember : Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                }
            }

            ToggleRow {
                id: hsSwitch
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                width: 64
                checked: page.hsActive
                enabled: !page.hsBusy
                onToggled: {
                    if (page.hsActive) {
                        page.stopHotspot();
                    } else {
                        if (page.hsPw.length < 8)
                            page.hsPw = page.generatePw();
                        page.applyHotspot();
                    }
                }
            }
        }

        // -- credentials ---------------------------------------------------
        SettingSection {
            width: parent.width
            title: "DETAILS"

            // editable label/value row. tap the value to drop an inline
            // TextField in its place; Enter commits via commitHotspotEdit, Esc
            // (loss of focus) cancels.
            component CredRow: Item {
                id: cr
                property string field: ""
                property string label: ""
                property string value: ""
                property string placeholder: ""
                property bool secret: false
                property bool reveal: false
                readonly property bool editing: page.hsEdit === cr.field
                readonly property bool tooShort: cr.field === "pw" && cr.editing && page.hsDraft.length > 0 && page.hsDraft.length < 8

                width: parent ? parent.width : 0
                height: 44

                // hairline background, lights up while editing.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: cr.editing ? Theme.surfaceLo : "transparent"
                    border.width: 1
                    border.color: cr.editing ? Theme.ember : Theme.lineSoft
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                }

                Text {
                    id: crLabel
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: cr.label
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                // read-only value + tap-to-edit affordance.
                Item {
                    visible: !cr.editing
                    anchors.left: crLabel.right
                    anchors.right: (cr.secret && cr.value.length > 0) ? revealBtn.left : parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height

                    Text {
                        id: crValue
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool isSecretHidden: cr.secret && !cr.reveal && cr.value.length > 0
                        text: cr.value.length === 0
                            ? (cr.placeholder.length ? cr.placeholder : "tap to set")
                            : (isSecretHidden ? "\u2022".repeat(Math.max(cr.value.length, 8)) : cr.value)
                        color: cr.value.length === 0
                            ? Theme.faint
                            : (cr.secret ? Theme.ember : Theme.bright)
                        font.family: cr.secret ? Theme.mono : Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        font.features: ({ "tnum": 1 })
                        elide: Text.ElideLeft
                        maximumLineCount: 1
                    }

                    HoverHandler {
                        id: valueHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: {
                            page.hsDraft = cr.value;
                            page.hsEdit = cr.field;
                            Qt.callLater(crField.forceActiveFocus);
                        }
                    }
                }

                // "Show" / "Hide" pill, password row only.
                Rectangle {
                    id: revealBtn
                    visible: cr.secret && !cr.editing && cr.value.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: revealText.implicitWidth + 18
                    height: 24
                    radius: Theme.radius
                    color: revealHov.hovered ? Theme.surface : "transparent"
                    border.width: 1
                    border.color: revealHov.hovered ? Theme.ember : Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                    Text {
                        id: revealText
                        anchors.centerIn: parent
                        text: cr.reveal ? "Hide" : "Show"
                        color: revealHov.hovered ? Theme.bright : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    HoverHandler { id: revealHov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: cr.reveal = !cr.reveal }
                }

                // inline editor.
                TextField {
                    id: crField
                    visible: cr.editing
                    anchors.left: crLabel.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: TextInput.AlignRight
                    background: null
                    padding: 0
                    color: Theme.bright
                    font.family: cr.secret ? Theme.mono : Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    placeholderText: cr.field === "pw" ? "8+ characters" : "Network name"
                    placeholderTextColor: Theme.faint
                    selectByMouse: true
                    selectionColor: Theme.ember
                    selectedTextColor: Theme.onAccent
                    text: cr.editing ? page.hsDraft : ""
                    onTextEdited: page.hsDraft = text
                    onAccepted: page.commitHotspotEdit()
                    onActiveFocusChanged: {
                        if (!activeFocus && cr.editing)
                            page.commitHotspotEdit();
                    }
                    Keys.onEscapePressed: (event) => {
                        page.hsEdit = "";
                        page.hsDraft = "";
                        event.accepted = true;
                    }
                }

                // inline validation: password row only, only while typing too
                // few characters. real rejection happens in commitHotspotEdit;
                // this is just the heads-up.
                Text {
                    visible: cr.tooShort
                    anchors.left: crLabel.right
                    anchors.leftMargin: 12
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: "WPA2 needs at least 8 characters"
                    color: Theme.bad
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Medium
                }
            }

            CredRow {
                field: "name"
                label: "Network name"
                value: page.hsName
                placeholder: "Ryoku"
            }

            CredRow {
                field: "pw"
                label: "Password"
                value: page.hsPw
                placeholder: "Tap to set"
                secret: true
            }
        }
    }
}
