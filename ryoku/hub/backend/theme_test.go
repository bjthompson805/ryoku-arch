package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// healThemeLua: a pre-migration theme.lua (decoration nuances as raw Lua) must
// fold its values into still-default store fields and be rewritten from the
// migrated, motion-only init.lua, exactly once. a user-diverged field keeps its
// value (settings.lua already wins over theme.lua for it).
func TestHealThemeLua(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)

	themeDir := filepath.Join(dir, "hypr", "themes", "probe")
	if err := os.MkdirAll(themeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile := func(path, s string) {
		t.Helper()
		if err := os.WriteFile(path, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeFile(filepath.Join(themeDir, "theme.json"),
		`{"name":"Probe","look":{"roundingPower":2,"blurVibrancy":0.08,"blurNoise":0}}`)
	writeFile(filepath.Join(themeDir, "init.lua"),
		"hl.curve(\"ryokuTheme\", { type = \"bezier\", points = { { 0.16, 1.0 }, { 0.3, 1.0 } } })\n")
	writeFile(filepath.Join(dir, "hypr", "theme.lua"),
		"hl.config({ decoration = { rounding_power = 2, blur = { vibrancy = 0.08, noise = 0.0 } } })\n")
	saveThemeState(themeState{Slug: "probe", FollowWallpaper: true})

	o := defaultOverrides()
	o.Appearance.BlurNoise = 0.05 // user-diverged: must survive the fold
	if !healThemeLua(&o) {
		t.Fatal("stale theme.lua was not healed")
	}
	if o.Appearance.RoundingPower != 2 || o.Appearance.BlurVibrancy != 0.08 {
		t.Errorf("nuances not folded: power=%v vibrancy=%v", o.Appearance.RoundingPower, o.Appearance.BlurVibrancy)
	}
	if o.Appearance.BlurNoise != 0.05 {
		t.Errorf("user-diverged noise clobbered: %v", o.Appearance.BlurNoise)
	}
	cur, err := os.ReadFile(filepath.Join(dir, "hypr", "theme.lua"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(cur), "hl.config") || !strings.Contains(string(cur), "hl.curve") {
		t.Errorf("theme.lua not refreshed from init.lua:\n%s", cur)
	}
	// healed copy carries no hl.config -> second run is a no-op.
	if healThemeLua(&o) {
		t.Error("heal ran twice")
	}
}

// no active theme, or a theme whose installed init.lua is itself still
// pre-migration, must leave everything alone.
func TestHealThemeLuaBailsCleanly(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", dir)
	o := defaultOverrides()
	if healThemeLua(&o) {
		t.Error("healed with no theme state")
	}

	themeDir := filepath.Join(dir, "hypr", "themes", "probe")
	if err := os.MkdirAll(themeDir, 0o755); err != nil {
		t.Fatal(err)
	}
	stale := "hl.config({ decoration = { rounding_power = 2 } })\n"
	if err := os.WriteFile(filepath.Join(themeDir, "theme.json"), []byte(`{"name":"Probe"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(themeDir, "init.lua"), []byte(stale), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "hypr", "theme.lua"), []byte(stale), 0o644); err != nil {
		t.Fatal(err)
	}
	saveThemeState(themeState{Slug: "probe", FollowWallpaper: true})
	if healThemeLua(&o) {
		t.Error("healed against an unmigrated installed theme")
	}
	cur, _ := os.ReadFile(filepath.Join(dir, "hypr", "theme.lua"))
	if string(cur) != stale {
		t.Errorf("theme.lua touched on bail:\n%s", cur)
	}
}
