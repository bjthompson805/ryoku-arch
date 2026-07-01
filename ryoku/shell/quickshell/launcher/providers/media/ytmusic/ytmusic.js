// Parse YouTube Music's InnerTube search into track rows. The launcher POSTs to
// the keyless WEB_REMIX `/youtubei/v1/search` endpoint (songs filter) and parses
// the `musicResponsiveListItemRenderer` shelf here: proper songs with a clean
// title, separate artist/album, a duration label, and square album art inline
// (no second cover lookup). Pure so the parse is node-tested without the network.
// `parseFlat` keeps the old yt-dlp NDJSON shape for the offline fallback path.
// Consumed by YtMusic.qml.

// The InnerTube "songs" search filter (base64 protobuf). Restricts results to
// tracks, so no channels/albums/videos leak into the row list.
var SONGS_PARAMS = "EgWKAQIIAWoKEAkQBRAKEAMQBA==";
// Renderer type words that can lead the byline; dropped so artist reads first.
var TYPE_WORDS = { "Song": 1, "Video": 1, "Single": 1, "EP": 1, "Album": 1, "Playlist": 1, "Artist": 1 };

// Body for the search POST. WEB_REMIX is YouTube Music's own web client; the
// version only needs to be plausible. The songs filter keeps results clean.
function innertubeBody(query) {
    return JSON.stringify({
        context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00", hl: "en", gl: "US" } },
        query: String(query == null ? "" : query),
        params: SONGS_PARAMS
    });
}

// Swap a googleusercontent thumbnail to a cover-sized square. The size rides in
// the URL as `wNNN-hNNN`; search art is served at w120, so bump every size token
// to 544 for a crisp card and row cover. No-op on URLs without the token.
function hiResCover(url) {
    var u = String(url == null ? "" : url);
    return u.replace(/w\d+-h\d+/g, "w544-h544");
}

// "m:ss" -> seconds; "" or malformed -> 0. Handles "h:mm:ss" too.
function clockToSec(label) {
    var s = String(label == null ? "" : label).trim();
    if (!/^\d+(:\d{1,2})+$/.test(s))
        return 0;
    var parts = s.split(":");
    var sec = 0;
    for (var i = 0; i < parts.length; i++)
        sec = sec * 60 + parseInt(parts[i], 10);
    return sec;
}

// seconds -> "m:ss"; 0/blank -> "".
function fmtDuration(sec) {
    if (!(sec > 0))
        return "";
    var s = Math.floor(sec);
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + ":" + (r < 10 ? "0" + r : r);
}

// Join a runs[] array's text into one string.
function runsText(runs) {
    if (!runs || !runs.length)
        return "";
    var out = "";
    for (var i = 0; i < runs.length; i++)
        out += (runs[i] && runs[i].text) ? runs[i].text : "";
    return out;
}

// Recursively collect every value stored under `key` anywhere in `obj`. Used to
// dig the videoId out of a renderer's play-button endpoint without hardcoding the
// deep path (which YouTube reshuffles).
function firstKey(obj, key) {
    var stack = [obj];
    while (stack.length) {
        var o = stack.pop();
        if (!o || typeof o !== "object")
            continue;
        if (Object.prototype.hasOwnProperty.call(o, key) && typeof o[key] === "string")
            return o[key];
        for (var k in o)
            if (o[k] && typeof o[k] === "object")
                stack.push(o[k]);
    }
    return "";
}

// Split a byline ("Artist • Album • 3:47") into { artist, album, durationLabel }.
// The dot-separated segments vary: a leading type word ("Song") is dropped, a
// trailing m:ss is the duration, the first remaining segment is the artist (kept
// whole so multi-artist "A, B & C" survives), the next is the album.
function splitByline(text) {
    var parts = String(text == null ? "" : text).split("\u2022");
    var clean = [];
    for (var i = 0; i < parts.length; i++) {
        var p = parts[i].trim();
        if (p.length)
            clean.push(p);
    }
    if (clean.length && TYPE_WORDS[clean[0]])
        clean.shift();
    var durationLabel = "";
    if (clean.length && /^\d+(:\d{1,2})+$/.test(clean[clean.length - 1]))
        durationLabel = clean.pop();
    return {
        artist: clean.length ? clean[0] : "",
        album: clean.length > 1 ? clean[1] : "",
        durationLabel: durationLabel
    };
}

// Collect the shelf's musicResponsiveListItemRenderer entries in document order.
function collectRenderers(obj) {
    var out = [];
    var stack = [obj];
    // depth-first but order-preserving: push children reversed so siblings pop
    // left-to-right, keeping the on-screen result order.
    while (stack.length) {
        var o = stack.pop();
        if (!o || typeof o !== "object")
            continue;
        if (o.musicResponsiveListItemRenderer)
            out.push(o.musicResponsiveListItemRenderer);
        var keys = Object.keys(o);
        for (var i = keys.length - 1; i >= 0; i--) {
            var v = o[keys[i]];
            if (v && typeof v === "object")
                stack.push(v);
        }
    }
    return out;
}

