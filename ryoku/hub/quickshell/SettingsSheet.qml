import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

// Renders a page from its schema. A setting is a row of data; where it lands
// and what draws it are decided by Spans and its kind, so adding one is an
// edit to the schema and nothing else.
//
// The draft object holds live values and is the page's own; this only reads it
// and reports edits back. Nothing here writes a file.
Item {
    id: sheet

    property var schema: []          // [{ tab, group, key, label, desc, ctl, src, opts, lo, hi, unit, pct }]
    property var draft: null         // the page's live values
    property var defaults: ({})      // factory values, for the struck default
    property string tab: ""
    property string query: ""

    signal edited(string key, var value)

    readonly property var rows: {
        var q = query.toLowerCase();
        return schema.filter(function (r) {
            if (r.tab !== sheet.tab && query === "") return false;
            if (query === "") return true;
            return (r.label + " " + (r.desc || "") + " " + r.key).toLowerCase().indexOf(q) >= 0;
        });
    }
    readonly property var groups: {
        var g = [];
        for (var i = 0; i < rows.length; i++)
            if (g.indexOf(rows[i].group) < 0) g.push(rows[i].group);
        return g;
    }

    function val(r) {
        if (!draft) return "";
        var v = draft[r.key];
        return v === undefined ? "" : v;
    }
    function shown(r) {
        var v = val(r);
        if (r.ctl === "sw") return v ? "ON" : "OFF";
        if (r.ctl === "slid" && r.pct) return String(Math.round(v * 100));
        if (r.ctl === "multi") return String((v || []).length);
        if (r.ctl === "color") return String(v).toUpperCase();
        return String(v);
    }
    function shownDef(r) {
        var d = defaults[r.key];
        if (d === undefined) return "";
        if (r.ctl === "sw") return d ? "ON" : "OFF";
        if (r.ctl === "slid" && r.pct) return String(Math.round(d * 100));
        if (r.ctl === "multi") return String((d || []).length);
        return String(d);
    }
    function isChanged(r) {
        var v = val(r), d = defaults[r.key];
        if (d === undefined) return false;
        if (r.ctl === "multi") return JSON.stringify(v || []) !== JSON.stringify(d || []);
        return v !== d;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + Tokens.s5
        clip: true
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            width: flick.width - 14
            spacing: Tokens.s5

            Repeater {
                model: sheet.groups
                Section {
                    id: sect
                    required property string modelData
                    width: col.width
                    title: modelData === "" ? "OTHER" : modelData

                    // bento: pack this group's declared spans into flush rows,
                    // so no row ends in dead space. minSpan keeps a cell usable
                    // on a narrow sheet.
                    readonly property var groupRows: sheet.rows.filter(function (r) { return r.group === sect.modelData })
                    readonly property int minSpan: {
                        for (var n = 1; n <= Spans.cols; n++)
                            if (n * colWidth + (n - 1) * gutter >= 290) return n;
                        return Spans.cols;
                    }
                    readonly property var packed: Spans.pack(
                        groupRows.map(function (r) { return (r.ctl === "seg" && (r.opts || []).length >= 3) ? Spans.cols : Spans.of(r.ctl, (r.opts || []).length); }),
                        minSpan)

                    Repeater {
                        model: sect.groupRows
                        Cell {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var r: modelData
                            readonly property int optCount: (r.opts || []).length

                            width: sect.span(sect.packed[index] || 4)
                            height: neededHeight
                            block: Spans.isBlock(r.ctl) || (r.ctl === "seg" && cell.optCount >= 3)
                            footH: (r.ctl === "pick" || r.ctl === "text") ? 34 : 0
                            controlWidth: Spans.inlineWidth(r.ctl, optCount, width)

                            label: r.label
                            desc: r.desc || ""
                            unit: r.pct ? "%" : (r.unit || "")
                            value: (r.ctl === "text" || r.ctl === "seg") ? "" : sheet.shown(r)
                            def: sheet.shownDef(r)
                            changed: sheet.isChanged(r)
                            source: r.src + ".json"

                            Loader {
                                anchors.fill: parent
                                sourceComponent: {
                                    switch (cell.r.ctl) {
                                    case "sw": return swC;
                                    case "step": return stepC;
                                    case "slid": return slidC;
                                    case "seg": return segC;
                                    case "chips": return chipsC;
                                    case "multi": return multiC;
                                    case "pick": return pickC;
                                    case "gallery": return galleryC;
                                    default: return textC;
                                    }
                                }
                            }

                            Component {
                                id: swC
                                Sw {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    on: !!sheet.val(cell.r)
                                    onToggled: (v) => sheet.edited(cell.r.key, v)
                                }
                            }
                            Component {
                                id: stepC
                                Step {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: Number(sheet.val(cell.r)) || 0
                                    from: Number(cell.r.lo) || 0
                                    to: Number(cell.r.hi) || 100
                                    onModified: (v) => sheet.edited(cell.r.key, v)
                                }
                            }
                            Component {
                                id: slidC
                                Slid {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(cell.width * 0.42)
                                    value: Number(sheet.val(cell.r)) || 0
                                    from: Number(cell.r.lo) || 0
                                    to: Number(cell.r.hi) || 1
                                    onModified: (v) => sheet.edited(cell.r.key, v)
                                }
                            }
                            Component {
                                id: segC
                                Seg {
                                    anchors.right: cell.block ? undefined : parent.right
                                    anchors.left: cell.block ? parent.left : undefined
                                    anchors.verticalCenter: parent.verticalCenter
                                    options: cell.r.opts
                                    current: String(sheet.val(cell.r))
                                    onChose: (k) => sheet.edited(cell.r.key, k)
                                }
                            }
                            Component {
                                id: chipsC
                                Chips {
                                    anchors.fill: parent
                                    options: cell.r.opts
                                    current: String(sheet.val(cell.r))
                                    onChose: (k) => sheet.edited(cell.r.key, k)
                                }
                            }
                            Component {
                                id: multiC
                                Multi {
                                    anchors.fill: parent
                                    options: cell.r.opts
                                    chosen: sheet.val(cell.r) || []
                                    onToggled: (k) => {
                                        var l = (sheet.val(cell.r) || []).slice();
                                        var i = l.indexOf(k);
                                        if (i >= 0) l.splice(i, 1); else l.push(k);
                                        sheet.edited(cell.r.key, l);
                                    }
                                }
                            }
                            Component {
                                id: galleryC
                                Gallery {
                                    anchors.fill: parent
                                    options: Silhouette.skins
                                    current: String(sheet.val(cell.r))
                                    onChose: (k) => sheet.edited(cell.r.key, k)
                                }
                            }
                            Component {
                                id: pickC
                                PickBar {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    value: String(sheet.val(cell.r))
                                    count: cell.optCount
                                    onOpened: sheet.openPick(cell.r)
                                }
                            }
                            Component {
                                id: textC
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: Tokens.radius
                                    border.width: ti.activeFocus ? 2 : Tokens.border
                                    border.color: ti.activeFocus ? Tokens.ink : Tokens.line
                                    TextInput {
                                        id: ti
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: Text.AlignVCenter
                                        clip: true
                                        // show the head of a long value at rest, not
                                        // a scrolled-to-the-cursor tail.
                                        autoScroll: activeFocus
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: 12
                                        selectByMouse: true
                                        text: String(sheet.val(cell.r))
                                        onEditingFinished: sheet.edited(cell.r.key, text)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    signal pickRequested(var row)
    function openPick(r) { pickRequested(r) }

    Column {
        anchors.centerIn: parent
        visible: sheet.rows.length === 0
        spacing: Tokens.s2
        Text {
            text: "NO MATCH"
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fRow
            font.letterSpacing: 2
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Text {
            text: "nothing here matches “" + sheet.query + "”"
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
