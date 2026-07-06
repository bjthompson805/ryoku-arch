pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// now-playing module: art thumb, ping-pong title, play state, all read from
// the shared Media pick (wallpaper-filtered). click toggles playback, wheel
// nudges the sink volume (the OSD panel narrates the change). hidden with no
// player, so the plate only exists when there is music. a vertical bar keeps
// only the art thumb (state tinted), the noctalia idiom.
Row {
    id: media

    property real s: 1
    property bool vertical: false

    readonly property var player: Media.player
    readonly property bool playing: Media.playing
    readonly property bool present: Media.present
    readonly property string line: Media.line

    function toggle() {
        Media.toggle();
    }

    spacing: 8 * s
    // art thumb, hairline edge; kanji seal while artless. round under the
    // capsule skin, sharp under plates. carries the play state alone on a
    // vertical bar (accent edge while sounding).
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: (media.vertical ? 19 : 17) * media.s
        height: (media.vertical ? 19 : 17) * media.s
        radius: Config.barStyle === "capsule" ? width / 2 : 0
        color: Qt.alpha(Theme.bright, 0.05)
        border.width: 1
        border.color: media.vertical && media.playing ? Qt.alpha(Theme.verm, 0.8) : Theme.hair
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: 1
            source: media.player ? (media.player.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            anchors.centerIn: parent
            visible: !media.player || !(media.player.trackArtUrl || "").length
            text: "音"
            color: Theme.iconDim
            font.family: Theme.fontJp
            font.pixelSize: 9 * media.s
        }
    }

    Marquee {
        visible: !media.vertical
        id: title
        anchors.verticalCenter: parent.verticalCenter
        readonly property real natW: titleMetrics.advanceWidth
        width: Math.min(natW + 2, 170 * media.s)
        active: media.playing
        text: media.line
        color: media.playing ? Theme.cream : Theme.dim
        pixelSize: 10.5 * media.s
        weight: Font.Medium

        TextMetrics {
            id: titleMetrics
            text: media.line
            font.family: Theme.font
            font.pixelSize: 10.5 * media.s
            font.weight: Font.Medium
        }
    }

    // state tick: a vermilion play wedge while sounding, a paused hairline pair.
    Item {
        visible: !media.vertical
        anchors.verticalCenter: parent.verticalCenter
        width: 8 * media.s
        height: 9 * media.s

        Canvas {
            anchors.fill: parent
            visible: media.playing
            onPaint: {
                var c = getContext("2d");
                c.reset();
                c.fillStyle = Theme.verm;
                c.beginPath();
                c.moveTo(0, 0);
                c.lineTo(width, height / 2);
                c.lineTo(0, height);
                c.closePath();
                c.fill();
            }
        }
        Row {
            anchors.centerIn: parent
            visible: !media.playing
            spacing: 2.5 * media.s
            Rectangle { width: 2 * media.s; height: 9 * media.s; color: Theme.dim }
            Rectangle { width: 2 * media.s; height: 9 * media.s; color: Theme.dim }
        }
    }
}
