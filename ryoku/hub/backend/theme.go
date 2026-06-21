package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Themes are full-system "rices": each lives in its own folder under
// ~/.config/hypr/themes/<slug>/ with a theme.json (metadata + the Hyprland look)
// and, for fixed-palette themes, a colors.json (the 16-colour scheme). Applying a
// theme reuses the override engine: it sets the appearance store (so the Look and
// Borders tabs reflect it and can be fine-tuned on top) and, when the palette is
// fixed, writes the wallust dsts every consumer already reads (colors.json for the
// live visualiser, current-theme.conf for kitty) and locks the palette so a
// wallpaper change does not overwrite it. The shell frame and island keep their
// own brand look by design.

// ThemeFile is themes/<slug>/theme.json.
type ThemeFile struct {
	Name   string          `json:"name"`
	Blurb  string          `json:"blurb"`
	Tags   []string        `json:"tags"`
	Fixed  bool            `json:"fixed"`
	Accent string          `json:"accent"`
	Swatch []string        `json:"swatch"`
	Look   json.RawMessage `json:"look"`
}

// ThemeListItem is the GUI-facing summary (no look payload).
type ThemeListItem struct {
	Slug   string   `json:"slug"`
	Name   string   `json:"name"`
	Blurb  string   `json:"blurb"`
	Tags   []string `json:"tags"`
	Fixed  bool     `json:"fixed"`
	Accent string   `json:"accent"`
	Swatch []string `json:"swatch"`
	Active bool     `json:"active"`
}

type themeState struct {
	Slug  string `json:"slug"`
	Fixed bool   `json:"fixed"`
}

func themesDir() string { return filepath.Join(hyprConfigDir(), "themes") }

func wallustCacheDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "wallust")
}

func kittyThemePath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "kitty", "current-theme.conf")
}

func themeStatePath() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(base, "ryoku", "theme.json")
}

func wallpaperStatePath() string {
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(base, "ryoku-wallpaper")
}

func activeThemeSlug() string {
	var s themeState
	if b, err := os.ReadFile(themeStatePath()); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	return s.Slug
}

func loadThemeFile(slug string) (ThemeFile, error) {
	var t ThemeFile
	b, err := os.ReadFile(filepath.Join(themesDir(), slug, "theme.json"))
	if err != nil {
		return t, err
	}
	return t, json.Unmarshal(b, &t)
}

func listThemes() []ThemeListItem {
	active := activeThemeSlug()
	entries, _ := os.ReadDir(themesDir())
	out := []ThemeListItem{}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		t, err := loadThemeFile(e.Name())
		if err != nil {
			continue
		}
		out = append(out, ThemeListItem{
			Slug: e.Name(), Name: t.Name, Blurb: t.Blurb, Tags: t.Tags,
			Fixed: t.Fixed, Accent: t.Accent, Swatch: t.Swatch, Active: e.Name() == active,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// applyTheme loads the theme, folds its look onto the default appearance, sets the
// palette (fixed: write the wallust dsts + lock; wallpaper-driven: re-derive from
// the current wallpaper), persists the store, regenerates settings.lua, and
// applies live.
func applyTheme(slug string) error {
	dir := filepath.Join(themesDir(), slug)
	tf, err := loadThemeFile(slug)
	if err != nil {
		return fmt.Errorf("theme %q: %w", slug, err)
	}

	o := loadOverrides()
	app := defaultOverrides().Appearance
	if len(tf.Look) > 0 {
		if err := json.Unmarshal(tf.Look, &app); err != nil {
			return fmt.Errorf("theme %q look: %w", slug, err)
		}
	}

	if tf.Fixed {
		pal, err := loadPalette(filepath.Join(dir, "colors.json"))
		if err != nil {
			return fmt.Errorf("theme %q palette: %w", slug, err)
		}
		app.FollowWallpaper = false
		if tf.Accent != "" {
			app.ActiveBorder = tf.Accent
		}
		if bg := pal["background"]; bg != "" {
			app.InactiveBorder = bg
		}
		if err := os.MkdirAll(wallustCacheDir(), 0o755); err != nil {
			return err
		}
		_ = atomicWrite(filepath.Join(wallustCacheDir(), "colors.json"), mustJSON(pal), 0o644)
		_ = atomicWrite(kittyThemePath(), []byte(renderKitty(pal)), 0o644)
	} else {
		app.FollowWallpaper = true
		if pic := currentWallpaper(); pic != "" {
			_ = exec.Command("wallust", "run", pic).Run()
		}
	}

	o.Appearance = app
	if err := saveOverrides(o); err != nil {
		return err
	}
	if err := writeGeneratedLua(o); err != nil {
		return err
	}
	_ = atomicWrite(themeStatePath(), mustJSON(themeState{Slug: slug, Fixed: tf.Fixed}), 0o644)

	hyprReload()
	_ = exec.Command("pkill", "-USR1", "-x", "kitty").Run()
	return nil
}

func loadPalette(path string) (map[string]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m map[string]string
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, err
	}
	return m, nil
}

// renderKitty fills kitty's current-theme.conf from the palette (cursor follows
// the foreground), matching the wallust kitty template.
func renderKitty(p map[string]string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "background %s\n", p["background"])
	fmt.Fprintf(&b, "foreground %s\n", p["foreground"])
	fmt.Fprintf(&b, "cursor %s\n", p["foreground"])
	fmt.Fprintf(&b, "cursor_text_color %s\n", p["background"])
	fmt.Fprintf(&b, "selection_background %s\n", p["color8"])
	fmt.Fprintf(&b, "selection_foreground %s\n", p["foreground"])
	for i := 0; i < 16; i++ {
		key := fmt.Sprintf("color%d", i)
		fmt.Fprintf(&b, "%s %s\n", key, p[key])
	}
	return b.String()
}

func currentWallpaper() string {
	b, err := os.ReadFile(wallpaperStatePath())
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func mustJSON(v any) []byte {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return []byte("{}")
	}
	return b
}