// One search renderer -> track, or null if it has no playable videoId (an album
// or artist card that slipped past the filter).
function trackFromRenderer(r) {
    var cols = r.flexColumns || [];
    function colText(i) {
        var c = cols[i] && cols[i].musicResponsiveListItemFlexColumnRenderer;
        return c ? runsText(c.text && c.text.runs) : "";
    }
    var title = colText(0);
    var videoId = firstKey(r, "videoId");
    if (!videoId || !title)
        return null;
    var meta = splitByline(colText(1));
    var thumbs = ((((r.thumbnail || {}).musicThumbnailRenderer || {}).thumbnail || {}).thumbnails) || [];
    var cover = thumbs.length ? hiResCover(thumbs[thumbs.length - 1].url) : "";
    return {
        id: videoId,
        title: title,
        artist: meta.artist,
        album: meta.album,
        duration: clockToSec(meta.durationLabel),
        durationLabel: meta.durationLabel,
        cover: cover
    };
}

// Parse an InnerTube search response body into tracks. Malformed JSON, an empty
// shelf, or non-song cards all resolve to a (possibly empty) array, never throw.
function parse(text) {
    var obj;
    try {
        obj = JSON.parse(String(text == null ? "" : text));
    } catch (e) {
        return [];
    }
    var renderers = collectRenderers(obj);
    var out = [];
    var seen = {};
    for (var i = 0; i < renderers.length; i++) {
        var t = trackFromRenderer(renderers[i]);
        if (t && !seen[t.id]) {
            seen[t.id] = 1;
            out.push(t);
        }
    }
    return out;
}

// Fallback parser: yt-dlp `--flat-playlist -j` NDJSON (one JSON object per line),
// used when InnerTube is unreachable. Keeps only plausible songs by duration and
// carries the video thumbnail as a best-effort cover (16:9, unlike the square
// InnerTube art, but better than nothing). Malformed lines are skipped.
var FLAT_MIN_SEC = 30;
var FLAT_MAX_SEC = 600;
function parseFlat(text) {
    var lines = String(text == null ? "" : text).split("\n");
    var out = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0)
            continue;
        var o;
        try {
            o = JSON.parse(line);
        } catch (e) {
            continue;
        }
        if (!o || !o.id || !o.title)
            continue;
        var dur = typeof o.duration === "number" ? o.duration : 0;
        if (dur > 0 && (dur < FLAT_MIN_SEC || dur > FLAT_MAX_SEC))
            continue;
        var cover = "";
        if (o.thumbnails && o.thumbnails.length)
            cover = o.thumbnails[o.thumbnails.length - 1].url || "";
        out.push({
            id: o.id,
            title: o.title,
            artist: o.uploader || o.channel || o.artist || "",
            album: "",
            duration: dur,
            durationLabel: fmtDuration(dur),
            cover: cover
        });
    }
    return out;
}

// --- Radio continuation (the /next endpoint) ---
// Merged here (not a sibling file) because QML has no `require`: a separate
// module could not pull in the shared helpers above, so every radio track parsed
// empty. One file, one set of helpers, works in both QML and node.

// A track's radio playlist id: "RDAMVM" + the seed videoId (its auto station).
function radioPlaylistId(videoId) {
    return "RDAMVM" + String(videoId == null ? "" : videoId);
}

// Body for the continuation POST. isAudioOnly trims video-only entries.
function radioBody(videoId) {
    return JSON.stringify({
        context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00", hl: "en", gl: "US" } },
        videoId: String(videoId == null ? "" : videoId),
        playlistId: radioPlaylistId(videoId),
        isAudioOnly: true
    });
}

// Collect playlistPanelVideoRenderer entries in queue order.
function collectPanelRenderers(obj) {
    var out = [];
    var stack = [obj];
    while (stack.length) {
        var o = stack.pop();
        if (!o || typeof o !== "object")
            continue;
        if (o.playlistPanelVideoRenderer)
            out.push(o.playlistPanelVideoRenderer);
        var keys = Object.keys(o);
        for (var i = keys.length - 1; i >= 0; i--) {
            var v = o[keys[i]];
            if (v && typeof v === "object")
                stack.push(v);
        }
    }
    return out;
}

// One radio renderer -> track, or null without a videoId. lengthText is explicit;
// the byline carries artist/album. Radio art is served up to w544 already.
function radioTrackFromRenderer(r) {
    var videoId = r.videoId || "";
    var title = runsText(r.title && r.title.runs);
    if (!videoId || !title)
        return null;
    var meta = splitByline(runsText(r.longBylineText && r.longBylineText.runs));
    var lengthLabel = runsText(r.lengthText && r.lengthText.runs);
    var thumbs = ((r.thumbnail || {}).thumbnails) || [];
    var cover = thumbs.length ? hiResCover(thumbs[thumbs.length - 1].url) : "";
    return {
        id: videoId,
        title: title,
        artist: meta.artist,
        album: meta.album,
        duration: clockToSec(lengthLabel),
        durationLabel: lengthLabel,
        cover: cover
    };
}

// Parse a `/next` response into a de-duplicated track queue. Malformed/empty -> [].
function parseRadio(text) {
    var obj;
    try {
        obj = JSON.parse(String(text == null ? "" : text));
    } catch (e) {
        return [];
    }
    var renderers = collectPanelRenderers(obj);
    var out = [];
    var seen = {};
    for (var i = 0; i < renderers.length; i++) {
        var t = radioTrackFromRenderer(renderers[i]);
        if (t && !seen[t.id]) {
            seen[t.id] = 1;
            out.push(t);
        }
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { parse, parseFlat, innertubeBody, hiResCover, clockToSec, fmtDuration, splitByline, runsText, SONGS_PARAMS, parseRadio, radioBody, radioPlaylistId };
}
