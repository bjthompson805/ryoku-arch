import QtQuick
import QtQuick.Effects

// Beautify: wrap a capture in a shareable frame -- background, padding, rounded
// corners, drop shadow. Opened from the toolbar's 力 button; the stage is grabbed
// and exported through the same wl-copy / save path as the annotator, so no new
// dependency and no separate app. Ryoku brand palette, sits inside the ryoshot
// overlay. The stage keeps its full logical size (a visual scale fits it to the
// screen) so grabToImage exports at full resolution regardless of the preview.
Item {
    id: beautify

    property string srcPath: ""
    property real s: 1

    signal copyRequested(string path)
    signal saveRequested(string path)
    signal closeRequested()

    readonly property string exportTmp: "/tmp/ryoshot-beautified.png"

    readonly property color glassBg: Qt.rgba(22 / 255, 17 / 255, 11 / 255, 0.94)
    readonly property color glassBorder: Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.14)
    readonly property color vermilion: "#e2342a"
    readonly property color idle: "#c7bfae"
    readonly property color sep: Qt.rgba(243 / 255, 237 / 255, 225 / 255, 0.14)

    // --- look state ---
    property int bgIndex: 0
    property int padIndex: 2
    property int radiusIndex: 1
    property int shadowIndex: 1
    property int ratioIndex: 0
    property int filterIndex: 0

    readonly property var backgrounds: [
        { "name": "Ember", "a": "#e2342a", "b": "#14120f" },
        { "name": "Dusk", "a": "#4b607f", "b": "#12161f" },
        { "name": "Teal", "a": "#3e6868", "b": "#0f1514" },
        { "name": "Sand", "a": "#cda47b", "b": "#7c5f42" },
        { "name": "Carbon", "a": "#241d15", "b": "#0e0d0b" },
        { "name": "Paper", "a": "#efe6d8", "b": "#cdbfae" }
    ]
    readonly property var pads: [0, 44, 88, 150]
    readonly property var radii: [0, 16, 30]
    readonly property var shadows: [
        { "blur": 0.0, "off": 0, "alpha": 0.0 },
        { "blur": 1.0, "off": 18, "alpha": 0.45 },
        { "blur": 1.0, "off": 34, "alpha": 0.62 }
    ]
    readonly property var ratios: [
        { "name": "Auto", "v": 0 },
        { "name": "16:9", "v": 1.7778 },
        { "name": "1:1", "v": 1 },
        { "name": "4:3", "v": 1.3333 },
        { "name": "3:2", "v": 1.5 }
    ]
    readonly property var filters: [
        { "name": "None", "b": 0.0, "c": 0.0, "s": 0.0 },
        { "name": "Vivid", "b": 0.0, "c": 0.16, "s": 0.4 },
        { "name": "Soft", "b": 0.05, "c": -0.08, "s": -0.12 },
        { "name": "Mono", "b": 0.0, "c": 0.06, "s": -1.0 }
    ]

    // --- computed stage geometry (full resolution) ---
    readonly property int pad: pads[padIndex]
    readonly property real natW: img.sourceSize.width > 0 ? img.sourceSize.width : 800
    readonly property real natH: img.sourceSize.height > 0 ? img.sourceSize.height : 500
    readonly property real minW: natW + 2 * pad
    readonly property real minH: natH + 2 * pad
    readonly property real ratioV: ratios[ratioIndex].v
    readonly property real fullW: ratioV <= 0 ? minW : (ratioV >= minW / minH ? minH * ratioV : minW)
    readonly property real fullH: ratioV <= 0 ? minH : (ratioV >= minW / minH ? minH : minW / ratioV)

    function exportStage(path, cb) {
        var scheduled = stage.grabToImage(function (r) {
            var ok = false;
            try { ok = r ? r.saveToFile(path) : false; }
            catch (e) { console.log("ryoshot: beautify grab failed: " + e); }
            if (cb) cb(ok);
        }, Qt.size(Math.round(beautify.fullW), Math.round(beautify.fullH)));
        if (!scheduled && cb) cb(false);
    }

    // dim the frozen capture behind
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.055, 0.051, 0.043, 0.96) }

    // --- preview area (everything above the control bar) ---
    Item {
        id: stageWrap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bar.top
        anchors.margins: 28 * beautify.s

        Item {
            id: stage
            width: beautify.fullW
            height: beautify.fullH
            anchors.centerIn: parent
            scale: Math.min((stageWrap.width) / beautify.fullW, (stageWrap.height) / beautify.fullH, 1)
            transformOrigin: Item.Center

            // background fill
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: beautify.backgrounds[beautify.bgIndex].a }
                    GradientStop { position: 1.0; color: beautify.backgrounds[beautify.bgIndex].b }
                }
            }

            // the capture, padded / rounded / shadowed
            Item {
                id: shotHolder
                anchors.centerIn: parent
                width: beautify.natW
                height: beautify.natH

                Image {
                    id: img
                    anchors.fill: parent
                    source: beautify.srcPath ? ("file://" + beautify.srcPath) : ""
                    cache: false
                    fillMode: Image.Stretch
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: beautify.radii[beautify.radiusIndex] > 0
                        maskSource: rounded
                        shadowEnabled: beautify.shadows[beautify.shadowIndex].alpha > 0
                        shadowColor: Qt.rgba(0, 0, 0, beautify.shadows[beautify.shadowIndex].alpha)
                        shadowBlur: beautify.shadows[beautify.shadowIndex].blur
                        shadowVerticalOffset: beautify.shadows[beautify.shadowIndex].off
                        brightness: beautify.filters[beautify.filterIndex].b
                        contrast: beautify.filters[beautify.filterIndex].c
                        saturation: beautify.filters[beautify.filterIndex].s
                        autoPaddingEnabled: true
                    }
                }
                Rectangle {
                    id: rounded
                    anchors.fill: parent
                    radius: beautify.radii[beautify.radiusIndex]
                    visible: false
                    layer.enabled: true
                }
            }
        }
    }

    // --- control bar ---
    Rectangle {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24 * beautify.s
        radius: 14
        color: beautify.glassBg
        border.color: beautify.glassBorder
        border.width: 1
        implicitWidth: barCol.implicitWidth + 32
        implicitHeight: barCol.implicitHeight + 24
        scale: beautify.s
        transformOrigin: Item.Bottom

        Column {
            id: barCol
            anchors.centerIn: parent
            spacing: 14

            // background chips
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: beautify.backgrounds
                    Rectangle {
                        id: chip
                        required property int index
                        required property var modelData
                        width: 40
                        height: 28
                        radius: 7
                        readonly property bool sel: beautify.bgIndex === chip.index
                        border.color: chip.sel ? "#ffffff" : Qt.rgba(1, 1, 1, 0.18)
                        border.width: chip.sel ? 2 : 1
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: chip.modelData.a }
                            GradientStop { position: 1.0; color: chip.modelData.b }
                        }
                        scale: chipMa.containsMouse ? 1.08 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; onClicked: beautify.bgIndex = chip.index }
                    }
                }
            }

            // segmented look controls
            Flow {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(implicitWidth, 720)
                spacing: 18
                Seg { label: "Padding"; options: ["None", "S", "M", "L"]; current: beautify.padIndex; onPicked: (i) => beautify.padIndex = i }
                Seg { label: "Corners"; options: ["None", "Soft", "Round"]; current: beautify.radiusIndex; onPicked: (i) => beautify.radiusIndex = i }
                Seg { label: "Shadow"; options: ["Off", "Soft", "Deep"]; current: beautify.shadowIndex; onPicked: (i) => beautify.shadowIndex = i }
                Seg { label: "Ratio"; options: ["Auto", "16:9", "1:1", "4:3", "3:2"]; current: beautify.ratioIndex; onPicked: (i) => beautify.ratioIndex = i }
                Seg { label: "Filter"; options: ["None", "Vivid", "Soft", "Mono"]; current: beautify.filterIndex; onPicked: (i) => beautify.filterIndex = i }
            }

            // divider + actions
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: parent.width; height: 1; color: beautify.sep }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                ActionBtn {
                    label: "Back"
                    onTapped: beautify.closeRequested()
                }
                ActionBtn {
                    label: "Copy"
                    accent: true
                    onTapped: beautify.exportStage(beautify.exportTmp, function (ok) { if (ok) beautify.copyRequested(beautify.exportTmp); })
                }
                ActionBtn {
                    label: "Save"
                    accent: true
                    onTapped: beautify.exportStage(beautify.exportTmp, function (ok) { if (ok) beautify.saveRequested(beautify.exportTmp); })
                }
            }
        }
    }

    // --- inline widgets ---
    component Seg: Row {
        id: seg
        property string label: ""
        property var options: []
        property int current: 0
        signal picked(int i)
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: seg.label
            color: beautify.idle
            font.family: "Space Grotesk"
            font.pixelSize: 12
            font.weight: Font.Medium
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.05)
            implicitWidth: segRow.implicitWidth + 6
            implicitHeight: 28
            Row {
                id: segRow
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: seg.options
                    Rectangle {
                        id: opt
                        required property int index
                        required property var modelData
                        readonly property bool sel: seg.current === opt.index
                        implicitWidth: lbl.implicitWidth + 18
                        height: 24
                        radius: 6
                        color: opt.sel ? beautify.vermilion : (optMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: opt.modelData
                            color: opt.sel ? "#ffffff" : beautify.idle
                            font.family: "Space Grotesk"
                            font.pixelSize: 12
                            font.weight: opt.sel ? Font.DemiBold : Font.Medium
                        }
                        MouseArea { id: optMa; anchors.fill: parent; hoverEnabled: true; onClicked: seg.picked(opt.index) }
                    }
                }
            }
        }
    }

    component ActionBtn: Rectangle {
        id: ab
        property string label: ""
        property bool accent: false
        signal tapped()
        implicitWidth: abLbl.implicitWidth + 34
        implicitHeight: 34
        radius: 8
        color: abMa.containsMouse ? (ab.accent ? Qt.lighter(beautify.vermilion, 1.1) : Qt.rgba(1, 1, 1, 0.08)) : (ab.accent ? beautify.vermilion : "transparent")
        border.width: ab.accent ? 0 : 1
        border.color: beautify.glassBorder
        Text {
            id: abLbl
            anchors.centerIn: parent
            text: ab.label
            color: ab.accent ? "#ffffff" : beautify.idle
            font.family: "Space Grotesk"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        MouseArea { id: abMa; anchors.fill: parent; hoverEnabled: true; onClicked: ab.tapped() }
    }
}
