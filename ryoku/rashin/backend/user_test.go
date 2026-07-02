package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func seedTree(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for rel, content := range files {
		p := filepath.Join(root, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestDiffUserConfig(t *testing.T) {
	base, cfg := t.TempDir(), t.TempDir()
	seedTree(t, base, map[string]string{
		"hypr/hyprland.lua": "shipped",
		"kitty/kitty.conf":  "shipped",
		"fish/config.fish":  "shipped",
	})
	seedTree(t, cfg, map[string]string{
		"hypr/hyprland.lua": "user edited", // modified
		"kitty/kitty.conf":  "shipped",     // untouched
		"hypr/user.lua":     "user override",
		// fish/config.fish deleted
	})

	d, err := diffUserConfig(base, cfg)
	if err != nil {
		t.Fatal(err)
	}
	if len(d.Modified) != 1 || d.Modified[0] != "hypr/hyprland.lua" {
		t.Fatalf("modified = %v", d.Modified)
	}
	if len(d.Missing) != 1 || d.Missing[0] != "fish/config.fish" {
		t.Fatalf("missing = %v", d.Missing)
	}
	if len(d.Overrides) != 1 || d.Overrides[0] != "hypr/user.lua" {
		t.Fatalf("overrides = %v", d.Overrides)
	}
}

func TestUserDocBodyWithoutBase(t *testing.T) {
	t.Setenv("RYOKU_CONFIG_BASE", filepath.Join(t.TempDir(), "absent"))
	body := userDocBody()
	if !strings.Contains(body, "diffing is unavailable") {
		t.Fatalf("expected unavailable note, got:\n%s", body)
	}
}

func TestUserDocBodyCleanBaseline(t *testing.T) {
	base := t.TempDir()
	cfg := t.TempDir()
	seedTree(t, base, map[string]string{"kitty/kitty.conf": "same"})
	seedTree(t, cfg, map[string]string{"kitty/kitty.conf": "same"})
	t.Setenv("RYOKU_CONFIG_BASE", base)
	t.Setenv("XDG_CONFIG_HOME", cfg)
	if body := userDocBody(); !strings.Contains(body, "matches the shipped Ryoku baseline") {
		t.Fatalf("expected clean baseline note, got:\n%s", body)
	}
}
