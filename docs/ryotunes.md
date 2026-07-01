# RyoTunes: free music, built in

RyoTunes is Ryoku's built-in free-music experience, built on YouTube Music. It is
not a separate app: it is the launcher's `@` search, a now-playing card, and one
engine singleton that ties them together, so "search a song" becomes "an endless
station" without leaving the command palette. There is no account, no key, and no
setup: YouTube Music's public endpoints are keyless.

The launcher surface (the `@` provider, the now-playing card) is documented in
`docs/launcher.md`; this file documents the engine and the behaviour behind it.

## What it does

- **Song-grade search, fast.** The `@` provider queries YouTube Music's InnerTube
  `WEB_REMIX` API (the same backend the web player uses) with `curl` and parses
  proper songs: clean title, separate artist/album, a duration, and **square album
  art inline**. That is markedly faster than the old `yt-dlp` search (~0.5s vs
  ~1.4s cold, no Python start-up) and returns songs instead of "(Official Video)"
  clips. A prefix cache shows the widest already-resolved prefix's rows the moment
  you keep typing, so refining a query feels instant.
- **Covers for free.** InnerTube ships the album art with the search result, so
  the row shows it and the now-playing card shows the exact square cover with no
  second lookup. (For *other* players that expose no art, e.g. a browser, the card
  still falls back to the keyless iTunes Search API, now noise-stripped.)
- **Endless radio.** Playing a track does not stop at the end of that track: the
  engine seeds a YouTube Music radio from it (the `/next` continuation, a ~50-track
  station) and keeps appending as the queue drains, so free music never stops.
- **Paste a link, play a playlist.** A pasted YouTube / YouTube Music URL (with or
  without the `@` prefix) becomes a one-tap play: a bare track link seeds its
  radio, a playlist or mix link (`?list=...`) queues the whole playlist through the
  same `/next` path. Played playlists are cached and shown as a **SAVED PLAYLISTS**
  chip row under the now-playing stack, so the full playlist replays instantly with
  one tap and no network round-trip; the `×` on a chip forgets it.
- **Real transport.** `mpv-mpris` publishes the stream as a first-class MPRIS
  player, so the now-playing card's Next/Prev and the media keys step the radio
  queue like any other player, the card shows an up-next peek, and the wavy
  seekbar is draggable to scrub (it seeks any player, not just ours). A **shuffle**
  toggle (lit when on) reorders the queue via mpv's own shuffle, and mpv prefetches
  the next track as the current one ends so playback is **gapless** without eating
  bandwidth mid-song on a slow link.
- **One control plane for every source.** The active player owns the full card;
  every other controllable player (a paused browser tab, Spotify) extends beneath
  it as a slim one-line strip (cover, title, a play button). Playing a YouTube
  track **takes over** (pauses the others so audio never stacks); tapping a strip
  switches back to that source. The card is sticky, so pausing it never makes it
  jump to a different player, and it shows a **buffering** state with a frozen
  seekbar so a slow load never ticks in silence.
- **System-audio synergy.** Whatever is already playing (Spotify, a browser video,
  any app) can seed a station: the now-playing row's **YT Radio** verb reads the
  current track's title/artist and starts an endless YouTube Music radio from it.
  Our own stream yields to other audio by fading out and pausing (not a hard kill),
  so hand-off between players is smooth and two streams never stack.

## Architecture

One engine, owned by the launcher, so both the search provider and the MPRIS
"YT Radio" verb feed the same player. View and logic stay split: the parsers are
pure JavaScript with `node` tests; the QML renders and drives processes.

- `quickshell/launcher/Singletons/Radio.qml` the engine (singleton). Owns one
  persistent `mpv` (audio only, `--idle=yes`) driven over its JSON IPC socket via
  Quickshell's native `Socket` (no `socat`). Keeps the ordered queue and the index
  `mpv` is on, observes `playlist-pos` to follow the current track and `core-idle`
  to know when it is buffering, fetches and appends radio continuations as the
  tail approaches, and exposes the current cover/title/artist, the up-next entry,
  and the buffering flag for the card. `toggleShuffle()` drives mpv's
  `playlist-shuffle`/`unshuffle` then re-syncs the queue from mpv's reordered
  playlist (by videoId) so metadata stays correct; mpv runs with
  `--prefetch-playlist=yes` for a gapless next track. Also the shared authority on
  players:
  `realPlayers()` (the `playerctld` proxy dropped and deduped by `dbusName`),
  `isOurPlayer()`, `pauseOthers()` (take-over), and the fade-yield. IPC writes are
  queued and flushed on connect, so a radio append that resolves before the socket
  is up is never dropped. Kills any orphan `mpv` on startup so a restart mid-play
  never leaves an unmanaged stream. Costs nothing at rest: nothing runs until the
  first play.
