pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// System > GPU (DESIGN.md section 11, SYSTEM). Which GPU Ryoku renders on, and
// the optional GPU-passthrough stack that binds the discrete GPU to vfio so a
// VM can own it. Running the VM lives in the ryovm app, not here; this page is
// graphics hardware only. Its backend is `ryoku-hub gpu` (caps probe + mode
// get/set + the apply/enable dry-run), not the shared config store, so it is
// full-bleed and draws its whole content region itself: a read-only specimen
// card on the left, the render-mode selector and passthrough dossier scrolling
// on the right. Everything dangerous is gated on the verdict from `gpu caps`.
// Monochrome: no colour carries state, so severity reads through the ink ramp
// (calm recedes to inkMuted, a call to action brightens to ink) and a filled
// dot for good versus a hollow ring for attention. Every value is a Token.
Item {
    id: pg

    property var hub
    // A full-bleed page draws the whole content region itself: the shell hides
    // the side panel and global action bar, and keeps the rail.
    readonly property bool fullBleed: true
    // The page's contract with the shell: mode writes land in gpu.lua and take
    // effect at next login, so there is never unsaved preview state to guard.
    readonly property bool previewDirty: false

    property var caps: ({})
    property string mode: "hybrid"
    property string planText: ""
    property bool planning: false
    property bool enabling: false      // enable launched in a terminal; awaiting recheck
    property bool showChecks: false    // disclosure: the passthrough readiness dossier
    property string actionError: ""
    property string capsError: ""      // caps probe failed/timed out; show retry, not a spinner
    property string modeWarn: ""

    // the GPU wired to the display: what the desktop renders on.
    readonly property var renderGpu: {
        var p = pg.caps.passthrough, h = pg.caps.host;
        if (p && p.drivesDisplay)
            return p;
        if (h && h.drivesDisplay)
            return h;
        return h || p || null;
    }
    readonly property string renderName: pg.renderGpu ? pg.renderGpu.model : "your GPU"
    readonly property string dgpuName: pg.caps.passthrough ? pg.caps.passthrough.model : "the discrete GPU"

    readonly property bool capsLoaded: pg.caps.verdict !== undefined
    // still probing: nothing decided and no failure to report yet.
    readonly property bool ptPending: pg.capsError === "" && !pg.capsLoaded
    readonly property bool ptOk: pg.caps.verdict === "ready"

    // passthrough status line, by verdict. All six strings survive verbatim.
    readonly property string ptText: {
        switch (pg.caps.verdict) {
        case "ready": return "Ready. " + pg.dgpuName + " is free for a VM to claim, and returns to the desktop when the VM stops.";
        case "needs-relogin": return "Set up. Log out and back in once, then it is ready.";
        case "needs-reboot": return "Your screen runs on " + pg.dgpuName + ". Switch to Hybrid GPU mode in the BIOS (look for GPU Mode, MUX, or Hybrid/Optimus) and reboot, so the built-in GPU drives the display and the discrete GPU is free.";
        case "needs-setup": return "Not set up yet. Review the changes, then enable it below.";
        case "incapable": return "This machine can't pass a GPU to a VM. Open the readiness checks below for why.";
        default: return pg.capsError !== "" ? "Couldn't read your graphics hardware." : "Checking\u2026";
        }
    }

    function reload() {
        pg.capsError = "";    // re-checking: clear the old failure so Retry shows progress, not a frozen error
        capsProc.running = true;
        modeProc.running = true;
    }
    function act(cmd) {
        pg.actionError = "";
        runProc.command = cmd;
        runProc.running = true;
    }
    function setMode(m) {
        pg.modeWarn = "";
        modeSetProc.command = ["ryoku-hub", "gpu", "mode", "set", m];
        modeSetProc.running = true;
    }
    function reviewEnable() {
        planProc.command = ["ryoku-hub", "gpu", "apply", "enable", "--dry-run"];
        planProc.running = true;
    }
    // the real enable builds the AUR Looking Glass stack (needs a TTY for the
    // build + sudo) then escalates for the system setup, so it runs in a terminal.
    function enableInTerminal() {
        Quickshell.execDetached(["kitty", "--class", "ryoku-gpu", "-e", "sh", "-c",
            "ryoku-hub gpu apply enable; echo; read -n1 -rsp 'Done. Press any key to close\u2026'; echo"]);
        pg.planning = false;
        pg.planText = "";
        pg.enabling = true;
    }
    function recheck() {
        pg.enabling = false;
        pg.reload();
    }

    // Seg carries labels; the backend keys are their lowercase form.
    function modeLabel(m) { return m.length ? m.charAt(0).toUpperCase() + m.slice(1) : ""; }

    Component.onCompleted: pg.reload()

    // ── backend: probe caps, read/write the render mode, dry-run the enable ──
    Process {
        id: capsProc
        command: ["ryoku-hub", "gpu", "caps"]
        stdout: StdioCollector { id: capsOut }
        stderr: StdioCollector { id: capsErr }
        // decide on exit, not per-stream: a non-zero exit or unparseable output
        // becomes a visible error + retry instead of an endless "Checking...".
        onExited: (code) => {
            if (code === 0) {
                try {
                    pg.caps = JSON.parse(capsOut.text);
                    pg.capsError = "";
                    return;
                } catch (e) {
                    console.log("gpu: caps parse failed: " + e);
                }
            }
            pg.capsError = capsErr.text.trim() || ("ryoku-hub gpu caps exited " + code);
        }
    }
    Process {
        id: modeProc
        command: ["ryoku-hub", "gpu", "mode", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    pg.mode = JSON.parse(this.text).mode;
                } catch (e) {}
            }
        }
    }
    Process {
        id: modeSetProc
        stdout: StdioCollector { onStreamFinished: pg.reload() }
        stderr: StdioCollector {
            onStreamFinished: {
                var e = this.text.trim();
                if (e.length > 0)
                    pg.modeWarn = e;
            }
        }
    }
    Process {
        id: runProc
        stdout: StdioCollector { onStreamFinished: pg.reload() }
        stderr: StdioCollector {
            onStreamFinished: {
                var e = this.text.trim();
                if (e.length > 0)
                    pg.actionError = e;
            }
        }
    }
    Process {
        id: planProc
        stdout: StdioCollector {
            onStreamFinished: {
                pg.planText = this.text;
                pg.planning = true;
            }
        }
    }
    // while the enable runs in its terminal, poll caps so the page advances on
    // its own when the stack appears, instead of waiting for a manual Recheck.
    Timer {
        interval: 4000
        repeat: true
        running: pg.enabling
        onTriggered: capsProc.running = true
    }

    // ── a section leader: dot + CAPS label + hairline rule ────────────────
    component SectionHead: Item {
        id: sh
        property string label: ""
        implicitHeight: 16
        Row {
            id: shLab
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s2
            Rectangle {
                width: 4; height: 4; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: sh.label; color: Tokens.ink; font.family: Tokens.ui
                font.pixelSize: Tokens.fMicro; font.weight: Font.Medium
                font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Rectangle {
            anchors.left: shLab.right; anchors.right: parent.right
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            height: 1; color: Tokens.lineSoft
        }
    }

    // ── one readiness-dossier row: level pip + label + detected value ─────
    // The backend gives level ok|warn|bad; monochrome carries it as a filled
    // dot (good) versus a hollow ring (attention), with the value brightening
    // to ink when something needs looking at. The hint field is dropped, as the
    // old page dropped it -- there is nothing to put in its place here.
    component CheckRow: Item {
        id: cr
        property var check: null
        readonly property string lvl: cr.check ? cr.check.level : ""
        readonly property bool attn: cr.lvl === "warn" || cr.lvl === "bad"
        width: parent ? parent.width : 0
        height: 30

        Rectangle {
            id: dot
            width: 7; height: 7; radius: 3.5
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: cr.attn ? "transparent" : Tokens.ink
            border.width: cr.attn ? Tokens.border : 0
            border.color: Tokens.ink
        }
        Text {
            anchors.left: dot.right; anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            text: cr.check ? cr.check.label : ""
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // a detected value is file-truth, so mono (DESIGN.md section 2).
            text: cr.check ? cr.check.value : ""
            color: cr.attn ? Tokens.ink : Tokens.inkMuted
            font.family: Tokens.mono
            font.pixelSize: Tokens.fMicro
        }
    }

    // one dossier inventory line: tag chip, model + spec, and a role marker.
    // Page-scope (inline components cannot nest); used inside GpuSpecimen.
    component GpuRow: Item {
        id: gr
        property var gpu: null
        property string tag: ""
        width: parent ? parent.width : 0
        height: 36
        visible: gr.gpu !== null && gr.gpu !== undefined
        readonly property bool active: gr.gpu !== null && gr.gpu !== undefined && gr.gpu.drivesDisplay === true

        Rectangle {
            id: chip
            width: 46; height: 20; radius: Tokens.radius
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: "transparent"
            border.width: Tokens.border
            border.color: gr.active ? Tokens.ink : Tokens.line
            Text {
                anchors.centerIn: parent
                text: gr.tag
                color: gr.active ? Tokens.ink : Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
            }
        }
        Column {
            anchors.left: chip.right; anchors.leftMargin: Tokens.s3
            anchors.right: role.left; anchors.rightMargin: Tokens.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: gr.gpu ? gr.gpu.model : ""
                color: gr.active ? Tokens.ink : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }
            Text {
                text: gr.gpu ? (gr.gpu.vramMb + " MB \u00b7 " + gr.gpu.driver) : ""
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
            }
        }
        Row {
            id: role
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s1
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: gr.active ? "DISPLAY" : "FREE"
                color: gr.active ? Tokens.ink : Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fTiny
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
            }
            Rectangle {
                width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: gr.active ? Tokens.ink : Tokens.inkFaint
            }
        }
    }

    // ── the read-only GPU specimen card ───────────────────────────────────
    // A flat instrument plate (the old chromatic trading-card washes, foil and
    // parallax are decoration monochrome does not permit): the render GPU as
    // the hero readout with a VRAM plate, the machine type line, and the two
    // GPUs in a dossier box with a DISPLAY/FREE role marker.
    component GpuSpecimen: Rectangle {
        id: card
        property var caps: ({})
        property bool failed: false

        readonly property var renderGpu: {
            var p = card.caps.passthrough, h = card.caps.host;
            if (p && p.drivesDisplay)
                return p;
            if (h && h.drivesDisplay)
                return h;
            return h || p || null;
        }

        implicitHeight: body.implicitHeight + Tokens.s4 * 2
        radius: Tokens.radius
        color: "transparent"
        border.width: Tokens.border
        border.color: Tokens.line

        Column {
            id: body
            anchors.left: parent.left; anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.s4
            spacing: Tokens.s4

            // eyebrow: the graphics seal.
            Row {
                spacing: Tokens.s2
                Text {
                    text: "\u529b"; color: Tokens.ink; font.family: Tokens.jp
                    font.pixelSize: Tokens.fMicro
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "GRAPHICS"; color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackMark
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // hero: the GPU that draws the desktop, with a VRAM plate.
            Row {
                width: parent.width
                spacing: Tokens.s3
                Column {
                    width: parent.width - vram.width - parent.spacing
                    spacing: Tokens.s1
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "RENDERS ON"
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackLabel
                    }
                    Text {
                        width: parent.width
                        text: card.renderGpu ? card.renderGpu.model : (card.failed ? "Unavailable" : "Detecting\u2026")
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fValue
                        font.weight: Font.Light
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "the desktop draws here"
                        color: Tokens.inkFaint; font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny
                    }
                }
                Rectangle {
                    id: vram
                    anchors.verticalCenter: parent.verticalCenter
                    visible: card.renderGpu !== null
                    width: vramCol.width + Tokens.s3 * 2
                    height: vramCol.height + Tokens.s2 * 2
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: Tokens.line
                    Column {
                        id: vramCol
                        anchors.centerIn: parent
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: card.renderGpu ? (Math.round(card.renderGpu.vramMb / 1024) + "G") : ""
                            color: Tokens.ink; font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow; font.weight: Font.Light
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "VRAM"
                            color: Tokens.inkMuted; font.family: Tokens.ui
                            font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                            font.letterSpacing: Tokens.trackLabel
                        }
                    }
                }
            }

            // type line: INVENTORY badge + hairline + chassis / cpu.
            Row {
                width: parent.width
                spacing: Tokens.s2
                height: 20
                Rectangle {
                    id: invBadge
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18; width: invText.implicitWidth + Tokens.s3
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: Tokens.line
                    Text {
                        id: invText
                        anchors.centerIn: parent
                        text: "INVENTORY"
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                        font.letterSpacing: Tokens.trackLabel
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(1, parent.width - invBadge.width - machineLabel.implicitWidth - 2 * parent.spacing)
                    height: 1; color: Tokens.lineSoft
                }
                Text {
                    id: machineLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: (card.caps.chassis === "laptop" ? "LAPTOP" : "DESKTOP") + (card.caps.cpu ? " \u00b7 " + card.caps.cpu : "")
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fTiny; font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackLabel
                }
            }

            // dossier box: the two GPUs behind a hairline.
            Rectangle {
                width: parent.width
                height: invCol.implicitHeight + Tokens.s3 * 2
                color: Tokens.tint5
                radius: Tokens.radius
                border.width: Tokens.border
                border.color: Tokens.lineSoft
                Column {
                    id: invCol
                    anchors.fill: parent
                    anchors.margins: Tokens.s3
                    spacing: Tokens.s2
                    GpuRow { tag: "iGPU"; gpu: card.caps.host }
                    Rectangle {
                        visible: (card.caps.host !== undefined) && (card.caps.passthrough !== undefined)
                        width: parent.width; height: 1; color: Tokens.lineSoft
                    }
                    GpuRow { tag: "dGPU"; gpu: card.caps.passthrough }
                }
            }

            // MUX line, when the machine reports one.
            Text {
                visible: card.caps.mux !== undefined && card.caps.mux !== "none"
                text: "MUX " + (card.caps.mux ? card.caps.mux.replace("present-", "").toUpperCase() : "")
                color: Tokens.inkFaint; font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
            }
        }
    }

    // ── head: eyebrow, Fraunces title, blurb (matches every settings page) ──
    Column {
        id: head
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s6
        }
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "\u529b"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "SYSTEM"; color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: "GPU"; color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: "Which GPU Ryoku renders on, and the optional GPU-passthrough stack that binds the discrete GPU to vfio so a virtual machine can own it. Running the VM lives in ryovm; this page is graphics hardware only."
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // marginalia in the head's right margin, dressing the dead space beside the title. Ink only.
    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s1
        kana: "描画"
        index: "02"; label: "SYSTEM"
        glyph: "asanoha"; glyph2: "meander"
    }

    // ── content: specimen rail on the left, scrolling dossier on the right ──
    Item {
        id: below
        anchors {
            left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom
            leftMargin: Tokens.s6; rightMargin: Tokens.s6; topMargin: Tokens.s5; bottomMargin: Tokens.s6
        }

        // left rail: the specimen card, then a failure column if the probe died.
        Column {
            id: rail
            anchors.left: parent.left; anchors.top: parent.top
            width: Math.min(parent.width * 0.36, 380)
            spacing: Tokens.s4

            GpuSpecimen {
                width: parent.width
                caps: pg.caps
                failed: pg.capsError !== ""
            }

            // caps probe failed (detector missing, wedged, or timed out): surface
            // it with a retry instead of leaving the page stuck on "Checking...".
            Column {
                visible: pg.capsError !== ""
                width: parent.width
                spacing: Tokens.s3
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    // an error is inverted text and the word (DESIGN.md section 1);
                    // with no red to raise the alarm, it takes the brightest ink.
                    text: "Couldn't read your graphics hardware."
                    color: Tokens.ink; font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: pg.capsError
                    color: Tokens.inkMuted; font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                }
                Btn {
                    text: "Retry"
                    primary: true
                    onAct: pg.reload()
                }
            }
        }

        // right column: the render mode and the passthrough dossier.
        Flickable {
            id: gfx
            anchors {
                left: rail.right; right: parent.right; top: parent.top; bottom: renderDecor.top
                leftMargin: Tokens.s6; bottomMargin: Tokens.s5
            }
            contentWidth: width
            contentHeight: gfxCol.height + Tokens.s5
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

            Column {
                id: gfxCol
                width: Math.min(gfx.width - Tokens.s3, 640)   // reserve a scroll lane
                spacing: Tokens.s5

                // ── RYOKU RENDERS ON: the graphics-mode selector ──
                Column {
                    width: parent.width
                    spacing: Tokens.s3

                    SectionHead { width: parent.width; label: "RYOKU RENDERS ON" }

                    Column {
                        width: parent.width
                        spacing: Tokens.s2
                        Text {
                            text: "Graphics mode"
                            color: Tokens.ink; font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow
                        }
                        Seg {
                            options: ["Hybrid", "Performance", "Passthrough"]
                            current: pg.modeLabel(pg.mode)
                            // request-then-re-read: the segment only moves after the
                            // backend confirms via reload, never optimistically.
                            onChose: (label) => pg.setMode(label.toLowerCase())
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: pg.mode === "hybrid"
                            ? "Hybrid keeps the built-in GPU primary for battery; apps can still use " + pg.dgpuName + " on demand."
                            : (pg.mode === "performance"
                                ? "Performance pins " + pg.dgpuName + " as primary: fastest, more power draw."
                                : "Passthrough runs the desktop on the built-in GPU so " + pg.dgpuName + " is free for a VM.")
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }
                    Text {
                        width: parent.width
                        text: "A change takes effect on your next login."
                        color: Tokens.inkFaint; font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }

                    // mode-warning banner: the raw stderr from a refused mode set
                    // (e.g. the long BIOS/MUX message). Never auto-dismisses.
                    Rectangle {
                        visible: pg.modeWarn !== ""
                        width: parent.width
                        height: modeWarnText.implicitHeight + Tokens.s3 * 2
                        radius: Tokens.radius
                        color: "transparent"
                        border.width: Tokens.border
                        border.color: Tokens.lineStrong
                        Text {
                            id: modeWarnText
                            anchors {
                                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                leftMargin: Tokens.s3; rightMargin: Tokens.s3
                            }
                            text: pg.modeWarn
                            color: Tokens.ink; wrapMode: Text.WordWrap
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                        }
                    }
                }

                // ── GPU PASSTHROUGH · ADVANCED ──
                Column {
                    width: parent.width
                    spacing: Tokens.s3

                    SectionHead { width: parent.width; label: "GPU PASSTHROUGH \u00b7 ADVANCED" }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Free " + pg.dgpuName + " from the desktop and bind it to vfio so a virtual machine can own it for near-native performance. This sets up the host only; you run the VM yourself (libvirt + Looking Glass). Everyday VMs in ryovm need none of this."
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }

                    // status line: a filled dot for ready, a hollow ring for
                    // attention, an inkMuted dot while checking; the verdict copy
                    // and the ink ramp carry severity in place of colour.
                    Row {
                        width: parent.width
                        spacing: Tokens.s2
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            anchors.top: parent.top; anchors.topMargin: 5
                            color: pg.ptPending ? Tokens.inkMuted : (pg.ptOk ? Tokens.ink : "transparent")
                            border.width: (!pg.ptPending && !pg.ptOk) ? Tokens.border : 0
                            border.color: Tokens.ink
                        }
                        Text {
                            width: parent.width - 7 - Tokens.s2
                            wrapMode: Text.WordWrap
                            text: pg.ptText
                            color: pg.ptPending ? Tokens.inkMuted : (pg.ptOk ? Tokens.inkDim : Tokens.ink)
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.weight: Font.Medium
                        }
                    }

                    // enabled: nothing to do but tear it down.
                    Btn {
                        visible: pg.caps.enabled === true
                        text: "Disable passthrough"
                        onAct: pg.act(["ryoku-hub", "gpu", "apply", "disable"])
                    }

                    // not enabled + capable: review, then enable in a terminal.
                    Btn {
                        visible: pg.caps.enabled !== true && pg.caps.verdict !== "incapable" && !pg.planning && !pg.enabling
                        text: "Review changes"
                        onAct: pg.reviewEnable()
                    }

                    // plan console: the raw --dry-run output (package list, write
                    // lines, AUR notices) -- file-truth, so mono.
                    Rectangle {
                        visible: pg.planning
                        width: parent.width
                        height: 220
                        radius: Tokens.radius
                        color: Tokens.tint5
                        border.width: Tokens.border
                        border.color: Tokens.line
                        clip: true
                        Flickable {
                            id: planFlick
                            anchors.fill: parent
                            anchors.margins: Tokens.s3
                            contentWidth: width
                            contentHeight: planView.height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }
                            Text {
                                id: planView
                                width: planFlick.width
                                text: pg.planText
                                color: Tokens.inkDim; font.family: Tokens.mono
                                font.pixelSize: Tokens.fMicro
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                    Row {
                        visible: pg.planning
                        spacing: Tokens.s2
                        Btn {
                            text: "Enable passthrough"
                            primary: true
                            onAct: pg.enableInTerminal()
                        }
                        Btn { text: "Close"; onAct: { pg.planning = false; pg.planText = ""; } }
                    }

                    // enable running in a terminal: prompt a recheck.
                    Text {
                        visible: pg.enabling
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Setting up in a terminal window (it builds a kernel module, so it can take a few minutes). Click Recheck when it finishes."
                        color: Tokens.inkMuted; font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }
                    Btn {
                        visible: pg.enabling
                        text: "Recheck"
                        onAct: pg.recheck()
                    }

                    // disclosure: the full readiness dossier, collapsed by default.
                    Item {
                        width: parent.width
                        height: 22
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s2
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: ">"
                                rotation: pg.showChecks ? 90 : 0
                                color: chkHov.hovered ? Tokens.ink : Tokens.inkMuted
                                font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                                Behavior on rotation { NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: pg.showChecks ? "Hide readiness checks" : "Readiness checks"
                                color: chkHov.hovered ? Tokens.ink : Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fMicro
                                font.weight: Font.Medium
                                font.letterSpacing: Tokens.trackLabel
                            }
                        }
                        HoverHandler { id: chkHov; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: pg.showChecks = !pg.showChecks }
                    }
                    Item {
                        width: parent.width
                        clip: true
                        height: pg.showChecks ? checksCol.implicitHeight : 0
                        visible: height > 0.5
                        opacity: pg.showChecks ? 1 : 0
                        Behavior on height { NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease } }
                        Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
                        Column {
                            id: checksCol
                            width: parent.width
                            spacing: 0
                            Repeater {
                                model: pg.caps.checks || []
                                delegate: CheckRow {
                                    required property var modelData
                                    width: parent.width
                                    check: modelData
                                }
                            }
                        }
                    }
                }
            }
        }

        // action error banner: refused mode switch, failed enable, etc. An error
        // is inverted text and the word (DESIGN.md section 1): the tag flips to
        // bone, the raw message reads in ink. Dismissed by tapping the banner.
        Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            visible: pg.actionError !== ""
            height: Math.min(errText.implicitHeight + Tokens.s3 * 2, 110)
            radius: Tokens.radius
            color: Tokens.paper
            border.width: Tokens.border
            border.color: Tokens.lineStrong
            clip: true

            Rectangle {
                id: errTag
                anchors.left: parent.left; anchors.top: parent.top
                anchors.leftMargin: Tokens.s3; anchors.topMargin: Tokens.s3
                width: errTagLab.width + Tokens.s2 * 2
                height: 18
                radius: Tokens.radius
                color: Tokens.bone
                Text {
                    id: errTagLab
                    anchors.centerIn: parent
                    text: "ERROR"
                    color: Tokens.inkOnBone
                    font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                }
            }
            Text {
                id: errText
                anchors {
                    left: errTag.right; right: parent.right; top: parent.top
                    leftMargin: Tokens.s3; rightMargin: Tokens.s3; topMargin: Tokens.s3
                }
                text: pg.actionError
                color: Tokens.ink; wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 4
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
            }
            TapHandler { onTapped: pg.actionError = "" }
        }

        // the GPU's output, full width across the foot: a shaded torus knot
        // turning, a real-time render baked to the house dither.
        Decor {
            id: renderDecor
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.min(300, below.height - rail.height - Tokens.s5)
            images: ["render.gif", "torus.gif", "sphere.gif", "cube.gif", "spring.gif"]
            title: "\u63cf\u753b"; sub: "\u4e09\u6b21\u5143"
            tate: "\u5149\u3068\u4e09\u89d2\u5f62"
            caption: "The desktop, drawn in real time: geometry, light, and a few million triangles a frame."
            readout: ["SHADING|per-pixel", "GEOMETRY|instanced", "SURFACES|composited", "REFRESH|adaptive"]
            code: "GPU-02"; seal: "\u63cf"; boxId: "gpu.render"; seed: 0; ditherFreq: 1.0
        }
    }
}
