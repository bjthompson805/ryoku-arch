pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// PALETTE lane: edits the scheme wallust extracts. Tone, character, backend,
// colorspace, palette saturation, threshold, contrast-safe, and (video) the
// sampled frame second. Persisted to ryowalls.json immediately, so every cell
// carries the ryowalls source tag. There is no Advanced drawer: grouping by
// meaning is the disclosure a twelve-cell sheet needs.
Item {
    id: sheet

    readonly property bool videoMode: !!Wallhaven.selected && Wallhaven.selectedVideo

    readonly property var presets: [
        { label: "Muted Dark",   tone: "dark",  character: "pastel",  cs: "lab",      sat: 0 },
        { label: "Vivid Dark",   tone: "dark",  character: "vivid",   cs: "lch",      sat: 85 },
        { label: "Salient Pop",  tone: "dark",  character: "salient", cs: "salience", sat: 70 },
        { label: "Pastel Light", tone: "light", character: "pastel",  cs: "lab",      sat: 0 }
    ]
    readonly property var backendMap: [
        { k: "", l: "Auto" }, { k: "full", l: "Precise" }, { k: "kmeans", l: "Diverse" }, { k: "wal", l: "Pywal" }
    ]
    readonly property var csMap: [
        { k: "", l: "Auto" }, { k: "lab", l: "Lab" }, { k: "lch", l: "Lch" }, { k: "salience", l: "Salient" }
    ]

    function set(key, val) { Wallhaven.settings[key] = val; Wallhaven.saveSettings(); }
    function applyPreset(p) {
        var c = Wallhaven.settings;
        c.tone = p.tone; c.character = p.character; c.colorspace = p.cs;
        c.backend = ""; c.saturation = p.sat; c.threshold = 0; c.contrast = false;
        Wallhaven.saveSettings();
    }
    function presetLabel() {
        var c = Wallhaven.settings;
        for (var i = 0; i < presets.length; i++) {
            var p = presets[i];
            if (c.tone === p.tone && c.character === p.character && c.colorspace === p.cs && c.saturation === p.sat)
                return p.label;
        }
        return "";
    }
    function toneLabel() { return Wallhaven.settings.tone === "light" ? "Light" : "Dark"; }
    function charLabel() { var c = Wallhaven.settings.character; return c.charAt(0).toUpperCase() + c.slice(1); }
    function labelFor(map, key) { for (var i = 0; i < map.length; i++) if (map[i].k === key) return map[i].l; return map[0].l; }
    function keyFor(map, label) { for (var i = 0; i < map.length; i++) if (map[i].l === label) return map[i].k; return ""; }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollRail {}

        Column {
            id: col
            width: flick.width
            spacing: Tokens.s5

            Text {
                width: parent.width
                visible: !Wallhaven.selected
                wrapMode: Text.WordWrap
                text: "Pick a wallpaper to tune its palette."
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: 12
            }

            // ── PRESETS: macros. picking one sets the keys; the lit state derives.
            SheetSection {
                id: presetSec
                width: parent.width
                title: "PRESETS"
                Cell {
                    width: presetSec.span(10)
                    height: 2 * Tokens.cellH + Tokens.s2
                    label: "Preset"
                    value: ""
                    block: true
                    source: "ryowalls.json"
                    changed: Wallhaven.tuned
                    desc: "A ready-made scheme. Sets tone, character and colorspace at once."
                    Chips {
                        width: parent.width
                        options: sheet.presets.map(p => p.label)
                        current: sheet.presetLabel()
                        onChose: (k) => { var p = sheet.presets.find(x => x.label === k); if (p) sheet.applyPreset(p); }
                    }
                }
            }

            // ── MOOD: the two axes wallust reads as light/dark and character ───
            SheetSection {
                id: moodSec
                width: parent.width
                title: "MOOD"
                Cell {
                    width: moodSec.span(4)
                    label: "Tone"
                    source: "ryowalls.json"
                    value: sheet.toneLabel()
                    def: "Dark"
                    desc: "A light or a dark scheme."
                    controlWidth: Spans.inlineWidth("seg", 2, width)
                    Seg {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        options: ["Dark", "Light"]
                        current: sheet.toneLabel()
                        onChose: (k) => sheet.set("tone", k.toLowerCase())
                    }
                }
                Cell {
                    width: moodSec.span(8)
                    label: "Character"
                    source: "ryowalls.json"
                    value: sheet.charLabel()
                    def: "Natural"
                    desc: "How wallust weights the extracted colours."
                    controlWidth: Spans.inlineWidth("seg", 4, width)
                    Seg {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        options: ["Natural", "Vivid", "Pastel", "Salient"]
                        current: sheet.charLabel()
                        onChose: (k) => sheet.set("character", k.toLowerCase())
                    }
                }
            }

            // ── COLOUR: the finer wallust controls, and the reset ──────────────
            SheetSection {
                id: colourSec
                width: parent.width
                title: "COLOUR"
                action: Btn {
                    text: "RESET TO DEFAULT"
                    armed: Wallhaven.tuned
                    onAct: Wallhaven.resetTune()
                }
                Cell {
                    width: colourSec.span(6)
                    label: "Saturation"
                    source: "ryowalls.json"
                    // AUTO is the value at zero: wallust decides for you.
                    value: Wallhaven.settings.saturation === 0 ? "AUTO" : "" + Wallhaven.settings.saturation
                    def: "AUTO"
                    desc: "Push or pull every extracted colour's saturation."
                    controlWidth: Spans.inlineWidth("slid", 0, width)
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 100
                        value: Wallhaven.settings.saturation
                        onModified: (v) => sheet.set("saturation", v)
                    }
                }
                Cell {
                    width: colourSec.span(6)
                    label: "Threshold"
                    source: "ryowalls.json"
                    value: Wallhaven.settings.threshold === 0 ? "AUTO" : "" + Wallhaven.settings.threshold
                    def: "AUTO"
                    desc: "How aggressively near-duplicate colours are merged."
                    controlWidth: Spans.inlineWidth("slid", 0, width)
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 100
                        value: Wallhaven.settings.threshold
                        onModified: (v) => sheet.set("threshold", v)
                    }
                }
                Cell {
                    width: colourSec.span(4)
                    label: "Contrast-safe"
                    source: "ryowalls.json"
                    value: Wallhaven.settings.contrast ? "ON" : "OFF"
                    def: "OFF"
                    desc: "Force legible text contrast on every surface."
                    controlWidth: Spans.inlineWidth("sw", 0, width)
                    Sw {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        on: Wallhaven.settings.contrast
                        onToggled: (v) => sheet.set("contrast", v)
                    }
                }
                Cell {
                    width: colourSec.span(4)
                    label: "Backend"
                    source: "ryowalls.json"
                    value: sheet.labelFor(sheet.backendMap, Wallhaven.settings.backend)
                    def: "Auto"
                    desc: "The extraction algorithm wallust runs."
                    controlWidth: Spans.inlineWidth("seg", 4, width)
                    Seg {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        options: sheet.backendMap.map(m => m.l)
                        current: sheet.labelFor(sheet.backendMap, Wallhaven.settings.backend)
                        onChose: (k) => sheet.set("backend", sheet.keyFor(sheet.backendMap, k))
                    }
                }
                Cell {
                    width: colourSec.span(4)
                    label: "Colorspace"
                    source: "ryowalls.json"
                    value: sheet.labelFor(sheet.csMap, Wallhaven.settings.colorspace)
                    def: "Auto"
                    desc: "The space colours are compared in."
                    controlWidth: Spans.inlineWidth("seg", 4, width)
                    Seg {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        options: sheet.csMap.map(m => m.l)
                        current: sheet.labelFor(sheet.csMap, Wallhaven.settings.colorspace)
                        onChose: (k) => sheet.set("colorspace", sheet.keyFor(sheet.csMap, k))
                    }
                }
            }

            // ── SAMPLING: which second of a clip wallust reads (video picks) ───
            SheetSection {
                id: sampleSec
                width: parent.width
                title: "SAMPLING"
                visible: sheet.videoMode
                Cell {
                    width: sampleSec.span(6)
                    label: "Frame"
                    source: "ryowalls.json"
                    value: Wallhaven.settings.frame.toFixed(1) + "s"
                    def: "1.0s"
                    desc: "The second of the clip wallust samples for colour."
                    controlWidth: Spans.inlineWidth("slid", 0, width)
                    // the module Slid seats integers, so scrub in half-second steps.
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 20
                        value: Math.round(Wallhaven.settings.frame * 2)
                        onModified: (v) => Wallhaven.retuneFrame(v / 2)
                    }
                }
            }

            Item { width: 1; height: Tokens.s2 }
        }
    }
}
