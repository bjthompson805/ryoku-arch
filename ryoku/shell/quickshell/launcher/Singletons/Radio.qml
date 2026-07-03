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
    // engineUp mirrors the IPC socket: mpv is spawned detached (so a quickshell
    // reload cannot kill it) and its death is observed as socket EOF, not as a
    // child-process exit.
    property bool engineUp: false
    readonly property bool active: engineUp && queue.length > 0
    readonly property string cover: current ? (current.cover || "") : ""
    readonly property string title: current ? (current.title || "") : ""
    readonly property string artist: current ? (current.artist || "") : ""
    readonly property string upNext: next ? (next.title || "") : ""

    // True while mpv is loading/buffering our stream and not yet producing sound
    // (mpv's core-idle). The card shows a buffering hint and holds the seekbar so
    // it never ticks in silence, especially on a slow connection.
    property bool buffering: false

    // Whether the playlist is shuffled. Toggled from the card; mpv owns the actual
    // reorder (playlist-shuffle/unshuffle, which keeps history and prev/next), and
    // we re-sync our queue from mpv's playlist afterward so covers/titles stay right.
    property bool shuffled: false

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
    // Matched by DBus name: mpv-mpris derives it from mpv's audio-client-name,
    // which we set to "ryotunes" at spawn, so a user's own mpv (same mpv-mpris
    // script, identity also "mpv") is never mistaken for our stream.
    function isOurPlayer(p) {
        return p && !root.isProxy(p) && String(p.dbusName || "").indexOf("org.mpris.MediaPlayer2.mpv.ryotunes") === 0;
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
        // a fresh play rebuilds mpv's playlist, which drops mpv's shuffle state;
        // keep our flag in step so the button never lies.
        root.shuffled = false;
        if (mpvSock.connected) {
            root.mpvCmd(["loadfile", url, "replace"]);
            root.mpvCmd(["playlist-clear"]);
            root.mpvCmd(["set_property", "volume", 100]);
            root.mpvCmd(["set_property", "pause", false]);
        } else {
            root.spawnMpv(url);
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
    // The seed videoId playback started on while its playlist fetch is in
    // flight; the fetch handler merges around it instead of restarting audio.
    property string pendingSeedVid: ""

    function playUrl(url) {
        var parsed = YtMusic.parseYtUrl(url);
        if (!parsed)
            return false;
        root.session++;
        root.buffering = true;
        if (parsed.videoId) {
            // start now on the seed track; the queue fills when the playlist
            // lands. Take over the airwaves only when real audio starts.
            root.tookOverAt = Date.now();
            root.pauseOthers();
            root.pendingSeedVid = parsed.videoId;
            root.queue = [{ id: parsed.videoId, title: "", artist: "", album: "", cover: "", durationLabel: "" }];
            root.index = 0;
            root.startOrReplace(root.watchUrl(parsed.videoId));
        } else {
            // playlist-only link: nothing plays until the fetch resolves, so
            // leave whatever is on the air (ours or another player) alone; the
            // fetch handler pauses others when it actually has audio to start.
            root.pendingSeedVid = "";
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

    // Extract the 11-char videoId from a watch URL (for mapping mpv's playlist
    // entries back to our track objects after a shuffle).
    function videoIdFromUrl(url) {
        var m = String(url || "").match(/v=([A-Za-z0-9_-]{11})/);
        return m ? m[1] : "";
    }

    // Toggle shuffle on the current queue. mpv does the reorder (keeping history
    // and prev/next intact) and we re-sync our queue from its new playlist order
    // (the SYNC request below), so the card's cover/title stay correct.
    readonly property int syncReqId: 42
    function toggleShuffle() {
        if (!root.active)
            return;
        root.shuffled = !root.shuffled;
        root.mpvCmd([root.shuffled ? "playlist-shuffle" : "playlist-unshuffle"]);
        // request the reordered playlist tagged with syncReqId; the reply handler
        // in onMpvLine rebuilds our queue to match mpv's new order.
        if (mpvSock.connected)
            mpvSock.write(JSON.stringify({ command: ["get_property", "playlist"], request_id: root.syncReqId }) + "\n");
    }

    // Stop for good: kill mpv and clear. Used on explicit stop only; a shell
    // reload deliberately leaves mpv playing for the next instance to adopt.
    function stop() {
        root.queue = [];
        root.index = 0;
        root.buffering = false;
        root.shuffled = false;
        root.pending = [];
        root.pendingSeedVid = "";
        root.engineUp = false;
        sockDial.stop();
        sockDial.tries = 0;
        mpvSock.connected = false;
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
            // a buffered write with no dial running would strand forever (the
            // old give-up path); re-arm so the queue drains once mpv answers.
            if (root.lastSpawnUrl.length > 0 && !sockDial.running) {
                sockDial.tries = 0;
                sockDial.start();
            }
        }
    }
    function flushPending() {
        var q = root.pending;
        root.pending = [];
        for (var i = 0; i < q.length; i++)
            mpvSock.write(q[i]);
    }

    // The persistent audio mpv, spawned DETACHED so it outlives this quickshell
    // instance: a hot-reload tears the QML tree (and any declarative Process
    // child with it) but must not silence the music; the next instance adopts
    // the running mpv over the socket instead. `--idle=yes` keeps mpv alive
    // when the queue drains before radio refills; the IPC server is how we
    // append and observe; the ryotunes audio-client-name gives our stream a
    // stable MPRIS bus name (see isOurPlayer).
    property string lastSpawnUrl: ""
    property string respawnAfterKill: ""
    function spawnMpv(url) {
        // a stop()'s pkill may still be sweeping the socket pattern; spawning
        // into that window would kill the fresh mpv. Park the url until the
        // sweep finishes.
        if (killProc.running) {
            root.respawnAfterKill = url;
            return;
        }
        root.lastSpawnUrl = url;
        Quickshell.execDetached(["mpv", "--no-video", "--no-terminal", "--force-window=no",
            "--audio-display=no", "--idle=yes", "--volume=100",
            "--audio-client-name=ryotunes",
            "--cache=yes", "--network-timeout=20",
            // open the next queue entry only as the current one nears its end
            // (initial connect + ytdl resolve, not an early full download), so the
            // next track starts gaplessly without stealing bandwidth mid-song.
            "--prefetch-playlist=yes",
            "--input-ipc-server=" + root.ipcSocket,
            "--ytdl-format=bestaudio/best", url]);
        sockDial.tries = 0;
        sockDial.maxTries = 60;
        sockDial.start();
    }

    // mpv creates the IPC socket a beat after launch; dial until it answers.
    // On give-up after a spawn: one respawn attempt, then a clean stop so the
    // engine state and the process agree. On give-up of the startup adoption
    // probe (nothing was spawned): fall through to the orphan sweep.
    Timer {
        id: sockDial
        interval: 120
        repeat: true
        property int tries: 0
        property int maxTries: 60
        property bool respawned: false
        onTriggered: {
            if (mpvSock.connected) { sockDial.stop(); tries = 0; return; }
            if (++tries > maxTries) {
                sockDial.stop();
                tries = 0;
                if (root.lastSpawnUrl.length > 0 && !respawned) {
                    respawned = true;
                    var u = root.lastSpawnUrl;
                    root.lastSpawnUrl = "";
                    root.spawnMpv(u);
                } else {
                    root.stop();
                }
                return;
            }
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
                sockDial.respawned = false;
                root.engineUp = true;
                mpvSock.write(JSON.stringify({ command: ["observe_property", 1, "playlist-pos"] }) + "\n");
                // core-idle is true while mpv is loading/buffering and NOT actually
                // producing sound; observing it lets the card show a buffering state
                // and freeze the seekbar instead of ticking silently on a slow load.
                mpvSock.write(JSON.stringify({ command: ["observe_property", 2, "core-idle"] }) + "\n");
                root.flushPending();
                // connected with nothing played this session: an orphan from the
                // previous instance answered. Ask for its playlist; the reply
                // either adopts it (skeleton queue) or sweeps it away.
                if (root.queue.length === 0)
                    mpvSock.write(JSON.stringify({ command: ["get_property", "playlist"], request_id: root.adoptReqId }) + "\n");
            } else if (root.engineUp) {
                // socket EOF: mpv died (it is not our child anymore, so this is
                // the only death signal). Clear so active/upNext follow.
                root.engineUp = false;
                root.queue = [];
                root.index = 0;
                root.buffering = false;
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
        } else if (msg && msg.request_id === root.syncReqId && msg.data) {
            // reply to the shuffle's playlist request: rebuild our queue to mpv's
            // new order by mapping each entry's videoId back to our track object,
            // and set the index from the entry mpv marks `current`. An entry we
            // cannot map (e.g. an append that landed mid-shuffle) gets a skeleton
            // instead of being dropped, so q stays positionally congruent with
            // mpv and playlist-pos keeps indexing the right track.
            var byId = {};
            for (var i = 0; i < root.queue.length; i++)
                byId[root.queue[i].id] = root.queue[i];
            var q = [];
            var cur = root.index;
            for (var j = 0; j < msg.data.length; j++) {
                var vid = root.videoIdFromUrl(msg.data[j].filename);
                if (!vid)
                    continue;
                var t = byId[vid] || root.skeletonTrack(vid);
                q.push(t);
                if (msg.data[j].current)
                    cur = q.length - 1;
            }
            if (q.length > 0) {
                root.queue = q;
                root.index = cur;
            }
        } else if (msg && msg.request_id === root.adoptReqId) {
            // reply to the startup adoption probe: an orphan mpv from the last
            // instance is alive on our socket. If its playlist is ours (watch
            // URLs), rebuild a skeleton queue and keep the music playing; rich
            // metadata degrades gracefully (mpv's resolved title, ytimg cover)
            // and the radio keeps extending from the tail. Anything else is
            // swept away as before.
            var aq = [];
            var acur = 0;
            var entries = Array.isArray(msg.data) ? msg.data : [];
            for (var k = 0; k < entries.length; k++) {
                var avid = root.videoIdFromUrl(entries[k].filename);
                if (!avid)
                    continue;
                aq.push(root.skeletonTrack(avid));
                if (entries[k].current)
                    acur = aq.length - 1;
            }
            if (aq.length > 0 && root.queue.length === 0) {
                root.queue = aq;
                root.index = acur;
            } else if (root.queue.length === 0) {
                root.stop();
            }
        }
    }

    // Minimal track object for an mpv playlist entry we have no metadata for:
    // adopted after a reload, or appended while a shuffle snapshot was in
    // flight. The ytimg thumb is real cover art (16:9 instead of square).
    function skeletonTrack(vid) {
        return { id: vid, title: "", artist: "", album: "", cover: "https://i.ytimg.com/vi/" + vid + "/hqdefault.jpg", durationLabel: "" };
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
                        root.pendingSeedVid = "";
                        return;
                    }
                    var seed = root.pendingSeedVid;
                    root.pendingSeedVid = "";
                    if (seed) {
                        // audio already started on the seed; never restart it.
                        // YT Music routinely substitutes an equivalent videoId
                        // for the seed, so find it anywhere in the playlist and
                        // merge around it instead of comparing to tracks[0].
                        var i0 = -1;
                        for (var s = 0; s < tracks.length; s++)
                            if (tracks[s].id === seed) { i0 = s; break; }
                        var tail;
                        if (i0 >= 0) {
                            root.queue = tracks.slice(i0);
                            tail = tracks.slice(i0 + 1);
                        } else {
                            root.queue = [root.queue[0]].concat(tracks);
                            tail = tracks;
                        }
                        root.index = 0;
                        for (var k = 0; k < tail.length; k++)
                            root.mpvCmd(["loadfile", root.watchUrl(tail[k].id), "append"]);
                    } else {
                        // playlist-only link: replacement audio is real now, so
                        // this is the moment to take over the airwaves.
                        root.tookOverAt = Date.now();
                        root.pauseOthers();
                        root.startOrReplace(root.watchUrl(tracks[0].id));
                        for (var p = 1; p < tracks.length; p++)
                            root.mpvCmd(["loadfile", root.watchUrl(tracks[p].id), "append"]);
                        root.queue = tracks;
                        root.index = 0;
                    }
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
        running: root.engineUp
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

    // pkill fallback + socket cleanup for explicit stop() and failed adoption.
    Process {
        id: killProc
        command: ["sh", "-c",
            "pkill -f 'mpv.*ryoku-ytmusic-mpv\\.sock' 2>/dev/null; " +
            "i=0; while [ $i -lt 20 ] && pgrep -f 'mpv.*ryoku-ytmusic-mpv\\.sock' >/dev/null 2>&1; do sleep 0.05; i=$((i+1)); done; " +
            "rm -f " + root.ipcSocket + "; true"]
        onExited: {
            // a play() that landed mid-sweep parked its url here (spawnMpv).
            if (root.respawnAfterKill.length > 0) {
                var u = root.respawnAfterKill;
                root.respawnAfterKill = "";
                root.spawnMpv(u);
            }
        }
    }

    // Adoption probe id for the startup playlist request (see the socket's
    // connected branch and onMpvLine).
    readonly property int adoptReqId: 43

    // Startup: probe the socket briefly instead of pkilling on sight. A live
    // mpv from the previous instance (hot-reload, daemon restart) answers and
    // gets adopted, so the music never stops; a dead socket or a foreign
    // playlist falls through to the sweep via sockDial's give-up -> stop().
    // The 2s guard covers a connect that never gets a playlist reply.
    Timer {
        id: adoptGuard
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.queue.length === 0 && root.engineUp)
                root.stop();
        }
    }
    Component.onCompleted: {
        sockDial.tries = 0;
        sockDial.maxTries = 6;
        sockDial.start();
        adoptGuard.start();
    }
}
