package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIsVideo(t *testing.T) {
	cases := map[string]bool{
		"/x/a.mp4": true, "/x/a.MP4": true, "/x/a.webm": true,
		"/x/a.mkv": true, "/x/a.mov": true,
		"/x/a.jpg": false, "/x/a.png": false, "/x/a.gif": false, "/x/plain": false,
	}
	for p, want := range cases {
		if got := isVideo(p); got != want {
			t.Errorf("isVideo(%q) = %v, want %v", p, got, want)
		}
	}
}

func TestFrameOffset(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_STATE_HOME", dir)
	tune := filepath.Join(dir, "ryoku-wallust.json")
	video := "/home/x/Pictures/livewalls/clip.mp4"

	// no tune -> the auto default
	if got := frameOffset(video); got != "1" {
		t.Fatalf("no tune: got %q want 1", got)
	}
	// a tune for this video -> its chosen second
	_ = os.WriteFile(tune, []byte(`{"image":"`+video+`","frame":3.5}`), 0o644)
	if got := frameOffset(video); got != "3.50" {
		t.Fatalf("matching tune: got %q want 3.50", got)
	}
	// a tune keyed to another video never bleeds across
	if got := frameOffset("/home/x/other.mp4"); got != "1" {
		t.Fatalf("other video: got %q want 1", got)
	}
	// frame 0 falls back to the default
	_ = os.WriteFile(tune, []byte(`{"image":"`+video+`","frame":0}`), 0o644)
	if got := frameOffset(video); got != "1" {
		t.Fatalf("zero frame: got %q want 1", got)
	}
}

// livePlaybackOpts must emit native, smooth mpv options: GPU decode (hwdec),
// cheap scalers (profile=fast), and playback at the clip's own rate. It must NOT
// carry video-sync=display-resample, which needs a display fps mpvpaper's libmpv
// render path never reports, so it ran blind and juddered.
func TestLivePlaybackOpts(t *testing.T) {
	cfg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", cfg)
	rj := filepath.Join(cfg, "ryoku", "ryowalls.json")
	if err := os.MkdirAll(filepath.Dir(rj), 0o755); err != nil {
		t.Fatal(err)
	}

	// default (no config): native/smooth, fill, and the clip's own rate.
	opts := livePlaybackOpts("/run/sock")
	for _, must := range []string{"hwdec=auto", "profile=fast", "no-audio", "loop-file=inf", "panscan=1.0", "input-ipc-server=/run/sock"} {
		if !strings.Contains(opts, must) {
			t.Errorf("default opts missing %q: %s", must, opts)
		}
	}
	if strings.Contains(opts, "display-resample") {
		t.Errorf("display-resample must be gone (mpvpaper reports no display fps, so it juddered): %s", opts)
	}
	if strings.Contains(opts, "vf=fps") {
		t.Errorf("default (60 fps) must play at the native rate, no fps filter: %s", opts)
	}

	// fit -> letterbox (panscan 0.0) instead of fill.
	if err := os.WriteFile(rj, []byte(`{"liveFit":"fit"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if opts := livePlaybackOpts("/run/sock"); !strings.Contains(opts, "panscan=0.0") {
		t.Errorf("fit must set panscan=0.0: %s", opts)
	}

	// a sub-60 cap adds the fps filter for battery.
	if err := os.WriteFile(rj, []byte(`{"liveFps":30}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if opts := livePlaybackOpts("/run/sock"); !strings.Contains(opts, "vf=fps=30") {
		t.Errorf("liveFps=30 must cap via vf=fps=30: %s", opts)
	}
}
