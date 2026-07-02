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
	if _, err := os.Stat(hermesConfig()); err == nil {
		info.Configured = true
	}
	info.Wired = fileHasBlock(hermesMemory())
	return info
}

func hermesVersion(bin string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, bin, "--version").Output()
	if err != nil {
		return ""
	}
	line := strings.TrimSpace(firstLine(string(out)))
	// Reduce "hermes 0.15.2" to "0.15.2" when the tool prefixes its name.
	if f := strings.Fields(line); len(f) > 1 && strings.EqualFold(f[0], "hermes") {
		return f[len(f)-1]
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
