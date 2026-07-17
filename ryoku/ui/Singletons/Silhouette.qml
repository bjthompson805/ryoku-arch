pragma Singleton

import QtQuick
import Quickshell

// The bar skins, drawn. Every skin's silhouette lives here once so the gallery
// tile and the live preview cannot disagree about what a skin looks like.
// Descriptions come from docs/bar.md and pill/Bar.qml, not from taste.
Singleton {
    readonly property var skins: [
        { key: "noctalia",  origin: "reference", draw: "noctalia",  what: "Capsule modules in a row, dot workspaces, the stacked clock" },
        { key: "caelestia", origin: "reference", draw: "caelestia", what: "Numbered cell strip in one pill with a sliding indicator" },
        { key: "aegis",     origin: "ryoku",     draw: "aegis",     what: "Flat modules with hairline accent underlines" },
        { key: "stele",     origin: "ryoku",     draw: "stele",     what: "Engraved bracket cells" },
        { key: "triptych",  origin: "ryoku",     draw: "triptych",  what: "Three rounded islands on the band" },
        { key: "delos",     origin: "ryoku",     draw: "delos",     what: "The whole bar collapsed into one floating island" },
        { key: "nacre",     origin: "ryoku",     draw: "nacre",     what: "Three islands with concave dips under a hairline top edge" },
        { key: "inir",      origin: "inir",      draw: "inir",      what: "Flat frame-off panel with hairline cell separators" },
        { key: "aurora",    origin: "inir",      draw: "aurora",    what: "Translucent frame-off glass with a soft top sheen" },
        { key: "angel",     origin: "inir",      draw: "angel",     what: "Opaque brutalist panel, heavy base, bright inset top" }
    ]

    function pill(c, x, y, w, h, r) {
        c.beginPath();
        c.moveTo(x + r, y);
        c.lineTo(x + w - r, y); c.quadraticCurveTo(x + w, y, x + w, y + r);
        c.lineTo(x + w, y + h - r); c.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
        c.lineTo(x + r, y + h); c.quadraticCurveTo(x, y + h, x, y + h - r);
        c.lineTo(x, y + r); c.quadraticCurveTo(x, y, x + r, y);
        c.closePath();
    }

    // fgA/dimA let a selected tile lift without changing the drawing.
    function draw(c, kind, W, H, fgA, dimA) {
        var fg = "rgba(205,196,186," + fgA + ")";
        var dim = "rgba(205,196,186," + dimA + ")";
        var by = 10, bh = 12, i;
        c.fillStyle = fg; c.strokeStyle = fg; c.lineWidth = 1;

        if (kind === "noctalia") {
            for (i = 0; i < 4; i++) { pill(c, 4 + i * 30, by, 24, bh, 6); c.fill() }
        } else if (kind === "caelestia") {
            pill(c, 4, by, W - 8, bh, 6); c.fillStyle = dim; c.fill();
            c.fillStyle = fg; pill(c, 8, by + 2, 22, bh - 4, 4); c.fill();
            c.fillStyle = dim;
            for (i = 1; i < 4; i++) { pill(c, 8 + i * 26, by + 2, 22, bh - 4, 4); c.stroke() }
        } else if (kind === "aegis") {
            for (i = 0; i < 4; i++) {
                c.fillStyle = dim; c.fillRect(4 + i * 30, by, 24, bh);
                c.fillStyle = fg; c.fillRect(4 + i * 30, by + bh - 2, 24, 2);
            }
        } else if (kind === "stele") {
            for (i = 0; i < 4; i++) {
                var x0 = 4 + i * 30;
                c.beginPath(); c.moveTo(x0 + 4, by); c.lineTo(x0, by); c.lineTo(x0, by + bh); c.lineTo(x0 + 4, by + bh); c.stroke();
                c.beginPath(); c.moveTo(x0 + 20, by); c.lineTo(x0 + 24, by); c.lineTo(x0 + 24, by + bh); c.lineTo(x0 + 20, by + bh); c.stroke();
                c.fillStyle = dim; c.fillRect(x0 + 7, by + 4, 10, 4);
            }
        } else if (kind === "triptych") {
            var w3 = (W - 8 - 12) / 3;
            for (i = 0; i < 3; i++) { pill(c, 4 + i * (w3 + 6), by, w3, bh, 5); c.fill() }
        } else if (kind === "delos") {
            pill(c, W / 2 - 22, by - 2, 44, bh + 4, 8); c.fill();
            c.fillStyle = dim; c.fillRect(4, by + 5, W - 8, 1);
        } else if (kind === "nacre") {
            var w4 = (W - 8 - 10) / 3;
            c.fillStyle = dim; c.fillRect(2, by - 4, W - 4, 1);
            c.fillStyle = fg;
            for (i = 0; i < 3; i++) { pill(c, 4 + i * (w4 + 5), by, w4, bh, 5); c.fill() }
        } else if (kind === "inir") {
            c.fillStyle = dim; c.fillRect(0, by, W, bh);
            c.strokeStyle = fg;
            for (i = 1; i < 5; i++) { c.beginPath(); c.moveTo(i * W / 5, by); c.lineTo(i * W / 5, by + bh); c.stroke() }
        } else if (kind === "aurora") {
            var g = c.createLinearGradient(0, by, 0, by + bh);
            g.addColorStop(0, "rgba(205,196,186," + (fgA * 0.56) + ")");
            g.addColorStop(1, "rgba(205,196,186,0.06)");
            c.fillStyle = g; c.fillRect(0, by, W, bh);
            c.fillStyle = fg; c.fillRect(0, by, W, 1);
        } else if (kind === "angel") {
            c.fillStyle = dim; c.fillRect(0, by, W, bh);
            c.fillStyle = fg; c.fillRect(0, by, W, 2); c.fillRect(0, by + bh - 3, W, 3);
        }
    }
}
