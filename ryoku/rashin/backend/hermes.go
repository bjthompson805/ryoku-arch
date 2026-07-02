package main

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// HermesInfo is the resident agent's install and wiring state for the dashboard.
type HermesInfo struct {
	Installed  bool   `json:"installed"`
	Version    string `json:"version"`
	Configured bool   `json:"configured"`
	Wired      bool   `json:"wired"`
}

// hermesMemory is the file the vault pointer block is wired into.
func hermesMemory() string {
	return filepath.Join(home(), ".hermes", "memories", "MEMORY.md")
}

func hermesConfig() string {
	return filepath.Join(home(), ".hermes", "config.yaml")
}

// FindHermes resolves the hermes binary: PATH first, then the two locations its
// installer uses.
func FindHermes() (string, bool) {
	if p, err := exec.LookPath("hermes"); err == nil {
		return p, true
	}
	for _, cand := range []string{
		filepath.Join(home(), ".hermes", "bin", "hermes"),
		filepath.Join(home(), ".local", "bin", "hermes"),
	} {
		if fi, err := os.Stat(cand); err == nil && !fi.IsDir() {
			return cand, true
		}
	}
	return "", false
}

// HermesStatus reports install, version, config, and wiring state, best effort:
// a missing or slow hermes never blocks the caller.
func HermesStatus() HermesInfo {
	info := HermesInfo{}
	bin, ok := FindHermes()
	info.Installed = ok
	if ok {
		info.Version = hermesVersion(bin)
	}
	info.Configured = hermesOnboarded()
	info.Wired = fileHasBlock(hermesMemory())
	return info
}

// hermesOnboarded reports whether the user finished hermes's own onboarding.
// The installer lays a template config.yaml with an EMPTY `model:` line, so
// file existence alone is a false positive; a chosen model is the artifact of
// the user actually completing `hermes setup`.
func hermesOnboarded() bool {
	b, err := os.ReadFile(hermesConfig())
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(b), "\n") {
		trimmed := strings.TrimSpace(line)
		if rest, ok := strings.CutPrefix(trimmed, "model:"); ok {
			return strings.TrimSpace(rest) != ""
		}
	}
	return false
}

func hermesVersion(bin string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, bin, "--version").Output()
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(firstLine(string(out)))
	// Real output: "Hermes Agent v0.18.0 (2026.7.1) · upstream 88d1d620".
	// Pick the first token that looks like a version number.
	for _, f := range strings.Fields(line) {
		v := strings.TrimPrefix(f, "v")
		if len(v) > 0 && v[0] >= '0' && v[0] <= '9' && strings.Contains(v, ".") {
			return v
		}
	}
	return line
}

// WireHermesMemory upserts the pointer block into Hermes's MEMORY.md, creating
// memories/ only when ~/.hermes already exists. It never installs Hermes.
func WireHermesMemory() error {
	if !dirExists(filepath.Join(home(), ".hermes")) {
		return errors.New("hermes not installed")
	}
	file := hermesMemory()
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		return err
	}
	doc := readFileOrEmpty(file)
	return atomicWrite(file, []byte(upsertBlock(doc)), 0o644)
}
