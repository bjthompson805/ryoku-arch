pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// ryovm, the monochrome yard. Two lanes: LIBRARY (the yard list left, the machine
// stage right) and NEW (a CATALOG / INSTANT / ISO channel, its grid or explainer
// left, its create sheet right). Paper and ink; the departure board keeps the
// yard's headline; one red hanko on the stage is the only colour the chrome owns.
Rectangle {
    id: app

    implicitWidth: 1180
    implicitHeight: 760
    color: Tokens.paper

    property bool settingsOpen: false
    property string mode: "library"     // library | new
    property string channel: "catalog"  // catalog | instant | iso  (NEW lane)
    property string query: ""

    // only a hard hardware fault gates the whole window; a missing engine is an
    // annunciator banner, so the library (list needs no engine) stays a working
    // room rather than a locked door.
    readonly property bool gated: Vm.capsLoaded && Vm.kvmOff
    readonly property bool engineMissing: Vm.capsLoaded && !Vm.kvmOff && !Vm.caps.quickemu
    readonly property int runningCount: {
        var n = 0;
        for (var i = 0; i < Vm.vms.length; i++)
            if (Vm.vms[i].running === true)
                n++;
        return n;
    }
    readonly property bool pending: Vm.downloading || Vm.busy

    focus: true
    Keys.onEscapePressed: {
        if (app.settingsOpen) app.settingsOpen = false;
        else if (search.focused) app.forceActiveFocus();
        else if (app.query.length > 0) app.query = "";
        else if (app.mode === "new") app.mode = "library";
    }
    Keys.onUpPressed: app.moveSelection(-1)
    Keys.onDownPressed: app.moveSelection(1)
    Keys.onReturnPressed: app.launchSelected()
    Keys.onEnterPressed: app.launchSelected()
    Shortcut {
        sequences: ["/", "Ctrl+K"]
        onActivated: { search.focus(); }
    }
    Shortcut { sequence: "Ctrl+Q"; onActivated: app.requestQuit() }

    function moveSelection(dir) {
        if (app.mode !== "library" || lib.shown.length === 0)
            return;
        var idx = -1;
        for (var i = 0; i < lib.shown.length; i++)
            if (lib.shown[i].name === Vm.selectedName) { idx = i; break; }
        idx = Math.max(0, Math.min(lib.shown.length - 1, idx + dir));
        Vm.select(lib.shown[idx].name);
    }
    function launchSelected() {
        if (app.mode !== "library" || Vm.busy || !Vm.selected)
            return;
        if (Vm.selected.running)
            Vm.stop(Vm.selected.name);
        else if (Vm.caps.quickemu === true)
            Vm.launch(Vm.selected.name, ({ "gtk": "window", "spice": "spice", "none": "headless" })[Vm.selected.display] || "window");
    }
    function requestQuit() {
        if (Vm.downloading && !quitArm.running) {
            Vm.info("A download is running. Cancel it, or quit again to abandon it");
            quitArm.restart();
            return;
        }
        Qt.quit();
    }
    Timer { id: quitArm; interval: 3000 }

    onModeChanged: if (mode === "new") app._loadChannel()
    onChannelChanged: if (mode === "new") app._loadChannel()
    function _loadChannel() {
        if (channel === "catalog") Vm.loadCatalog(false);
        else if (channel === "instant") Vm.loadCloud();
    }

    // deep-link start mode, and an optional OS to preselect once it lands.
    Component.onCompleted: {
        var m = Quickshell.env("RYOVM_START_MODE");
        if (m === "catalog" || m === "instant") { app.mode = "new"; app.channel = m; }
    }
    readonly property string startOs: Quickshell.env("RYOVM_START_OS") || ""
    Connections {
        target: Vm
        function onCreated(name) { app.mode = "library"; }
        function onOsListChanged() {
            if (app.startOs.length === 0 || Vm.selectedOs !== null)
                return;
            for (var i = 0; i < Vm.osList.length; i++)
                if (Vm.osList[i].os === app.startOs) { Vm.selectOs(Vm.osList[i]); break; }
        }
    }

    // ---- head --------------------------------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        anchors.topMargin: Tokens.s5
        height: 64

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s2
            Row {
                spacing: Tokens.s2
                Rectangle { width: 16; height: 1; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "\u529b"; color: Tokens.inkMuted; font.family: Tokens.jp; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "RYOKU VM"
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackMark
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                text: "Build, run and manage virtual machines."
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: 12
            }
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Tokens.s1
            IconBtn { glyph: "\u2699"; onAct: app.settingsOpen = true }
            IconBtn { glyph: "\u2715"; onAct: app.requestQuit() }
        }

        // the departure board: the yard's headline, always live.
        FlapWord {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: !app.gated
            text: String(Vm.vms.length).padStart(2, "0") + " MACHINES  "
                + String(app.runningCount).padStart(2, "0") + " RUNNING"
            cellW: 14; cellH: 21; fontPx: 12
            ink: Tokens.ink
        }
    }

    // ---- toolbar -----------------------------------------------------------
    Item {
        id: toolbar
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        anchors.topMargin: Tokens.s3
        height: 40
        visible: !app.gated

        Seg {
            id: laneSeg
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            options: ["LIBRARY", "NEW"]
            current: app.mode.toUpperCase()
            onChose: (k) => { app.mode = k.toLowerCase(); app.query = ""; }
        }

        Field {
            id: search
            anchors.left: laneSeg.right
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            width: 280
            toolbar: true
            text: app.query
            placeholder: app.mode === "library" ? "Filter your machines"
                : app.channel === "instant" ? "Search instant images"
                : app.channel === "iso" ? "Load ISO"
                : "Search 90+ operating systems"
            onEdited: (v) => app.query = v
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s2
            Seg {
                anchors.verticalCenter: parent.verticalCenter
                visible: app.mode === "new"
                options: ["CATALOG", "INSTANT", "ISO"]
                current: app.channel.toUpperCase()
                onChose: (k) => { app.channel = k.toLowerCase(); app.query = ""; }
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: app.mode === "new" && app.channel === "catalog"
                glyph: "\u21bb"
                armed: !Vm.catalogLoading
                onAct: Vm.loadCatalog(true)
            }
        }
    }

    // ---- gate: virtualization off (the only whole-window fault) ------------
    Item {
        anchors.top: toolbar.bottom
        anchors.topMargin: Tokens.s4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: bottomBar.top
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        visible: app.gated

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width, 520)
            spacing: Tokens.s4
            Mark { anchors.horizontalCenter: parent.horizontalCenter; size: 96 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Virtualization is off"
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: 18
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                text: "A virtual machine needs hardware virtualization. Turn on SVM / AMD-V (AMD) or VT-x (Intel) in your BIOS/firmware, then reboot."
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: 13
            }
        }
    }

    // ---- engine banner: quickemu missing = a lit fault row, not a locked app --
    Rectangle {
        id: engineBanner
        anchors.top: toolbar.bottom
        anchors.topMargin: app.engineMissing ? Tokens.s3 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        height: app.engineMissing ? 44 : 0
        visible: app.engineMissing && !app.gated
        color: "transparent"
        radius: Tokens.radius
        border.width: Tokens.border
        border.color: Tokens.line
        antialiasing: false

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3
            Annunciator { anchors.verticalCenter: parent.verticalCenter; label: "ENGINE"; lit: true; tileW: 60 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "quickemu is not installed: machines can be imported and configured, not launched."
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: 12
            }
        }
        Btn {
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s2
            anchors.verticalCenter: parent.verticalCenter
            text: "INSTALL ENGINE"
            primary: true
            onAct: settings.installEngine()
        }
    }

    // ---- main: the split ---------------------------------------------------
    Item {
        id: main
        anchors.top: engineBanner.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: faultStrip.top
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        anchors.topMargin: Tokens.s4
        anchors.bottomMargin: Tokens.s2
        visible: !app.gated

        // the grid: gutter s2, widened to s5 at the seam. Left span 5, right 7.
        readonly property real gCol: (width - (Spans.cols - 1) * Tokens.s2) / Spans.cols
        readonly property real leftW: 5 * gCol + 4 * Tokens.s2
        readonly property int seamW: Tokens.s5

        Item {
            id: leftCol
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: main.leftW

            VmGrid {
                id: lib
                anchors.fill: parent
                filter: app.query
                onBuildRequested: { app.mode = "new"; app.channel = "catalog"; }
                opacity: app.mode === "library" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            OsGrid {
                anchors.fill: parent
                filter: app.query
                onInstallRequested: settings.installEngine()
                opacity: app.mode === "new" && app.channel === "catalog" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            CloudGrid {
                anchors.fill: parent
                filter: app.query
                selected: cloudPanel.os
                onPicked: (e) => cloudPanel.os = e
                opacity: app.mode === "new" && app.channel === "instant" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            // ISO left column: the mark and one explanatory sentence.
            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: Tokens.s4
                opacity: app.mode === "new" && app.channel === "iso" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
                Mark { anchors.horizontalCenter: parent.horizontalCenter; size: 96 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Build a machine from any ISO on disk: off-catalogue, the full QEMU reach. Fill in the sheet on the right."
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: 12
                }
            }
        }

        // the seam: a 1px hairline centred in the widened gutter.
        Rectangle {
            anchors.left: leftCol.right
            anchors.leftMargin: main.seamW / 2
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: Tokens.s2
            anchors.bottomMargin: Tokens.s2
            width: 1
            color: Tokens.line
        }

        Item {
            id: rightCol
            anchors.left: leftCol.right
            anchors.leftMargin: main.seamW
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            VmDetail {
                anchors.fill: parent
                opacity: app.mode === "library" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            CreatePanel {
                anchors.fill: parent
                opacity: app.mode === "new" && app.channel === "catalog" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            CloudPanel {
                id: cloudPanel
                anchors.fill: parent
                opacity: app.mode === "new" && app.channel === "instant" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
            IsoPanel {
                anchors.fill: parent
                opacity: app.mode === "new" && app.channel === "iso" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Tokens.swap } }
            }
        }
    }

    // ---- fault strip: sticky until dismissed or superseded -----------------
    Rectangle {
        id: faultStrip
        anchors.bottom: bottomBar.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.s6
        anchors.rightMargin: Tokens.s6
        anchors.bottomMargin: Vm.fault.length > 0 ? Tokens.s2 : 0
        height: Vm.fault.length > 0 ? faultCol.implicitHeight + 2 * Tokens.s2 : 0
        visible: Vm.fault.length > 0
        color: "transparent"
        radius: Tokens.radius
        border.width: Tokens.border
        border.color: Tokens.line
        antialiasing: false
        property bool expanded: false

        Column {
            id: faultCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.s2
            spacing: Tokens.s2

            Item {
                width: parent.width
                height: 22
                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.s3
                    Annunciator { anchors.verticalCenter: parent.verticalCenter; label: "FAULT"; lit: true; warn: true; tileW: 52 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: faultStrip.width - 240
                        elide: Text.ElideRight
                        text: Vm.fault
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: 12
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.s3
                    Text {
                        visible: Vm.faultDetail.indexOf("\n") >= 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: faultStrip.expanded ? "LESS" : "DETAIL"
                        color: fdh.hovered ? Tokens.ink : Tokens.inkMuted
                        font.family: Tokens.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        HoverHandler { id: fdh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: faultStrip.expanded = !faultStrip.expanded }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "DISMISS"
                        color: fxh.hovered ? Tokens.ink : Tokens.inkMuted
                        font.family: Tokens.mono
                        font.pixelSize: 9
                        font.letterSpacing: 1.5
                        HoverHandler { id: fxh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { faultStrip.expanded = false; Vm.clearFault(); } }
                    }
                }
            }

            Flickable {
                visible: faultStrip.expanded
                width: parent.width
                height: Math.min(faultDetailText.implicitHeight, 140)
                contentHeight: faultDetailText.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Text {
                    id: faultDetailText
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: Vm.faultDetail
                    color: Tokens.inkMuted
                    font.family: Tokens.mono
                    font.pixelSize: 11
                }
            }
        }
    }

    // ---- bottom bar --------------------------------------------------------
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 60

        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Tokens.line }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s6
            spacing: Tokens.s3
            Rectangle {
                width: 6; height: 6
                anchors.verticalCenter: parent.verticalCenter
                color: Tokens.ink
                // a heartbeat, only while something is genuinely pending.
                SequentialAnimation on opacity {
                    running: app.pending
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600 }
                    NumberAnimation { to: 1.0; duration: 600 }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Vm.downloading ? "BUILDING · " + Vm.dlName
                    : Vm.busy ? "WORKING"
                    : Vm.status.length > 0 ? Vm.status
                    : (app.runningCount > 0 ? app.runningCount + " RUNNING" : "READY")
                color: Vm.status.length > 0 || app.pending ? Tokens.ink : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 1.4
                font.capitalization: Font.AllUppercase
            }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s6
            spacing: Tokens.s4
            Btn {
                anchors.verticalCenter: parent.verticalCenter
                visible: Vm.downloading
                text: "CANCEL"
                onAct: Vm.cancelCreate()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Vm.caps.version ? "quickemu " + Vm.caps.version : "quickemu"
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: 9
            }
        }
    }

    // ---- overlays ----------------------------------------------------------
    SettingsPanel {
        id: settings
        anchors.fill: parent
        open: app.settingsOpen
        onClosed: app.settingsOpen = false
    }

    // ---- the matte: one grain layer, topmost over everything ---------------
    Grain { anchors.fill: parent }
}
