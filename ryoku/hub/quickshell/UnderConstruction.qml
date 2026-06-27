import QtQuick
import "Singletons"

// placeholder for sections still being built (Extras, Shell Settings). airy,
// centred, no boxed tile. big ember glyph + heading + section blurb + a mono
// "coming soon".
Item {
    id: uc

    property string title: ""
    property string blurb: ""
    property string icon: "wrench"

    Column {
        anchors.centerIn: parent
        width: Math.min(uc.width - 96, 430)
        spacing: 22

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: uc.icon
            size: 56
            weight: 1.4
            tint: Theme.ember
            opacity: 0.85
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Under construction"
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 20
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: uc.blurb
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
            wrapMode: Text.WordWrap
            lineHeight: 1.35
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "COMING SOON"
            color: Theme.ember
            font.family: Theme.mono
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 2
        }
    }
}
