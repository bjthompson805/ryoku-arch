pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "Singletons"

// The Profile section: a showcase screen built to be screenshotted and shared
// alongside a rice. The specimen card sits on the left as the hero; a dossier of
// extended system stats sits on the right. An ambient backdrop (soft glow blooms,
// a faint spec grid, an edge vignette, and corner ticks) ties the
// pair together. The card is the hub-palette twin of the shell pill's system card.
Item {
    id: page

    // The specimen is height-bound; keep it under ~42% of the width so the dossier
    // keeps room on the right.
    readonly property real cardW: Math.round(Math.min((page.height - 44) * 0.585, page.width * 0.42, 440))

    ShowcaseBackdrop { anchors.fill: parent }

    // ── The specimen, left and lifted ───────────────────────────────────────
    ProfileCard {
        id: hero
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        cardWidth: page.cardW

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.55)
            shadowBlur: 1.0
            shadowVerticalOffset: 12
            autoPaddingEnabled: true
        }
    }

    // Hairline rule down the gutter between the specimen and the dossier.
    Rectangle {
        anchors.left: hero.right
        anchors.leftMargin: 21
        anchors.top: hero.top
        anchors.bottom: hero.bottom
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        width: 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.16; color: Qt.alpha(Theme.cream, 0.09) }
            GradientStop { position: 0.84; color: Qt.alpha(Theme.cream, 0.09) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // ── The dossier, right, spanning the specimen's height ───────────────────
    ProfileStats {
        anchors.left: hero.right
        anchors.leftMargin: 44
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.top: hero.top
        anchors.topMargin: 8
        anchors.bottom: hero.bottom
    }
}
