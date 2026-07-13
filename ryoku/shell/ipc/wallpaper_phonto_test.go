package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Setting a video shows the clip through awww (its own first frame) plus the
// GPU's video daemon on top, and does NOT kill awww: the still under the video is
// the clip's content, so nothing stale bleeds through and a later image switch
// transitions from a real frame. Runs for both backends against recording
// stand-ins on PATH, forcing liveDaemon so it is GPU-independent and never touches
// the real wallpaper daemon.
func TestShowLiveWallpaperHandoff(t *testing.T) {
	for _, backend := range []string{daemonPhonto, daemonMpvpaper} {
		t.Run(backend, func(t *testing.T) {
			bin := t.TempDir()
			state := t.TempDir()
			t.Setenv("XDG_CONFIG_HOME", t.TempDir()) // no ryowalls.json -> fill
			t.Setenv("XDG_STATE_HOME", state)        // isolate the extracted frame
			liveLog := filepath.Join(state, "live.args")
			awwwLog := filepath.Join(state, "awww.args")
			alive := filepath.Join(state, "live.alive")

			fake := func(name, body string) {
				if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			// backend records its argv + marks itself alive; pgrep reports the
			// marker; pkill clears it; ffmpeg (liveFrame) creates the frame file so
			// awww gets an `img`; awww answers `query` alive and records the rest.
			fake(backend, `printf '%s\n' "$*" > "`+liveLog+`"; : > "`+alive+`"`)
			fake("ffmpeg", `for a in "$@"; do o="$a"; done; : > "$o"`)
			fake("awww", `case "$1" in query) exit 0 ;; *) printf '%s\n' "$*" >> "`+awwwLog+`" ;; esac`)
			fake("pgrep", `[ -f "`+alive+`" ]`)
			fake("pkill", `rm -f "`+alive+`"; exit 0`)
			t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))

			orig := liveDaemon
			liveDaemon = backend
			t.Cleanup(func() { liveDaemon = orig })

			vid := filepath.Join(t.TempDir(), "clip.mp4")
			if err := os.WriteFile(vid, []byte("x"), 0o644); err != nil {
				t.Fatal(err)
			}
			if err := (&daemon{}).showLiveWallpaper(vid); err != nil {
				t.Fatalf("showLiveWallpaper: %v", err)
			}
			if got, err := os.ReadFile(liveLog); err != nil || !strings.Contains(string(got), vid) {
				t.Errorf("%s not launched with the clip: %q err=%v", backend, got, err)
			}
			aw, err := os.ReadFile(awwwLog)
			if err != nil || !strings.Contains(string(aw), "img") {
				t.Errorf("awww did not paint the clip's frame under the video: %q err=%v", aw, err)
			}
			if strings.Contains(string(aw), "kill") {
				t.Errorf("awww must stay up under the video (its still is the clip's frame), not be killed: %q", aw)
			}
		})
	}
}
