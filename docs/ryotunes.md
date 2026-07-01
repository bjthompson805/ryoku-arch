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
- **Real transport.** `mpv-mpris` publishes the stream as a first-class MPRIS
  player, so the now-playing card's Next/Prev and the media keys step the radio
  queue like any other player, and the card shows an up-next peek.
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
  `mpv` is on, observes `playlist-pos` to follow the current track, fetches and
  appends radio continuations as the tail approaches, and exposes the current
  cover/title/artist plus the up-next entry for the card. Costs nothing at rest:
  nothing runs until the first play.
- `quickshell/launcher/providers/media/ytmusic/`
  - `ytmusic.js` builds the InnerTube search body and parses the
    `musicResponsiveListItemRenderer` shelf into tracks (title, artist, album,
    duration, hi-res square cover); `parseFlat` keeps the `yt-dlp` NDJSON shape for
    the offline fallback. Pure, node-tested (`ytmusic.test.mjs`).
  - `radio.js` builds the `/next` continuation body and parses the
    `playlistPanelVideoRenderer` queue into the same track shape. Pure, node-tested
    (`radio.test.mjs`).
  - `YtMusic.qml` the `@` search provider: InnerTube `curl` + prefix cache +
    `yt-dlp` fallback, rows carry the cover, play hands off to `Radio`.
- `quickshell/launcher/providers/media/mpris/Mpris.qml` the now-playing row for any
  player, plus the **YT Radio** verb that calls `Radio.playFromText(...)`.
- `quickshell/launcher/NowPlaying.qml` the card: when `Radio.isOurs(player)` it
  shows the engine's exact cover, clean title/artist, and the up-next peek;
  otherwise it renders the active MPRIS player and its cover (or the iTunes
  fallback).
- `quickshell/launcher/providers/media/albumart.js` the iTunes fallback for
  players with no art, now stripping video noise (`(Official Video)`, `[HD]`,
  `feat. ...`) from the title first for a better match. Node-tested.

## Data flow

```
@query -> YtMusic.query
  -> prefix-cache hit shows rows now
  -> debounce -> curl InnerTube /search -> ytmusic.parse -> rows{icon: cover}
       (empty -> yt-dlp flat fallback)

play(track) -> Radio.play
  -> mpv loadfile (reuse running mpv over IPC, else cold-start)
  -> curl InnerTube /next -> radio.parseRadio -> loadfile append * (queue grows)

mpv IPC playlist-pos event -> Radio.index -> card cover / up-next follow
                           -> tail near? extendRadio (append more)

another player starts -> fade mpv volume -> pause (yield)

MPRIS row "YT Radio" -> Radio.playFromText -> curl /search -> play first hit
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
