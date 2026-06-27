pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import "Singletons"

/**
 * utilities slot of the 力 deck = flat-carbon dossier (recorder, keep-awake,
 * quick toggles, recordings list), ported from UtilitiesSurface. polling is
 * gated on `active` so wifi / mic / night probes only run while the deck is
 * open. requestClose() dismisses the deck before any screen-grab action
 * (slurp region, gpu-screen-recorder, xdg-open) so the panel is never in the
 * capture. content is column-wide; implicitHeight is the sum of fixed group
 * heights, width-independent. the deck renders the "Utilities" eyebrow above
 * us, so this one is content-only and groups carry their own micro-labels.
 */
Item {
    id: root

    property real s: 1
    property bool active: true
    signal requestClose()

    implicitHeight: content.implicitHeight

    readonly property string scripts: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/"
    readonly property string recDir: (Quickshell.env("HOME") || "") + "/Videos/Recordings"

    // ── keep-awake elapsed ────────────────────────────────────────────────
    property int awakeElapsed: 0
    Timer {
        interval: 1000
        running: root.active && Flags.keepAwake && Flags.keepAwakeSince > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.awakeElapsed = Math.max(0, Math.floor((Date.now() - Flags.keepAwakeSince) / 1000))
    }

    // ── recordings model ──────────────────────────────────────────────────
    ListModel { id: recModel }

    function refreshRecs() {
        recProc.running = true;
    }

    Process {
        id: recProc
        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -type f -name 'recording_*.mp4' -printf '%T@\\t%s\\t%p\\n' 2>/dev/null | sort -rn", "_", root.recDir]
        stdout: StdioCollector {
            onStreamFinished: {
                recModel.clear();
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i];
                    if (!ln.length)
                        continue;
                    var parts = ln.split("\t");
                    if (parts.length < 3)
                        continue;
                    var path = parts[2];
                    var base = path.substring(path.lastIndexOf("/") + 1).replace(/\.mp4$/, "");
                    recModel.append({ path: path, label: root.prettyName(base), size: root.humanSize(parseInt(parts[1], 10)) });
                }
            }
        }
    }

    function prettyName(base) {
        var m = base.match(/^recording_(\d{4})-(\d{2})-(\d{2})_(\d{2})\.(\d{2})\.(\d{2})/);
        if (!m)
            return base;
        var d = new Date(m[1], m[2] - 1, m[3], m[4], m[5], m[6]);
        return Qt.formatDateTime(d, "MMM d, HH:mm");
    }

    function humanSize(bytes) {
        if (!bytes || bytes < 1024)
            return (bytes || 0) + " B";
        var kb = bytes / 1024;
        if (kb < 1024)
            return Math.round(kb) + " KB";
        var mb = kb / 1024;
        if (mb < 1024)
            return mb.toFixed(mb < 10 ? 1 : 0) + " MB";
        return (mb / 1024).toFixed(1) + " GB";
    }

    onActiveChanged: if (active) {
        refreshRecs();
        wifiProc.running = true;
        micProc.running = true;
        nightProc.running = true;
    }

    // pre-warm recordings + toggle state once at startup, so the first open is
    // already at its final size and the panel doesn't re-morph as polls return.
    Component.onCompleted: {
        refreshRecs();
        wifiProc.running = true;
        micProc.running = true;
        nightProc.running = true;
    }

    // refresh the list a hair after a recording ends so the new file shows up.
    Connections {
        target: Recorder
        function onActiveChanged() {
            if (!Recorder.active)
                recRefresh.restart();
        }
    }
    Timer { id: recRefresh; interval: 1500; onTriggered: root.refreshRecs() }

    // ── quick-toggle state (wifi, mic; bluetooth via BT service) ──────────
    property bool wifiOn: false
    Process {
        id: wifiProc
        command: ["sh", "-c", "nmcli radio wifi 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.wifiOn = this.text.trim() === "enabled" }
    }
    function toggleWifi() {
        Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "off" : "on"]);
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
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        root.micMuted = !root.micMuted;
        micPoll.restart();
    }
    Timer { id: micPoll; interval: 600; onTriggered: micProc.running = true }
    Timer {
        interval: 4000
        running: root.active
        repeat: true
        onTriggered: { wifiProc.running = true; micProc.running = true; nightProc.running = true; }
    }

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
        Quickshell.execDetached([root.scripts + "ryoku-cmd-nightlight"]);
        root.nightOn = !root.nightOn;
        nightPoll.restart();
    }
    Timer { id: nightPoll; interval: 2000; onTriggered: nightProc.running = true }

    // ── record modes ──────────────────────────────────────────────────────
    readonly property var recModes: [
        { glyph: "monitor", label: "Record display",      args: [] },
        { glyph: "region",  label: "Record region",       args: ["-r"] },
        { glyph: "speaker", label: "Display with sound",  args: ["-s"] },
        { glyph: "speaker", label: "Region with sound",   args: ["-sr"] }
    ]
    property bool menuOpen: false

    // recording grabs the screen: region mode runs slurp, and gpu-screen-
    // recorder would otherwise capture this very panel. close the deck, let
    // the morph settle, then start. slurp gets a clear screen, panel stays
    // out of the file.
    property var pendingRec: null
    function startRecording(args) {
        root.pendingRec = args;
        root.menuOpen = false;
        root.requestClose();
        recLaunch.restart();
    }
    Timer {
        id: recLaunch
        interval: 400
        onTriggered: {
            if (root.pendingRec !== null) {
                Recorder.start(root.pendingRec);
                root.pendingRec = null;
            }
        }
    }

    function fmtAwake(sec) {
        var s = Math.max(0, sec);
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        var r = s % 60;
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return (h > 0 ? h + ":" + p(m) : m) + ":" + p(r);
    }

    // ── reusable bits ─────────────────────────────────────────────────────

    // flat icon button (play / folder / trash / pause / stop). tints carry
    // semantics: vermilion = destructive, cream = neutral, iconDim = rest.
    component IconBtn: Rectangle {
        property string glyph: ""
        property color tint: Theme.iconDim
        property real box: 26
        signal clicked()
        width: box * root.s
        height: box * root.s
        color: hov.hovered ? Theme.frameBg : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        GlyphIcon {
            anchors.centerIn: parent
            width: parent.box * 0.5 * root.s
            height: parent.box * 0.5 * root.s
            name: parent.glyph
            color: parent.tint
            stroke: 1.6
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }

    // flat quick-toggle tile: glyph only, lights vermilion when on. square,
    // hairline border at rest, frameBg on hover.
    component ToggleTile: Rectangle {
        id: tt
        property string glyph: ""
        property bool on: false
        signal acted()
        height: 36 * root.s
        color: tt.on ? Theme.brand : (tHov.hovered ? Theme.frameBg : "transparent")
        border.width: 1
        border.color: tt.on ? Theme.brand : (tHov.hovered ? Theme.frameBorder : Theme.border)
        Behavior on color { ColorAnimation { duration: Motion.fast } }
        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
        GlyphIcon {
            anchors.centerIn: parent
            width: 15 * root.s
            height: 15 * root.s
            name: tt.glyph
            color: tt.on ? Theme.cream : (tHov.hovered ? Theme.cream : Theme.iconDim)
            stroke: 1.6
        }
        HoverHandler { id: tHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: tt.acted() }
    }

    // ── content stack ─────────────────────────────────────────────────────
    Column {
        id: content
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 14 * root.s

        // ── record ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 9 * root.s

            // eyebrow + live status pill, right-aligned.
            Item {
                width: parent.width
                height: recEyebrow.implicitHeight

                MicroLabel { id: recEyebrow; label: "Record"; s: root.s }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: recEyebrow.verticalCenter
                    text: Recorder.paused
                        ? "PAUSED"
                        : (Recorder.active ? Recorder.elapsedText : "OFF")
                    color: Recorder.active ? Theme.brand : Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4 * root.s
                    font.capitalization: Font.AllUppercase
                    font.features: { "tnum": 1 }
                }
            }

            // running controls = pulsing vermilion REC tag, elapsed time in
            // tabular figures, pause + stop on the right.
            Item {
                width: parent.width
                visible: Recorder.active
                height: 30 * root.s

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 9 * root.s

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: recPillText.implicitWidth + 14 * root.s
                        height: 20 * root.s
                        color: Recorder.paused ? Theme.faint : Theme.brand
                        opacity: Recorder.paused ? 1 : Recorder.pulse
                        Text {
                            id: recPillText
                            anchors.centerIn: parent
                            text: Recorder.paused ? "PAUSED" : "REC"
                            color: Theme.cream
                            font.family: Theme.mono
                            font.pixelSize: 9.5 * root.s
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2 * root.s
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Recorder.elapsedText
                        color: Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13 * root.s
                        font.features: { "tnum": 1 }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    IconBtn {
                        visible: Recorder.canPause
                        glyph: Recorder.paused ? "play" : "pause"
                        tint: Theme.cream
                        onClicked: Recorder.togglePause()
                    }
                    IconBtn {
                        glyph: "stop"
                        tint: Theme.vermLit
                        onClicked: Recorder.stop()
                    }
                }
            }

            // idle Record button: flat tile, opens the mode dropdown.
            Rectangle {
                id: recBtn
                width: parent.width
                visible: !Recorder.active
                height: 32 * root.s
                color: recBtnHov.hovered ? Theme.frameBg : Theme.tileBg
                border.width: 1
                border.color: root.menuOpen ? Theme.brand : Theme.border
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                Row {
                    anchors.centerIn: parent
                    spacing: 8 * root.s
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13 * root.s
                        height: 13 * root.s
                        name: "record"
                        color: Theme.brand
                        stroke: 1.7
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RECORD"
                        color: Theme.cream
                        font.family: Theme.mono
                        font.pixelSize: 10.5 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.6 * root.s
                    }
                    GlyphIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 11 * root.s
                        height: 11 * root.s
                        name: "chevron-down"
                        color: Theme.subtle
                        stroke: 1.7
                        rotation: root.menuOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                    }
                }
                HoverHandler { id: recBtnHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.menuOpen = !root.menuOpen }
            }

            // inline mode dropdown: flat rows, hover-highlighted.
            Column {
                width: parent.width
                visible: root.menuOpen && !Recorder.active
                spacing: 0

                Repeater {
                    model: root.recModes
                    delegate: Rectangle {
                        id: mItem
                        required property var modelData
                        width: parent.width
                        height: 30 * root.s
                        color: mHov.hovered ? Theme.frameBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 8 * root.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 9 * root.s
                            GlyphIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13 * root.s
                                height: 13 * root.s
                                name: mItem.modelData.glyph
                                color: Theme.iconDim
                                stroke: 1.6
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: mItem.modelData.label
                                color: Theme.cream
                                font.family: Theme.font
                                font.pixelSize: 11.5 * root.s
                            }
                        }
                        HoverHandler { id: mHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.startRecording(mItem.modelData.args) }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── keep awake ────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 9 * root.s

            MicroLabel { label: "Keep Awake"; s: root.s }

            Item {
                width: parent.width
                height: 32 * root.s

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s
                    Text {
                        text: Flags.keepAwake ? root.fmtAwake(root.awakeElapsed) : "OFF"
                        color: Flags.keepAwake ? Theme.brand : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        text: Flags.keepAwake ? "ACTIVE" : "NORMAL POWER MANAGEMENT"
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.4 * root.s
                        font.capitalization: Font.AllUppercase
                    }
                }

                DeckSwitch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    on: Flags.keepAwake
                    onToggled: Flags.keepAwake = !Flags.keepAwake
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── game mode ─────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 9 * root.s

            MicroLabel { label: "Game Mode"; s: root.s }

            Item {
                width: parent.width
                height: 32 * root.s

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2 * root.s
                    Text {
                        text: Flags.gameMode ? "ON" : "OFF"
                        color: Flags.gameMode ? Theme.brand : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 14 * root.s
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: Flags.gameMode ? "LOW-LATENCY PROFILE" : "STANDARD DESKTOP"
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 8.5 * root.s
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.4 * root.s
                        font.capitalization: Font.AllUppercase
                    }
                }

                DeckSwitch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    s: root.s
                    on: Flags.gameMode
                    onToggled: Flags.gameMode = !Flags.gameMode
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── toggles ───────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 9 * root.s

            MicroLabel { label: "Toggles"; s: root.s }

            Row {
                id: togglesRow
                width: parent.width
                spacing: 6 * root.s
                // five even tiles. deck width ~280 scale-units, so each tile
                // is ~51 wide.
                readonly property real tileW: (width - spacing * 4) / 5

                ToggleTile {
                    width: togglesRow.tileW
                    glyph: "wifi"
                    on: root.wifiOn
                    onActed: root.toggleWifi()
                }
                ToggleTile {
                    width: togglesRow.tileW
                    glyph: "bluetooth"
                    on: root.btOn
                    onActed: root.toggleBt()
                }
                ToggleTile {
                    width: togglesRow.tileW
                    glyph: root.micMuted ? "mic-off" : "mic"
                    on: !root.micMuted
                    onActed: root.toggleMic()
                }
                ToggleTile {
                    width: togglesRow.tileW
                    glyph: "dnd"
                    on: Flags.dnd
                    onActed: Flags.dnd = !Flags.dnd
                }
                ToggleTile {
                    width: togglesRow.tileW
                    glyph: "moon"
                    on: root.nightOn
                    onActed: root.toggleNight()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.hair }

        // ── recordings ────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 9 * root.s

            Item {
                width: parent.width
                height: recEye.implicitHeight

                MicroLabel { id: recEye; label: "Recordings"; s: root.s }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: recEye.verticalCenter
                    text: recModel.count < 10 ? "0" + recModel.count : String(recModel.count)
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.4 * root.s
                    font.features: { "tnum": 1 }
                }
            }

            Text {
                visible: recModel.count === 0
                text: "No recordings yet"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }

            ListView {
                width: parent.width
                visible: recModel.count > 0
                // height = fixed multiple of row height, cap at 4 rows. never
                // derived from width, so the column lays out clean.
                implicitHeight: Math.min(recModel.count, 4) * 30 * root.s
                clip: true
                model: recModel
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: recItem
                    required property string path
                    required property string label
                    required property string size
                    width: ListView.view.width
                    height: 30 * root.s
                    color: rHov.hovered ? Theme.frameBg : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    HoverHandler { id: rHov }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 4 * root.s
                        anchors.right: sizeText.left
                        anchors.rightMargin: 8 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: recItem.label
                        elide: Text.ElideRight
                        color: Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 11 * root.s
                    }

                    Text {
                        id: sizeText
                        anchors.right: actions.left
                        anchors.rightMargin: 6 * root.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: recItem.size
                        color: Theme.faint
                        font.family: Theme.mono
                        font.pixelSize: 9.5 * root.s
                        font.features: { "tnum": 1 }
                    }

                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        IconBtn {
                            glyph: "play"
                            box: 24
                            tint: Theme.cream
                            onClicked: { Quickshell.execDetached(["xdg-open", recItem.path]); root.requestClose(); }
                        }
                        IconBtn {
                            glyph: "folder"
                            box: 24
                            onClicked: { Quickshell.execDetached(["xdg-open", root.recDir]); root.requestClose(); }
                        }
                        IconBtn {
                            glyph: "trash"
                            box: 24
                            tint: Theme.vermLit
                            onClicked: {
                                Quickshell.execDetached(["sh", "-c", "gio trash \"$1\" 2>/dev/null || rm -f \"$1\"", "_", recItem.path]);
                                recRefresh.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
