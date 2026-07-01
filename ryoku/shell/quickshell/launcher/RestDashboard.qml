import QtQuick
import Quickshell
import Quickshell.Widgets
import "Singletons"

// Zero-query home card. A day-wave scene: the hero clock and greeting read over
// a filled wave horizon that encodes the day itself. The stretch of wave behind
// the sun glows the accent (the day so far); the stretch ahead stays faint (what
// is left); a sun or moon rides the ridge at the current time. It is the same
// grammar as the NowPlaying seekbar below it (filled = elapsed), so the resting
// card and the playing card rhyme instead of the clock reading as a foreign
// slab. Surface is the recessed cardBot with a hairline border and a top sheen
// so it sits in the window; corner radius steps one inside the window so the
// nested corners read concentric. Right column carries the weather glance when
// resolved (glyph + temperature, condition and city, mixed-case date at the
// base) and falls back to a clean date-only readout while Weather is fetching so
// the column is never dead space. The wave drifts and the colon breathes only
// while the launcher is shown, so an idle palette costs nothing.
Item {
    id: root

    property real s: 1
    implicitHeight: 106 * s

    readonly property var now: clock.date
    readonly property string hh: Qt.formatTime(now, "HH")
    readonly property string mm: Qt.formatTime(now, "mm")
    readonly property string date: Qt.locale("en_US").toString(now, "dddd, MMM d")
    readonly property string greeting: {
        var h = now.getHours();
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    }
    // fraction of the day elapsed, midnight to midnight, positions the sun.
    readonly property real dayFrac: (now.getHours() * 3600 + now.getMinutes() * 60) / 86400
    // sun by day, moon by night: trust the weather feed once resolved, otherwise
    // a plain daylight window so the pre-fetch marker is right through the evening.
    readonly property bool isDay: Weather.available ? Weather.isDay : (now.getHours() >= 6 && now.getHours() < 20)
    readonly property bool wxReady: Weather.available

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Squircle {
        anchors.fill: parent
        radius: Metrics.radiusCard
        power: 4
        color: Theme.cardBot
        borderColor: Theme.border
        borderWidth: 1

        // Lit top edge: a hairline of palette sheen inset past the rounded
        // corners so the recessed panel catches light from above, the cue the
        // NowPlaying card gets from its blurred art bleed.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: Metrics.radiusCard * root.s
            anchors.rightMargin: Metrics.radiusCard * root.s
            height: 1
            color: Theme.sheen
        }

        // The day wave: a filled horizon spanning the card, clipped to the
        // rounded corners so it never spills. Painted behind the text.
        ClippingRectangle {
            id: waveClip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 42 * root.s
            radius: Metrics.radiusCard * root.s
            color: "transparent"

            Canvas {
                id: wave
                anchors.fill: parent
                property real phase: 0
                readonly property real frac: root.dayFrac
                readonly property color accent: Theme.verm

                onFracChanged: requestPaint()

                // Canvas gradients want rgba() strings, not QML color objects
                // (a color serializes to #aarrggbb and corrupts the stop).
                function rgba(c, a) {
                    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255)
                        + "," + Math.round(c.b * 255) + "," + a + ")";
                }

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var w = width, h = height, s = root.s;
                    var base = h * 0.66, amp = 5 * s, steps = 72;
                    function ridge(x) {
                        var t = x / w;
                        return base + amp * Math.sin(t * Math.PI * 3 + wave.phase)
                            + amp * 0.4 * Math.sin(t * Math.PI * 7 - wave.phase * 0.7);
                    }
                    var nodeX = Math.max(2 * s, Math.min(w - 2 * s, w * wave.frac));

                    function fillRegion(x0, x1, style) {
                        ctx.beginPath();
                        ctx.moveTo(x0, h);
                        for (var i = 0; i <= steps; i++) {
                            var x = x0 + (x1 - x0) * i / steps;
                            ctx.lineTo(x, ridge(x));
                        }
                        ctx.lineTo(x1, h);
                        ctx.closePath();
                        ctx.fillStyle = style;
                        ctx.fill();
                    }
                    function strokeRidge(x0, x1, style) {
                        ctx.beginPath();
                        for (var i = 0; i <= steps; i++) {
                            var x = x0 + (x1 - x0) * i / steps;
                            var y = ridge(x);
                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                        }
                        ctx.strokeStyle = style;
                        ctx.stroke();
                    }

                    // elapsed fill (accent) then remaining fill (ghost), both
                    // fading up from the baseline so the ridge reads as a horizon.
                    var gA = ctx.createLinearGradient(0, base - amp * 2, 0, h);
                    gA.addColorStop(0, wave.rgba(wave.accent, 0.0));
                    gA.addColorStop(0.5, wave.rgba(wave.accent, 0.15));
                    gA.addColorStop(1, wave.rgba(wave.accent, 0.36));
                    fillRegion(0, nodeX, gA);

                    var gF = ctx.createLinearGradient(0, base - amp * 2, 0, h);
                    gF.addColorStop(0, wave.rgba(Theme.ghost, 0.0));
                    gF.addColorStop(1, wave.rgba(Theme.ghost, 0.22));
                    fillRegion(nodeX, w, gF);

                    ctx.lineWidth = 2 * s;
                    ctx.lineCap = "round";
                    strokeRidge(0, nodeX, wave.rgba(wave.accent, 0.9));
                    strokeRidge(nodeX, w, wave.rgba(Theme.faint, 0.5));

                    // sun / moon node: a soft glow halo, a filled disc, and a
                    // carved crescent by night.
                    var sy = ridge(nodeX);
                    var glow = ctx.createRadialGradient(nodeX, sy, 0, nodeX, sy, 15 * s);
                    glow.addColorStop(0, wave.rgba(wave.accent, 0.5));
                    glow.addColorStop(1, wave.rgba(wave.accent, 0.0));
                    ctx.fillStyle = glow;
                    ctx.beginPath();
                    ctx.arc(nodeX, sy, 15 * s, 0, 2 * Math.PI);
                    ctx.fill();

                    var r = 5.5 * s;
                    ctx.fillStyle = root.isDay ? wave.rgba(wave.accent, 1) : wave.rgba(Theme.cream, 0.95);
                    ctx.beginPath();
                    ctx.arc(nodeX, sy, r, 0, 2 * Math.PI);
                    ctx.fill();
                    if (!root.isDay) {
                        ctx.fillStyle = wave.rgba(Theme.cardBot, 1);
                        ctx.beginPath();
                        ctx.arc(nodeX + r * 0.6, sy - r * 0.4, r, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                }

                // Gentle drift, only while the palette is shown, so an idle
                // launcher triggers no repaints.
                FrameAnimation {
                    running: root.visible
                    onTriggered: {
                        wave.phase = Date.now() / 900;
                        wave.requestPaint();
                    }
                }
            }
        }

        // left: greeting eyebrow over the hero clock.
        Column {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.padOuter * root.s
            anchors.top: parent.top
            anchors.topMargin: 16 * root.s
            spacing: 4 * root.s

            Text {
                text: root.greeting
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: Metrics.fontEyebrow * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
            Row {
                spacing: 0
                Text {
                    text: root.hh
                    color: Theme.bright
                    font.family: Theme.mono
                    font.pixelSize: 34 * root.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: ":"
                    color: Theme.verm
                    font.family: Theme.mono
                    font.pixelSize: 34 * root.s
                    font.weight: Font.Medium
                    // Breathing colon, the shared clock-face heartbeat.
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 620; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.3; to: 1; duration: 620; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    text: root.mm
                    color: Theme.bright
                    font.family: Theme.mono
                    font.pixelSize: 34 * root.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }
        }

        // right: weather glance when resolved, date-only fallback while it is
        // still fetching so the column never reads as dead space.
        Column {
            anchors.right: parent.right
            anchors.rightMargin: Metrics.padOuter * root.s
            anchors.top: parent.top
            anchors.topMargin: 18 * root.s
            spacing: 3 * root.s

            // headline: icon + temperature, matched in weight to the left clock.
            Row {
                anchors.right: parent.right
                spacing: 6 * root.s
                visible: root.wxReady

                WeatherGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22 * root.s
                    height: 22 * root.s
                    name: Weather.glyph
                    color: Theme.cream
                    stroke: 1.7
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.temp
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 22 * root.s
                    font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }

            // fallback headline while weather has not resolved yet, in the same
            // slot as the temperature so the layout does not jump on arrival.
            Text {
                anchors.right: parent.right
                visible: !root.wxReady
                text: root.date
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 22 * root.s
                font.weight: Font.Medium
            }

            Text {
                anchors.right: parent.right
                visible: root.wxReady
                text: Weather.condition + (Weather.city.length ? "  \u00b7  " + Weather.city : "")
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: Metrics.fontSubtitle * root.s
            }

            Text {
                anchors.right: parent.right
                visible: root.wxReady
                text: root.date
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Metrics.fontEyebrow * root.s
            }
        }
    }
}
