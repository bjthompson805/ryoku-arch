pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Lockscreen (DESIGN.md section 8, DESKTOP). Choose the skin the lock and
// sign-in screens wear, from the qylock themes installed on disk. This is not a
// settings sheet: the one "key" is a visual choice among tiles, so it is a
// gallery, drawn bespoke. Data is fetched live from `ryoku-hub lock list` so a
// hand-dropped skin shows up without a Ryoku release; picking one applies
// immediately via `ryoku-hub lock set <slug>` (which also reskins the SDDM
// greeter, so it prompts for the password through pkexec). There is no draft
// and no Save, so the shell hides its side panel and action bar; this full-bleed
// page owns the whole content region and draws its own head, states and grid.
// The pick only swaps the look, never the login. Every value is a Token; the
// live skin thumbnail is the one permitted specimen of colour (a lock preview),
// everything else is paper and ink.
Item {
    id: pg

    property var hub
    // A full-bleed page draws the whole content region itself: the shell hides
    // its side panel and global action bar and keeps only the rail.
    readonly property bool fullBleed: true

    // ── state (backend unchanged from the old page) ─────────────────────────
    property var skins: []
    property string active: ""
    property bool loading: true
    property bool loadFailed: false
    property string pendingSlug: ""   // "" idle, else the slug being applied
    property string error: ""
    property bool online: true
    property bool refreshing: false     // the Refresh button is fetching
    property string status: ""          // transient cue under the title
    property bool cacheWarmed: false    // the background preview warm ran this session
    property bool pendingInstall: false // the in-flight apply is a download+install
    property string listMode: ""        // "" normal · "refresh" button · "silent" post-warm

    // the in-session lock preview script; running it locks the screen with the
    // named skin so the user sees the real thing (an action, not a pane).
    readonly property string lockSh: Quickshell.env("HOME") + "/.local/share/quickshell-lockscreen/lock.sh"
    // the rail's search box drives this; skins filter live against it.
    readonly property string query: (pg.hub && pg.hub.query) ? ("" + pg.hub.query) : ""

    // responsive column count, same breakpoints as the old bento grid.
    readonly property int cols: width >= 1320 ? 4 : (width >= 980 ? 3 : (width >= 640 ? 2 : 1))

    // vector glyph paths (viewBox 24), inlined so the page carries no icon
    // dependency of its own.
    readonly property string pLock: "M5 11h14a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1H5a1 1 0 0 1 -1 -1v-8a1 1 0 0 1 1 -1z M8 11V7.5a4 4 0 0 1 8 0V11 M12 15v2.5"
    readonly property string pPlay: "M8 5.4l11 6.6 -11 6.6z"
    readonly property string pChevron: "M6 9.5l6 6 6 -6"
    readonly property string pRefresh: "M21 12a9 9 0 1 1 -2.6 -6.4 M21 3v5h-5"

    Component.onCompleted: pg.reload()

    function reload() {
        pg.listMode = "";
        pg.loading = pg.skins.length === 0; // full spinner only when nothing is shown yet
        pg.loadFailed = false;
        listProc.command = ["ryoku-hub", "lock", "catalog"];
        listProc.running = true;
    }
    // the Refresh button: pull a fresh upstream tree (new/removed designs) with a
    // visible cue; the grid stays put and a short status reports the delta.
    function refresh() {
        if (pg.refreshing || pg.pendingSlug !== "")
            return;
        pg.error = "";
        pg.listMode = "refresh";
        pg.refreshing = true;
        pg.status = "Fetching designs\u2026";
        listProc.command = ["ryoku-hub", "lock", "catalog", "--refresh"];
        listProc.running = true;
    }
    // fire-and-apply: a no-op if the tile is active or an apply is in flight. an
    // uninstalled catalogue skin installs (downloads) then activates; an installed
    // one just activates. no draft, no Save.
    function select(skin) {
        if (skin.slug === pg.active || pg.pendingSlug !== "")
            return;
        pg.error = "";
        pg.pendingSlug = skin.slug;
        pg.pendingInstall = !skin.installed;
        actProc.command = skin.installed
            ? ["ryoku-hub", "lock", "set", skin.slug]
            : ["ryoku-hub", "lock", "install", skin.slug];
        actProc.running = true;
    }
    function preview(slug) {
        Quickshell.execDetached([pg.lockSh, slug]);
    }

    // live filter: name, theme, slug, tags and copy all match the rail query.
    readonly property var shown: {
        var q = pg.query.trim().toLowerCase();
        if (q === "")
            return pg.skins;
        var out = [];
        for (var i = 0; i < pg.skins.length; i++) {
            var s = pg.skins[i];
            var hay = ((s.name || "") + " " + (s.theme || "") + " " + (s.slug || "") + " "
                + (s.summary || "") + " " + (s.blurb || "") + " " + ((s.tags || []).join(" "))).toLowerCase();
            if (hay.indexOf(q) !== -1)
                out.push(s);
        }
        return out;
    }

    // greedy masonry like the old grid: each tile drops into the shortest
    // column, its height estimated from the hero plus blurb length so the
    // columns stay balanced.
    function buildColumns(list, n) {
        var c = [], h = [], i;
        for (i = 0; i < n; i++) { c.push([]); h.push(0); }
        for (i = 0; i < list.length; i++) {
            var est = 300 + Math.ceil(((list[i].blurb || "").length) / 30) * 16;
            var min = 0;
            for (var j = 1; j < n; j++)
                if (h[j] < h[min]) min = j;
            c[min].push(list[i]);
            h[min] += est + Tokens.s3;
        }
        return c;
    }
    readonly property var grouped: pg.buildColumns(pg.shown, pg.cols)

    // ── data load (backend unchanged) ───────────────────────────────────────
    Process {
        id: listProc
        command: ["ryoku-hub", "lock", "catalog"]
        stdout: StdioCollector {
            onStreamFinished: {
                var prev = pg.skins.length;
                try {
                    var o = JSON.parse(this.text);
                    var ss = o.skins || [];
                    for (var i = 0; i < ss.length; i++)
                        ss[i].ordinal = i + 1;
                    pg.skins = ss;
                    pg.active = o.active || "";
                    pg.online = o.online !== false;
                    pg.loadFailed = ss.length === 0;
                } catch (e) {
                    pg.skins = [];
                    pg.loadFailed = true;
                    pg.online = false;
                }
                pg.loading = false;
                if (pg.listMode === "refresh") {
                    var delta = pg.skins.length - prev;
                    pg.status = pg.loadFailed ? "Couldn't reach qylock"
                        : (delta > 0 ? ("+" + delta + " new design" + (delta === 1 ? "" : "s"))
                        : (pg.online ? "Up to date" : "Offline \u2014 showing installed skins"));
                    pg.refreshing = false;
                    statusClear.restart();
                }
                // warm the preview cache after a fresh listing, but not after the
                // silent re-list the warm itself triggers (that would loop).
                if (pg.listMode !== "silent") {
                    cacheProc.command = ["ryoku-hub", "lock", "cache"];
                    cacheProc.running = true;
                }
                pg.listMode = "";
            }
        }
    }
    Process {
        id: actProc
        stderr: StdioCollector { id: actErr }
        onExited: (code) => {
            if (code !== 0)
                pg.error = (pg.pendingInstall ? "Couldn't install skin: " : "Couldn't switch skin: ") + (actErr.text.trim() || ("exit " + code));
            pg.pendingSlug = "";
            pg.pendingInstall = false;
            // re-list to pick up the new active + installed skin; no loading flash.
            pg.listMode = "";
            listProc.command = ["ryoku-hub", "lock", "catalog"];
            listProc.running = true;
        }
    }
    // warm the preview cache after a listing (missing + stale gifs). the Hub runs
    // it in the background so previews cache on first open and refresh over time;
    // the first warm silently re-lists so cached paths replace the remote URLs.
    Process {
        id: cacheProc
        stdout: StdioCollector { id: cacheOut }
        onExited: (code) => {
            var fetched = 0;
            try { fetched = (JSON.parse(cacheOut.text).fetched) || 0; } catch (e) {}
            if (fetched > 0 && !pg.cacheWarmed) {
                pg.cacheWarmed = true;
                pg.listMode = "silent";
                listProc.command = ["ryoku-hub", "lock", "catalog"];
                listProc.running = true;
            } else {
                pg.cacheWarmed = true;
            }
        }
    }
    Timer { id: statusClear; interval: 3500; onTriggered: pg.status = "" }

    // ── head: eyebrow, Fraunces title + refresh, blurb, error line ──────────
    Column {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.leftMargin: Tokens.s6; anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s6
        spacing: Tokens.s2

        Row {
            spacing: Tokens.s2
            Rectangle {
                width: 16; height: 1; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "力"; color: Tokens.ink; font.family: Tokens.jp
                font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "DESKTOP"; color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // title with its one utility action (rescan the installed skins) beside it.
        Item {
            width: parent.width
            height: title.height
            Text {
                id: title
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: "Lockscreen"; color: Tokens.ink
                font.family: Tokens.display; font.pixelSize: Tokens.fTitle
            }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.s2
                // transient cue: what the last refresh did ("+N new", "Up to date").
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pg.status !== ""
                    text: pg.status
                    color: Tokens.inkMuted; font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                }
                // spins only while a fetch is genuinely in flight.
                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: pg.refreshing
                    path: pg.pRefresh; size: 15; weight: 2; tint: Tokens.inkMuted
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: pg.refreshing
                    }
                }
                Btn {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pg.refreshing ? "FETCHING\u2026" : "REFRESH"
                    armed: pg.pendingSlug === "" && !pg.refreshing
                    onAct: pg.refresh()
                }
            }
        }

        Text {
            width: Math.min(parent.width, 720)
            // the load-bearing caveat, kept verbatim: it only swaps the look,
            // never your login.
            text: "Pick the skin your lock and sign-in screens wear. It only swaps the look, never your login; applying reskins the sign-in screen too, so you will be asked for your password."
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
        Text {
            width: Math.min(parent.width, 720)
            visible: pg.error !== ""
            // no red on the sheet: an error is the brightest ink and the word.
            text: pg.error
            color: Tokens.ink; font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall; font.weight: Font.Medium; wrapMode: Text.WordWrap
        }
    }

    // marginalia dressing the head's empty right margin (eyebrow line). Ink only.
    Marginalia {
        anchors { right: parent.right; top: head.top }
        anchors.rightMargin: Tokens.s6; anchors.topMargin: Tokens.s1
        kana: "施錠"
        index: "03"; label: "DESKTOP"
        glyph: "column"; glyph2: "wave"
    }

    // ── loading / empty-or-failed state ─────────────────────────────────────
    Column {
        anchors.centerIn: parent
        visible: pg.loading || pg.loadFailed
        spacing: Tokens.s3
        width: Math.min(pg.width - Tokens.s6 * 2, 420)

        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pg.loading
            path: pg.pRefresh; size: 26; weight: 2; tint: Tokens.inkMuted
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: pg.loading
            }
        }
        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pg.loadFailed
            path: pg.pLock; size: 44; tint: Tokens.inkFaint
        }
        Text {
            width: parent.width
            visible: pg.loadFailed
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: "No lock skins found. Install qylock to add some."
            color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: Tokens.fBody
        }
        Btn {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: pg.loadFailed
            text: "TRY AGAIN"
            onAct: pg.reload()
        }
    }

    // ── no-matches state (a search that filtered everything out) ────────────
    Text {
        anchors.centerIn: parent
        visible: !pg.loading && !pg.loadFailed && pg.shown.length === 0 && pg.query.trim() !== ""
        text: "No skins match your search."
        color: Tokens.inkMuted; font.family: Tokens.ui; font.pixelSize: Tokens.fBody
    }

    // ── the gallery grid ────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: parent.bottom
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
            topMargin: Tokens.s4; bottomMargin: Tokens.s6
        }
        visible: !pg.loading && !pg.loadFailed && pg.shown.length > 0
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease } }
        contentWidth: width
        contentHeight: masonry.implicitHeight + Tokens.s4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Row {
            id: masonry
            width: flick.width - Tokens.s3   // reserve a lane for the scroll rail
            spacing: Tokens.s3

            Repeater {
                model: pg.cols
                delegate: Column {
                    id: column
                    required property int index
                    width: (masonry.width - (pg.cols - 1) * Tokens.s3) / pg.cols
                    spacing: Tokens.s3

                    Repeater {
                        model: pg.grouped[column.index] || []
                        delegate: LockTile {
                            required property var modelData
                            width: column.width
                            viewport: flick
                            skin: modelData
                            ordinal: modelData.ordinal || 0
                            active: modelData.slug === pg.active
                            installed: modelData.installed === true
                            busy: pg.pendingSlug === modelData.slug
                            installing: pg.pendingInstall && pg.pendingSlug === modelData.slug
                            onApplied: pg.select(modelData)
                            onPreviewed: pg.preview(modelData.slug)
                        }
                    }
                }
            }
        }
    }

    // ── a stroked vector glyph (viewBox 24), tint-able ──────────────────────
    component Glyph: Item {
        id: g
        property string path: ""
        property color tint: Tokens.inkMuted
        property real size: 20
        property real weight: 1.7
        implicitWidth: size
        implicitHeight: size
        Shape {
            anchors.centerIn: parent
            width: 24; height: 24
            scale: g.size / 24
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            ShapePath {
                strokeColor: g.tint
                strokeWidth: g.weight
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: g.path }
            }
        }
    }

    // ── one lock-skin tile ──────────────────────────────────────────────────
    // gallery grammar: selected = ink border + tint10 fill + corner dot. The
    // hero is the real skin thumbnail (a permitted colour specimen) when the
    // theme shipped a preview.gif, else a drawn lock silhouette.
    component LockTile: Rectangle {
        id: tile

        property var skin: ({})
        property int ordinal: 0
        property bool active: false
        property bool busy: false      // an apply is in flight for this skin
        property bool installed: false  // on disk already (catalogue skins install on pick)
        property bool installing: false // the in-flight apply is a download+install
        property Flickable viewport: null
        signal applied()
        signal previewed()

        // near-viewport test: map the tile into the Flickable and keep a 600px
        // margin so a remote thumbnail loads just before it scrolls in. reading
        // contentY/height makes the binding re-eval as the list scrolls.
        readonly property bool onScreen: {
            if (!viewport)
                return true;
            viewport.contentY;
            viewport.height;
            var top = tile.mapToItem(viewport, 0, 0).y;
            return top < viewport.height + 600 && top + tile.height > -600;
        }

        implicitHeight: body.implicitHeight + Tokens.s6
        radius: Tokens.radius
        color: tile.active ? Tokens.tint10 : (hover.hovered ? Tokens.tint5 : "transparent")
        border.width: Tokens.border
        border.color: tile.active ? Tokens.ink : (hover.hovered ? Tokens.lineStrong : Tokens.line)
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

        // gallery selection dot
        Rectangle {
            anchors { top: parent.top; right: parent.right; topMargin: Tokens.s2; rightMargin: Tokens.s2 }
            width: 5; height: 5; radius: 2.5
            color: Tokens.ink
            visible: tile.active
        }

        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: Tokens.s4
            spacing: 0

            // preview hero: 16:9 well over paper, hairline frame.
            Rectangle {
                id: media
                width: parent.width
                height: Math.round(width * 9 / 16)
                radius: Tokens.radius
                color: "transparent"
                border.width: Tokens.border
                border.color: (tile.active || hover.hovered) ? Tokens.ink : Tokens.line
                clip: true
                Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                // the real skin, animated. a lock thumbnail is a permitted
                // colour specimen, so it stays as shipped.
                AnimatedImage {
                    id: gif
                    anchors.fill: parent
                    anchors.margins: 1
                    source: tile.onScreen ? (tile.skin.preview || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    playing: tile.onScreen
                }

                // silhouette: shown while the thumbnail loads, or when the skin
                // shipped none.
                Glyph {
                    anchors.centerIn: parent
                    visible: gif.status !== AnimatedImage.Ready
                    path: pg.pLock; size: 34; tint: Tokens.inkMuted
                }

                // live-preview chip: locks the screen with this skin so the user
                // sees the real thing. only for an installed skin (the lock needs
                // its files on disk); a catalogue skin installs first, on pick.
                Rectangle {
                    anchors { left: parent.left; bottom: parent.bottom; margins: Tokens.s2 }
                    width: pvRow.implicitWidth + Tokens.s4
                    height: Tokens.ctlH
                    radius: Tokens.radius
                    visible: !tile.busy && tile.installed
                    // a scrim over a colour specimen to seat the label, not an
                    // app-surface fill.
                    color: Qt.rgba(0, 0, 0, 0.55)
                    border.width: Tokens.border
                    border.color: pvArea.containsMouse ? Tokens.ink : Tokens.lineStrong
                    opacity: (hover.hovered || pvArea.containsMouse) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
                    Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

                    Row {
                        id: pvRow
                        anchors.centerIn: parent
                        spacing: Tokens.s1
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            path: pg.pPlay; size: 11; weight: 2; tint: Tokens.ink
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Preview"; color: Tokens.ink
                            font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                            font.weight: Font.Medium
                        }
                    }
                    MouseArea {
                        id: pvArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.previewed()
                    }
                }

                // apply overlay
                Rectangle {
                    anchors.fill: parent
                    visible: tile.busy
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Column {
                        anchors.centerIn: parent
                        spacing: Tokens.s2
                        Glyph {
                            anchors.horizontalCenter: parent.horizontalCenter
                            path: pg.pRefresh; size: 22; weight: 2; tint: Tokens.ink
                            RotationAnimator on rotation {
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: tile.busy
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.installing ? "Installing\u2026" : "Applying\u2026"; color: Tokens.ink
                            font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.Medium
                        }
                    }
                }
            }

            Item { width: 1; height: Tokens.s4 }

            // ordinal + state badge
            Item {
                width: parent.width
                height: number.implicitHeight

                Text {
                    id: number
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    // an index is file-truth chrome, so mono.
                    text: (tile.ordinal < 10 ? "0" : "") + tile.ordinal
                    color: (tile.active || hover.hovered) ? Tokens.ink : Tokens.inkFaint
                    font.family: Tokens.mono; font.pixelSize: Tokens.fValue
                    Behavior on color { ColorAnimation { duration: Tokens.snap } }
                }
                // catalogue skin not yet on disk: picking it downloads then applies.
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    visible: !tile.installed && !tile.busy && !tile.active
                    text: "INSTALL" + (tile.skin.sizeKB > 0
                        ? "  \u00b7  " + (tile.skin.sizeKB >= 1024
                            ? (Math.round(tile.skin.sizeKB / 102.4) / 10 + " MB")
                            : (tile.skin.sizeKB + " KB"))
                        : "")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                    font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                }

                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: Tokens.s1 + 3
                    visible: tile.busy || tile.active
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3; color: Tokens.ink
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tile.busy ? (tile.installing ? "INSTALLING" : "APPLYING") : "ACTIVE"
                        color: Tokens.ink
                        font.family: Tokens.ui; font.pixelSize: 10
                        font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                    }
                }
            }

            // theme family tags
            Text {
                width: parent.width
                topPadding: Tokens.s3
                visible: (tile.skin.tags || []).length > 0
                text: (tile.skin.tags || []).join("  \u00b7  ")
                color: Tokens.inkFaint
                font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }

            // skin name
            Text {
                width: parent.width
                topPadding: (tile.skin.tags || []).length > 0 ? Tokens.s2 : Tokens.s3
                text: tile.skin.name || ""
                color: Tokens.ink
                font.family: Tokens.ui; font.pixelSize: Tokens.fRow; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            // one-line summary
            Text {
                width: parent.width
                topPadding: Tokens.s1
                visible: (tile.skin.summary || "") !== ""
                text: tile.skin.summary || ""
                color: Tokens.inkDim
                font.family: Tokens.ui; font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }

            // blurb, two lines
            Text {
                width: parent.width
                topPadding: Tokens.s2
                visible: (tile.skin.blurb || "") !== ""
                text: tile.skin.blurb || ""
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: 12
                lineHeight: 1.32
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        // hover affordance: this tile will apply on click.
        Glyph {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: Tokens.s4; bottomMargin: Tokens.s4 }
            path: pg.pChevron; size: 15; weight: 2; rotation: -90
            tint: Tokens.ink
            opacity: (hover.hovered && !tile.active && !tile.busy) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
        }

        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (!tile.active && !tile.busy) tile.applied() }
    }
}
