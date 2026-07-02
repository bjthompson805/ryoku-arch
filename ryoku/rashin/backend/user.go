package main

import (
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// user.go builds user.md: the user-owned changes layer. It diffs the shipped
// base config tree (what `ryoku materialize` lays down) against the live
// ~/.config, so agents can tell Ryoku's defaults from this user's own edits,
// and it is reindexed separately from the system layer when the user changes
// something.

// baseConfigDir mirrors the ryoku CLI's resolution: the packaged base tree,
// overridable for dev checkouts.
func baseConfigDir() string {
	if v := os.Getenv("RYOKU_CONFIG_BASE"); v != "" {
		return v
	}
	return "/usr/share/ryoku/config"
}

// userOverrideFiles are the documented always-user files: present means the
// user customized; they are never shipped.
var userOverrideFiles = []string{
	"hypr/user.lua",
	"hypr/monitors_user.lua",
	"kitty/user.conf",
	"fish/user.fish",
}

type userDiff struct {
	Modified  []string // shipped file, user edited it in place
	Missing   []string // shipped file, user deleted it
	Overrides []string // dedicated user-override files present
}

// diffUserConfig walks the base tree and compares each file against the live
// config by content hash.
func diffUserConfig(base, cfg string) (userDiff, error) {
	var d userDiff
	err := filepath.WalkDir(base, func(p string, e os.DirEntry, err error) error {
		if err != nil || e.IsDir() {
			return nil
		}
		rel, rerr := filepath.Rel(base, p)
		if rerr != nil {
			return nil
		}
		live := filepath.Join(cfg, rel)
		lfi, lerr := os.Stat(live)
		if lerr != nil {
			d.Missing = append(d.Missing, rel)
			return nil
		}
		if lfi.IsDir() {
			return nil
		}
		if !sameContent(p, live) {
			d.Modified = append(d.Modified, rel)
		}
		return nil
	})
	if err != nil {
		return d, err
	}
	for _, rel := range userOverrideFiles {
		if _, err := os.Stat(filepath.Join(cfg, rel)); err == nil {
			d.Overrides = append(d.Overrides, rel)
		}
	}
	sort.Strings(d.Modified)
	sort.Strings(d.Missing)
	return d, nil
}

func sameContent(a, b string) bool {
	ha, err1 := fileHash(a)
	hb, err2 := fileHash(b)
	return err1 == nil && err2 == nil && ha == hb
}

func fileHash(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

// userDocBody renders the fenced body of user.md.
func userDocBody() string {
	base := baseConfigDir()
	if _, err := os.Stat(base); err != nil {
		return "No shipped base config at `" + base + "` (dev checkout or unpackaged\n" +
			"install), so shipped-vs-user diffing is unavailable. Treat everything in\n" +
			"`~/.config` as potentially user-owned.\n"
	}
	cfg := configHomeDir()
	d, err := diffUserConfig(base, cfg)
	if err != nil {
		return "Diff failed: " + err.Error() + "\n"
	}

	var b strings.Builder
	if len(d.Modified) == 0 && len(d.Missing) == 0 && len(d.Overrides) == 0 {
		b.WriteString("The live config matches the shipped Ryoku baseline exactly; no user\nedits detected.\n")
		return b.String()
	}
	b.WriteString("Files where this user diverges from the shipped Ryoku baseline. Respect\n" +
		"these when editing: they are the user's own choices, not Ryoku defaults.\n\n")
	if len(d.Overrides) > 0 {
		b.WriteString("## User override files (always user-owned)\n\n")
		for _, f := range d.Overrides {
			fmt.Fprintf(&b, "- `~/.config/%s`\n", f)
		}
		b.WriteString("\n")
	}
	if len(d.Modified) > 0 {
		b.WriteString("## Shipped files the user edited\n\n")
		for _, f := range d.Modified {
			fmt.Fprintf(&b, "- `~/.config/%s`\n", f)
		}
		b.WriteString("\n")
	}
	if len(d.Missing) > 0 {
		b.WriteString("## Shipped files the user removed\n\n")
		for _, f := range d.Missing {
			fmt.Fprintf(&b, "- `~/.config/%s`\n", f)
		}
	}
	return b.String()
}

func configHomeDir() string {
	if v := os.Getenv("XDG_CONFIG_HOME"); v != "" {
		return v
	}
	return filepath.Join(home(), ".config")
}

// writeUserVaultDoc lays user.md into the vault.
func writeUserVaultDoc() error {
	const header = "# User-owned changes\n" +
		"\n" +
		"Where this machine's config diverges from the shipped Ryoku baseline.\n" +
		"Generated: the content between the markers is overwritten whenever the\n" +
		"user's config changes."
	return writeVaultDoc("user.md", header, userDocBody())
}

// userConfigFingerprint summarizes the live config tree cheaply (paths,
// sizes, mtimes of Ryoku-relevant dirs) so the watcher can tell "something
// changed" without hashing every file.
func userConfigFingerprint() string {
	cfg := configHomeDir()
	h := sha256.New()
	for _, dir := range []string{"hypr", "quickshell", "ryoku", "kitty", "fish"} {
		root := filepath.Join(cfg, dir)
		_ = filepath.WalkDir(root, func(p string, e os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			fi, ferr := e.Info()
			if ferr != nil {
				return nil
			}
			fmt.Fprintf(h, "%s|%d|%d\n", p, fi.Size(), fi.ModTime().UnixNano())
			return nil
		})
	}
	return fmt.Sprintf("%x", h.Sum(nil))
}
