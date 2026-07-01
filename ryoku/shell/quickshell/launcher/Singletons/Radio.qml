pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../providers/media/ytmusic/ytmusic.js" as YtMusic
import "../providers/media/ytmusic/radio.js" as RadioApi

// The YouTube Music radio engine: one persistent mpv (audio only) driven over its
// JSON IPC socket, playing a queue that auto-extends with YouTube Music radio so
// free music never stops. mpv-mpris publishes the stream as a first-class MPRIS
// player, so the now-playing card and media keys drive this queue with the same
// Next/Prev they use for any player; this singleton keeps the ordered queue and
// the per-track cover (InnerTube's square art) the MPRIS metadata cannot supply.
//
// Owned here (not in the provider) so both the `@` search provider and the MPRIS
// "YT Radio" verb feed the same engine. Costs nothing at rest: no process runs
// until the first play; the socket, poll, and radio fetch are all playback-gated.
Singleton {
    id: root

    readonly property string ipcSocket: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-ytmusic-mpv.sock"

    // The play queue (picked track + radio continuation) and the index mpv is on.
    // `current`/`next` drive the now-playing cover and the up-next peek.
    property var queue: []
    property int index: 0
    readonly property var current: (index >= 0 && index < queue.length) ? queue[index] : null
    readonly property var next: (index + 1 < queue.length) ? queue[index + 1] : null

    // Live while our mpv owns playback. NowPlaying reads these so the card shows
    // the exact square cover and clean title per radio track, not mpv's guess.
    readonly property bool active: playProc.running && queue.length > 0
    readonly property string cover: current ? (current.cover || "") : ""
    readonly property string title: current ? (current.title || "") : ""
    readonly property string artist: current ? (current.artist || "") : ""
    readonly property string upNext: next ? (next.title || "") : ""

    // Bumped on every play() so a radio fetch that resolves after the user picked
    // a different track is discarded instead of polluting the new queue.
    property int session: 0
    property bool extending: false

    // Whether the given MPRIS player is our own mpv stream. mpv-mpris identifies
    // as "mpv"; combined with `active` this tells NowPlaying to trust our hint.
    function isOurs(player) {
        return player && String(player.identity || "").toLowerCase() === "mpv" && root.active;
    }

    // Some OTHER player (Spotify, a browser, an app) is producing sound. We yield
    // to it so two streams never stack.
    function otherPlaying() {
        var list = Mpris.players.values;
        if (!list)
            return false;
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (p && p.isPlaying && String(p.identity || "").toLowerCase() !== "mpv")
                return true;
        }
        return false;
    }

    // Play a track now and seed an endless radio from it. Reuses a running mpv
    // (no audio gap) via IPC; cold-starts mpv otherwise.
    function play(track) {
        if (!track || !track.id)
            return;
        root.session++;
        root.queue = [track];
        root.index = 0;
        var url = "https://music.youtube.com/watch?v=" + track.id;
        if (playProc.running && mpvSock.connected) {
            // clean the playlist down to just this track, then let radio refill.
            root.mpvCmd(["loadfile", url, "replace"]);
            root.mpvCmd(["playlist-clear"]);
            root.mpvCmd(["set_property", "pause", false]);
        } else {
            playProc.firstUrl = url;
            playProc.running = false;
            playProc.running = true;
        }
        radioProc.fetch(track.id, root.session);
    }

    // Seed radio from a free-text "artist title" (the MPRIS "YT Radio" verb):
    // resolve the first InnerTube song hit, then play it.
    function playFromText(text) {
        seedProc.session = ++root.session;
        seedProc.term = String(text || "").trim();
        if (seedProc.term.length === 0)
            return;
        seedProc.running = false;
        seedProc.running = true;
    }

    // Stop for good: kill mpv and clear. Used on explicit stop / launcher exit.
    function stop() {
        root.queue = [];
        root.index = 0;
        mpvSock.connected = false;
        playProc.running = false;
        killProc.running = true;
    }

    // Send one JSON command line to mpv's IPC socket.
    function mpvCmd(cmdArray) {
        if (mpvSock.connected)
            mpvSock.write(JSON.stringify({ command: cmdArray }) + "\n");
    }

    // The persistent audio mpv. `--idle=yes` keeps it alive when the queue drains
    // before radio refills; the IPC server is how we append and observe.
    Process {
        id: playProc
        property string firstUrl: ""
        command: ["mpv", "--no-video", "--no-terminal", "--force-window=no",
            "--audio-display=no", "--idle=yes", "--volume=100",
            "--input-ipc-server=" + root.ipcSocket,
            "--ytdl-format=bestaudio", firstUrl]
        onStarted: sockDial.start()
        onExited: {
            mpvSock.connected = false;
            sockDial.stop();
            root.queue = [];
        }
    }

    // mpv creates the IPC socket a beat after launch; dial until it answers.
    Timer {
        id: sockDial
        interval: 120
        repeat: true
        property int tries: 0
        onTriggered: {
            if (mpvSock.connected) { stop(); tries = 0; return; }
            if (++tries > 60) { stop(); tries = 0; return; }
            mpvSock.connected = true;
        }
    }

    Socket {
        id: mpvSock
        path: root.ipcSocket
        onConnectedChanged: {
            if (connected) {
                sockDial.stop();
                // observe the playlist position so the card follows radio tracks.
                root.mpvCmd(["observe_property", 1, "playlist-pos"]);
            }
        }
        parser: SplitParser {
            splitMarker: "\n"
            onRead: line => root.onMpvLine(line)
        }
    }

    // Handle an mpv IPC line: a playlist-pos change advances our index (so the
    // cover/up-next follow) and refills radio as the tail approaches.
    function onMpvLine(line) {
        var msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg && msg.event === "property-change" && msg.name === "playlist-pos") {
            var pos = msg.data;
            if (typeof pos === "number" && pos >= 0) {
                root.index = pos;
                if (root.queue.length - pos <= 3 && !root.extending)
                    root.extendRadio();
            }
        }
    }

    // Append more radio seeded from the last queued track, so the station is
    // effectively endless. Guarded by `extending` so mpv's rapid position events
    // never fire a burst of overlapping fetches.
    function extendRadio() {
        if (root.queue.length === 0)
            return;
        root.extending = true;
        radioProc.fetch(root.queue[root.queue.length - 1].id, root.session);
    }

    // Radio continuation fetch: POST InnerTube /next, parse the queue, append the
    // tracks new to us (skipping dupes) to both our queue and mpv's playlist.
    Process {
        id: radioProc
        property int forSession: 0
        property string body: ""
        function fetch(videoId, sess) {
            forSession = sess;
            body = RadioApi.radioBody(videoId);
            running = false;
            running = true;
        }
        command: ["curl", "-s", "--max-time", "12",
            "https://music.youtube.com/youtubei/v1/next?prettyPrint=false",
            "-H", "Content-Type: application/json",
            "-H", "User-Agent: Mozilla/5.0",
            "--data-raw", body]
        stdout: StdioCollector {
            onStreamFinished: {
                root.extending = false;
                if (radioProc.forSession !== root.session)
                    return;
                var tracks = RadioApi.parseRadio(this.text);
                var have = {};
                for (var i = 0; i < root.queue.length; i++)
                    have[root.queue[i].id] = 1;
                var q = root.queue.slice();
                for (var j = 0; j < tracks.length; j++) {
                    var t = tracks[j];
                    if (have[t.id])
                        continue;
                    have[t.id] = 1;
                    q.push(t);
                    root.mpvCmd(["loadfile", "https://music.youtube.com/watch?v=" + t.id, "append"]);
                }
                root.queue = q;
            }
        }
    }

    // "YT Radio" seed: first InnerTube song hit for the free-text term, then play.
    Process {
        id: seedProc
        property int session: 0
        property string term: ""
        command: ["curl", "-s", "--max-time", "12",
            "https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
            "-H", "Content-Type: application/json",
            "-H", "User-Agent: Mozilla/5.0",
            "--data-raw", YtMusic.innertubeBody(term)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (seedProc.session !== root.session)
                    return;
                var rows = YtMusic.parse(this.text);
                if (rows.length > 0)
                    root.play(rows[0]);
            }
        }
    }

    // Graceful yield: when another player starts, fade our volume down and pause
    // (not kill), so hand-off is smooth and the user can resume from the card.
    Timer {
        interval: 1000
        repeat: true
        running: playProc.running
        onTriggered: if (root.otherPlaying() && !fade.running) fade.begin();
    }

    Timer {
        id: fade
        property int step: 0
        interval: 60
        repeat: true
        function begin() { step = 0; start(); }
        onTriggered: {
            step++;
            var vol = Math.max(0, 100 - step * 25);
            root.mpvCmd(["set_property", "volume", vol]);
            if (vol <= 0) {
                stop();
                root.mpvCmd(["set_property", "pause", true]);
                root.mpvCmd(["set_property", "volume", 100]);
            }
        }
    }

    // pkill fallback + socket cleanup for stop()/exit, matching the old teardown.
    Process {
        id: killProc
        command: ["sh", "-c",
            "pkill -f 'mpv.*ryoku-ytmusic-mpv\\.sock' 2>/dev/null; " +
            "i=0; while [ $i -lt 20 ] && pgrep -f 'mpv.*ryoku-ytmusic-mpv\\.sock' >/dev/null 2>&1; do sleep 0.05; i=$((i+1)); done; " +
            "rm -f " + root.ipcSocket + "; true"]
    }

    Component.onDestruction: killProc.running = true
}
