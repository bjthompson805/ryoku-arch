pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "Singletons"

/**
 * controls zone of the 力 deck = the unified control centre. two "session"
 * states on top (Keep-Awake with its live elapsed clock, Game-Mode with its
 * profile name) as wide stat-tiles carrying an inline switch, then the
 * momentary quick-toggles (wifi, bluetooth, mic, do-not-disturb, night,
 * airplane, tablet, webcam) as a collapsible, reorderable tile row
 * (DeckToggles.qml) beneath. this file owns most toggles' live state/probes
 * (webcam is the exception -- Singletons/Webcam.qml owns it instead, since
 * the bar's bridge indicator needs it live even while the deck is closed);
 * DeckToggles owns the catalog, layout and edit-mode UI. polling here (wifi
 * / mic / night / airplane / tablet probes) is gated on `active` so it only
 * runs while the deck is open. content is column-wide; the deck renders the
 * "Controls" eyebrow above us.
 */
Item {
    id: root

    property real s: 1
    property bool active: true

    implicitHeight: content.implicitHeight

    readonly property string scripts: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/"

    // ── keep-awake elapsed ────────────────────────────────────────────────
    property int awakeElapsed: 0
    Timer {
        interval: 1000
        running: root.active && Flags.keepAwake && Flags.keepAwakeSince > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.awakeElapsed = Math.max(0, Math.floor((Date.now() - Flags.keepAwakeSince) / 1000))
    }

    function fmtAwake(sec) {
        var v = Math.max(0, sec);
        var h = Math.floor(v / 3600);
        var m = Math.floor((v % 3600) / 60);
        var r = v % 60;
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return (h > 0 ? h + ":" + p(m) : m) + ":" + p(r);
    }

    // ── quick-toggle state (wifi, mic; bluetooth via BT service, night via pgrep) ──
    property bool wifiOn: false
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" }
    }
    function toggleWifi() {
        Spawn.spawn(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]);
        root.wifiOn = !root.wifiOn;
        wifiPoll.restart();
    }
    Timer { id: wifiPoll; interval: 1200; onTriggered: wifiProc.running = true }

    property bool micMuted: true
    Process {
        id: micProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.micMuted = this.text.indexOf("MUTED") >= 0 }
    }
    function toggleMic() {
        Spawn.spawn(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        root.micMuted = !root.micMuted;
        micPoll.restart();
    }
    Timer { id: micPoll; interval: 600; onTriggered: micProc.running = true }

    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btOn: btAdapter ? btAdapter.enabled : false
    function toggleBt() {
        if (root.btAdapter)
            root.btAdapter.enabled = !root.btAdapter.enabled;
    }

    property bool nightOn: false
    Process {
        id: nightProc
        command: ["sh", "-c", "pgrep -x hyprsunset >/dev/null 2>&1 && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: root.nightOn = this.text.trim() === "on" }
    }
    function toggleNight() {
        Spawn.spawn([root.scripts + "ryoku-cmd-nightlight"]);
        root.nightOn = !root.nightOn;
        nightPoll.restart();
    }
    Timer { id: nightPoll; interval: 2000; onTriggered: nightProc.running = true }

    // airplane: rfkill block/unblock all radios at once. poll-based (not just
    // a locally-flipped bool) so a physical airplane-mode hardware key is
    // reflected instead of fought.
    property bool airplaneOn: false
    Process {
        id: airplaneProc
        command: ["sh", "-c", "rfkill -J 2>/dev/null | jq -r 'if ([.rfkilldevices[]? | select(.type==\"wlan\" or .type==\"bluetooth\") | .soft] | any(. == \"unblocked\")) then \"off\" else \"on\" end'"]
        stdout: StdioCollector { onStreamFinished: root.airplaneOn = this.text.trim() === "on" }
    }
    function toggleAirplane() {
        Spawn.spawn(["sh", "-c", root.airplaneOn ? "rfkill unblock all" : "rfkill block all"]);
        root.airplaneOn = !root.airplaneOn;
        airplanePoll.restart();
    }
    Timer { id: airplanePoll; interval: 1200; onTriggered: airplaneProc.running = true }

    // tablet mode: disables the built-in keyboard + trackpad only, via the
    // ryoku-cmd-tablet-mode script (device detection lives there, not here).
    property bool tabletOn: false
    Process {
        id: tabletProc
        command: ["sh", "-c", root.scripts + "ryoku-cmd-tablet-mode status 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.tabletOn = this.text.trim() === "on" }
    }
    function toggleTablet() {
        Spawn.spawn([root.scripts + "ryoku-cmd-tablet-mode", root.tabletOn ? "off" : "on"]);
        root.tabletOn = !root.tabletOn;
        tabletPoll.restart();
    }
    Timer { id: tabletPoll; interval: 2000; onTriggered: tabletProc.running = true }

    // webcam: unlike every toggle above, its live state (Webcam.on) is owned
    // by the global Webcam singleton, not local Process/Timer pairs here --
    // the bar's bridge indicator (BarStatus.qml) needs a live answer even
    // while the deck is closed, so it polls continuously rather than only
    // while `active`. DeckToggles.qml reads/writes it directly.

    function repoll() {
        wifiProc.running = true;
        micProc.running = true;
        nightProc.running = true;
        airplaneProc.running = true;
        tabletProc.running = true;
    }
    onActiveChanged: if (active) repoll()
    Component.onCompleted: repoll()
    Timer {
        interval: 4000
        running: root.active
        repeat: true
        onTriggered: root.repoll()
    }

    // ── wide session stat-tile: glyph · label · live value. lights the whole
    // tile vermilion-tinted when on and the whole face taps to toggle, matching
    // the quick-toggles below (no separate switch; the tint is the state).
    component StatTile: Rectangle {
        id: st
        property string glyph: ""
        property string label: ""
        property string value: ""
        property bool on: false
        signal toggled()

        height: 46 * root.s
        radius: Theme.radius
        color: st.on ? Qt.alpha(Theme.brand, 0.16)
            : (stHov.hovered ? Theme.frameBg : Theme.tileBg)
        border.width: 1
        border.color: st.on ? Theme.brand
            : (stHov.hovered ? Theme.frameBorder : Theme.border)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

        GlyphIcon {
            id: stIcon
            anchors.left: parent.left
            anchors.leftMargin: 11 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: 16 * root.s
            name: st.glyph
            color: st.on ? Theme.brand : Theme.iconDim
            stroke: 1.6
        }

        Column {
            anchors.left: stIcon.right
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1 * root.s

            Text {
                width: parent.width
                text: st.label
                elide: Text.ElideRight
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 8 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1.4 * root.s
                font.capitalization: Font.AllUppercase
            }
            Text {
                width: parent.width
                text: st.value
                elide: Text.ElideRight
                color: st.on ? Theme.brand : Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        HoverHandler { id: stHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: st.toggled() }
    }

    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8 * root.s

        // two session stat-tiles side by side.
        Row {
            width: parent.width
            spacing: 8 * root.s
            readonly property real tileW: (width - spacing) / 2

            StatTile {
                width: parent.tileW
                glyph: "coffee"
                label: "Keep Awake"
                value: Flags.keepAwake ? root.fmtAwake(root.awakeElapsed) : "OFF"
                on: Flags.keepAwake
                onToggled: Flags.keepAwake = !Flags.keepAwake
            }
            StatTile {
                width: parent.tileW
                glyph: "cpu"
                label: "Game Mode"
                value: Flags.gameMode ? "ON" : "OFF"
                on: Flags.gameMode
                onToggled: Flags.gameMode = !Flags.gameMode
            }
        }

        // quick-toggles: collapsible, reorderable row (wifi/bluetooth/mic/
        // dnd/night/airplane/tablet), catalog + edit-mode in DeckToggles.qml.
        DeckToggles {
            width: parent.width
            s: root.s
            deck: root
        }
    }
}
