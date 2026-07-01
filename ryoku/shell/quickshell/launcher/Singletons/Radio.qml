pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../providers/media/ytmusic/ytmusic.js" as YtMusic

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

    // Emitted when a pasted playlist/mix link finishes resolving, with its id and
    // full track list. Launcher (which imports Singletons cleanly) persists it to
    // the Playlists cache; a singleton importing its own qmldir is unreliable, so
    // the save is driven from the view layer instead.
    signal playlistResolved(string playlistId, var tracks)

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

    // True while mpv is loading/buffering our stream and not yet producing sound
    // (mpv's core-idle). The card shows a buffering hint and holds the seekbar so
    // it never ticks in silence, especially on a slow connection.
    property bool buffering: false

    // Bumped on every play() so a radio fetch that resolves after the user picked
    // a different track is discarded instead of polluting the new queue.
    property int session: 0
    property bool extending: false

    // playerctld is a PROXY that mirrors whatever is active (its identity copies
    // the real player's), so it must never be shown or counted, or it double-lists
    // the active source. Identify it by dbusName; everything else is a real player.
    function isProxy(p) {
        return p && String(p.dbusName || "").indexOf("playerctld") !== -1;
    }

    // Real controllable players: the proxy removed and deduped by dbusName, so the
    // card and the strip never show the same source twice. Shared by Launcher and
    // MediaSources so both agree on what exists.
    function realPlayers() {
        var list = Mpris.players.values;
        var out = [];
        if (!list)
            return out;
        var seen = {};
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (!p || root.isProxy(p))
                continue;
            var key = String(p.dbusName || p.identity || i);
            if (seen[key])
                continue;
            seen[key] = 1;
            out.push(p);
        }
        return out;
    }

    // Whether a player is our own mpv stream (never the proxy mirroring it).
    function isOurPlayer(p) {
        return p && !root.isProxy(p) && String(p.identity || "").toLowerCase() === "mpv";
    }

    // Our stream AND it owns playback now: NowPlaying trusts our cover/title then.
    function isOurs(player) {
        return root.isOurPlayer(player) && root.active;
    }

    // Some OTHER real player (a browser, Spotify) is producing sound.
    function otherPlaying() {
        var list = root.realPlayers();
        for (var i = 0; i < list.length; i++)
            if (list[i].isPlaying && !root.isOurPlayer(list[i]))
                return true;
        return false;
    }

    // Our own mpv stream is the one currently playing (gates the yield timer).
    function ourMprisPlaying() {
        var list = root.realPlayers();
        for (var i = 0; i < list.length; i++)
            if (root.isOurPlayer(list[i]) && list[i].isPlaying)
                return true;
        return false;
    }

    // Take over the airwaves: pause every other real player so our stream owns
    // audio instead of stacking on a browser tab. Called on an explicit play.
    function pauseOthers() {
        var list = root.realPlayers();
        for (var i = 0; i < list.length; i++) {
            var p = list[i];
            if (p.isPlaying && !root.isOurPlayer(p) && p.canPause)
                p.pause();
        }
    }

    // Timestamp of the last explicit take-over. The yield timer ignores other
    // players for a grace window after this, so pausing them in play() is never
    // mistaken for "another player started" and bounced straight back.
    property double tookOverAt: 0
    readonly property int yieldGraceMs: 4000

    // Start mpv on `url`, or swap the running mpv to it over IPC (no audio gap).
    // The playlist is cleared so radio/playlist tracks refill from a clean slate.
    function startOrReplace(url) {
        if (playProc.running && mpvSock.connected) {
            root.mpvCmd(["loadfile", url, "replace"]);
            root.mpvCmd(["playlist-clear"]);
            root.mpvCmd(["set_property", "volume", 100]);
            root.mpvCmd(["set_property", "pause", false]);
        } else {
            playProc.firstUrl = url;
            playProc.running = false;
            playProc.running = true;
        }
    }

    function watchUrl(id) { return "https://music.youtube.com/watch?v=" + id; }

    // Play a track now and seed an endless radio from it. Reuses a running mpv
    // (no audio gap) via IPC; cold-starts mpv otherwise.
    function play(track) {
        if (!track || !track.id)
            return;
        root.session++;
        root.buffering = true;
        root.queue = [track];
        root.index = 0;
        // take over: pause whatever else is playing and open the grace window so
        // the yield timer does not treat that same audio as a reason to bow out.
        root.tookOverAt = Date.now();
        root.pauseOthers();
        root.startOrReplace(root.watchUrl(track.id));
        radioProc.fetch(track.id, root.session);
    }

    // Play a pasted YouTube / YouTube Music link. A link with a playlist (a mix or
    // a real playlist) queues that whole playlist; a bare track link seeds its auto
    // radio, same as picking a search result. With a videoId we start playback
    // immediately and fill the queue when /next lands; a playlist-only link waits
    // for the first track. Playlist links are saved for instant replay later.
    function playUrl(url) {
        var parsed = YtMusic.parseYtUrl(url);
        if (!parsed)
            return false;
        root.session++;
        root.buffering = true;
        root.tookOverAt = Date.now();
        root.pauseOthers();
        if (parsed.videoId) {
            // start now on the seed track; the queue fills when the playlist lands.
            root.queue = [{ id: parsed.videoId, title: "", artist: "", album: "", cover: "", durationLabel: "" }];
            root.index = 0;
            root.startOrReplace(root.watchUrl(parsed.videoId));
        } else {
            root.queue = [];
            root.index = 0;
        }
        radioProc.fetchPlaylist(parsed.videoId, parsed.playlistId, root.session, parsed.playlistId.length > 0);
        return true;
    }

    // Instant replay of a saved playlist from cache: no network, the queue is the
    // stored track list and mpv starts on the first track right away.
    function playCached(tracks) {
        if (!tracks || tracks.length === 0)
            return;
        root.session++;
        root.buffering = true;
        root.tookOverAt = Date.now();
        root.pauseOthers();
        root.queue = tracks.slice();
        root.index = 0;
        root.startOrReplace(root.watchUrl(tracks[0].id));
        for (var i = 1; i < tracks.length; i++)
            root.mpvCmd(["loadfile", root.watchUrl(tracks[i].id), "append"]);
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
        root.buffering = false;
        mpvSock.connected = false;
        playProc.running = false;
        killProc.running = true;
    }

    // Send one JSON command to mpv's IPC socket, or queue it until the socket
    // connects. Radio appends resolve seconds after mpv launches, often before
    // the socket is up; without this buffer those writes were silently dropped
    // (the bug that left the queue at one track).
    property var pending: []
    function mpvCmd(cmdArray) {
        var line = JSON.stringify({ command: cmdArray }) + "\n";
        if (mpvSock.connected) {
            mpvSock.write(line);
        } else {
            var q = root.pending;
            q.push(line);
            root.pending = q;
        }
    }
    function flushPending() {
        var q = root.pending;
        root.pending = [];
        for (var i = 0; i < q.length; i++)
            mpvSock.write(q[i]);
    }

    // The persistent audio mpv. `--idle=yes` keeps it alive when the queue drains
    // before radio refills; the IPC server is how we append and observe.
    Process {
        id: playProc
        property string firstUrl: ""
        command: ["mpv", "--no-video", "--no-terminal", "--force-window=no",
            "--audio-display=no", "--idle=yes", "--volume=100",
            "--cache=yes", "--network-timeout=20",
            "--input-ipc-server=" + root.ipcSocket,
            "--ytdl-format=bestaudio/best", firstUrl]
        onStarted: sockDial.start()
        onExited: {
            mpvSock.connected = false;
            sockDial.stop();
            root.queue = [];
            root.buffering = false;
        }
    }

    // mpv creates the IPC socket a beat after launch; dial until it answers.
    Timer {
        id: sockDial
        interval: 120
        repeat: true
        property int tries: 0
        onTriggered: {
            if (mpvSock.connected) { sockDial.stop(); tries = 0; return; }
            if (++tries > 60) { sockDial.stop(); tries = 0; return; }
            mpvSock.connected = true;
        }
    }

    Socket {
        id: mpvSock
        path: root.ipcSocket
        // the `connected` property notifies via connectionStateChanged, NOT
        // connectedChanged; using the wrong signal left the dial churning and
        // dropped every queued write. On connect: stop dialing, observe the
        // playlist position, and flush the appends buffered while disconnected.
        onConnectionStateChanged: {
            if (connected) {
                sockDial.stop();
                mpvSock.write(JSON.stringify({ command: ["observe_property", 1, "playlist-pos"] }) + "\n");
                // core-idle is true while mpv is loading/buffering and NOT actually
                // producing sound; observing it lets the card show a buffering state
                // and freeze the seekbar instead of ticking silently on a slow load.
                mpvSock.write(JSON.stringify({ command: ["observe_property", 2, "core-idle"] }) + "\n");
                root.flushPending();
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
                // don't kick an extend while any fetch is in flight: a playlist
                // link starts with a 1-track queue, and an eager extend here would
                // clobber the playlist fetch (and never cache it).
                if (root.queue.length - pos <= 3 && !root.extending && !radioProc.running)
                    root.extendRadio();
            }
        } else if (msg && msg.event === "property-change" && msg.name === "core-idle") {
            root.buffering = (msg.data === true);
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

    // Continuation / playlist fetch: POST InnerTube /next. In "extend" mode it
    // appends the auto-radio tail (dedup) as the queue drains; in "playlist" mode
    // it loads a pasted playlist/mix as the whole queue and saves it for replay.
    Process {
        id: radioProc
        property int forSession: 0
        property string body: ""
        property string mode: "extend"
        property string savePlaylistId: ""
        function fetch(videoId, sess) {
            mode = "extend";
            forSession = sess;
            body = YtMusic.radioBody(videoId);
            running = false;
            running = true;
        }
        function fetchPlaylist(videoId, playlistId, sess, save) {
            mode = "playlist";
            forSession = sess;
            savePlaylistId = save ? playlistId : "";
            body = YtMusic.radioBody(videoId, playlistId);
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
                var tracks = YtMusic.parseRadio(this.text);
                if (radioProc.mode === "playlist") {
                    if (tracks.length === 0) {
                        root.buffering = false;
                        return;
                    }
                    var startedVid = root.queue.length > 0 ? root.queue[0].id : "";
                    if (!(startedVid && tracks[0].id === startedVid))
                        root.startOrReplace(root.watchUrl(tracks[0].id));
                    for (var k = 1; k < tracks.length; k++)
                        root.mpvCmd(["loadfile", root.watchUrl(tracks[k].id), "append"]);
                    root.queue = tracks;
                    root.index = 0;
                    if (radioProc.savePlaylistId.length > 0)
                        root.playlistResolved(radioProc.savePlaylistId, tracks);
                    return;
                }
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
                    root.mpvCmd(["loadfile", root.watchUrl(t.id), "append"]);
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

    // Graceful yield: once another player starts *after* our take-over grace
    // window, fade our volume down and pause (not kill) so audio never stacks and
    // the user can resume us from the sources strip. Gated on our own mpv actually
    // playing, so it fires once (pausing clears the condition) and never fights.
    Timer {
        interval: 1000
        repeat: true
        running: playProc.running
        onTriggered: {
            if (fade.running)
                return;
            if (Date.now() - root.tookOverAt < root.yieldGraceMs)
                return;
            if (root.ourMprisPlaying() && root.otherPlaying())
                fade.begin();
        }
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

    // Kill any orphan mpv from a previous launcher instance on startup: a daemon
    // restart or crash SIGTERMs the old qs before Component.onDestruction can run,
    // leaving an mpv playing that the new Radio has no queue for (it would show a
    // raw "watch?v=..." title with no cover). Clean slate so state always matches.
    Component.onCompleted: killProc.running = true
    Component.onDestruction: killProc.running = true
}
