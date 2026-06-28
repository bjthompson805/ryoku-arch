pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether any application is actively playing audio. The visualiser uses this
// to run cava only when there is sound to show, instead of spinning it at the
// configured framerate around the clock. Defaults to playing so a box without
// pactl, or the window before the first probe, behaves exactly as before rather
// than going dark. `pactl subscribe` wakes the probe on every stream change;
// the probe reports active when a sink input is uncorked (really playing, not
// just paused).
Singleton {
    id: root

    property bool playing: true

    Process {
        id: probe
        command: ["sh", "-c", "command -v pactl >/dev/null 2>&1 || { echo keep; exit 0; }; pactl list sink-inputs 2>/dev/null | grep -q 'Corked: no' && echo on || echo off"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim();
                if (t === "on")
                    root.playing = true;
                else if (t === "off")
                    root.playing = false;
                // "keep" means no pactl: leave playing untouched (true).
            }
        }
    }

    // Re-probe shortly after any sink-input change (start, stop, pause, resume).
    // Debounced so a burst of events collapses into one probe.
    Process {
        id: sub
        command: ["pactl", "subscribe"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.indexOf("sink-input") >= 0)
                    debounce.restart();
            }
        }
    }

    Timer {
        id: debounce
        interval: 200
        onTriggered: probe.running = true
    }

    Component.onCompleted: probe.running = true
}