- `quickshell/launcher/providers/media/ytmusic/ytmusic.js` builds the InnerTube
  search body and parses the `musicResponsiveListItemRenderer` shelf into tracks
  (title, artist, album, duration, hi-res square cover); `parseFlat` keeps the
  `yt-dlp` NDJSON shape for the offline fallback; `radioBody`/`parseRadio` build
  and parse the `/next` continuation into the same track shape; `parseYtUrl` pulls
  the videoId/playlistId out of a pasted link, and `radioBody(videoId, playlistId)`
  queues an explicit playlist verbatim. Search, radio, and link parsing live in one
  file (QML has no `require`, so a split module could not share the helpers), pure
  and node-tested (`ytmusic.test.mjs`, `radio.test.mjs`).
- `quickshell/launcher/providers/media/ytmusic/YtMusic.qml` the `@` search
  provider: InnerTube `curl` + prefix cache + `yt-dlp` fallback, rows carry the
  cover, play hands off to `Radio`; a pasted link (`urlFallback`, gated by
  `lib/dispatch.js` `looksYtUrl`) short-circuits to a "Play" row that calls
  `Radio.playUrl`.
- `quickshell/launcher/Singletons/Playlists.qml` the saved-playlist cache: an LRU
  of resolved playlist/mix links (id, label, cover, track list) as JSON under the
  cache dir. `Radio` emits `playlistResolved` when a link's playlist lands and the
  launcher persists it here (a singleton reaching a sibling singleton via its own
  qmldir is unreliable, so the save is driven from the view layer).
- `quickshell/launcher/SavedPlaylists.qml` the chip row under the now-playing
  stack: recent saved playlists, tap to `Radio.playCached` (instant, no network),
  `×` to forget.
- `quickshell/launcher/MediaSources.qml` the slim strips under the card: one row
  per other real player (from `Radio.realPlayers()`), tap to switch source.
- `quickshell/launcher/providers/media/mpris/Mpris.qml` the now-playing row for any
  player, plus the **YT Radio** verb that calls `Radio.playFromText(...)`.
- `quickshell/launcher/NowPlaying.qml` the card: when `Radio.isOurs(player)` it
  shows the engine's exact cover, clean title/artist, up-next, and buffering;
  otherwise it renders the active MPRIS player and its cover (or the iTunes
  fallback), suppressing a raw `watch?v=` stream title.
- `quickshell/launcher/providers/media/albumart.js` the iTunes fallback for
  players with no art, stripping video noise (`(Official Video)`, `[HD]`,
  `feat. ...`) from the title first for a better match. Node-tested.

## Data flow

```
@query -> YtMusic.query
  -> prefix-cache hit shows rows now
  -> debounce -> curl InnerTube /search -> parse -> rows{icon: cover}
       (empty -> yt-dlp flat fallback)

play(track) -> Radio.play
  -> pauseOthers (take over)  -> mpv loadfile (reuse over IPC, else cold-start)
  -> curl InnerTube /next -> parseRadio -> loadfile append * (queue grows)

mpv IPC playlist-pos -> Radio.index -> card cover / up-next follow
           core-idle -> Radio.buffering -> card buffering + frozen seekbar
                     -> tail near? extendRadio (append more)

another player starts (past grace) -> fade mpv volume -> pause (yield)
tap a source strip -> resume it, pause the rest
MPRIS row "YT Radio" -> Radio.playFromText -> curl /search -> play first hit

paste link -> YtMusic linkRow -> Radio.playUrl(parseYtUrl)
  -> play seed now -> curl /next(playlistId) -> parseRadio -> queue = playlist
  -> playlistResolved -> Playlists.save (cache)
tap SAVED PLAYLISTS chip -> Radio.playCached(cached tracks)  [instant, no network]
```

## Requirements and limits

- Needs `yt-dlp` and `mpv` (with `mpv-mpris`), all in `system/packages/base.packages`;
  the `@` provider hides itself when they are absent. Search itself only needs
  `curl`. No new packages: the IPC path uses Quickshell's built-in `Socket`.
- InnerTube is an unofficial endpoint. It is stable in practice, but if a request
  is rejected (a stale client version, or a cold rate-limited machine) search
  falls back to `yt-dlp` and radio simply does not extend that round. A signed-in
  default browser lifts `yt-dlp`'s rate limit via `--cookies-from-browser`.
- Scope: this is the quick, always-playing path. Playlists, playlist import, a
  separate full-window deck, and library/likes sync are intentionally out of scope.
