package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ryoku-hub owns all network and disk for the extras catalogue, so the shell
// actuator (ryoku-extras-install) never fetches anything itself: it reads the
// cache this writes and asks for an installer path on demand.
//
//	ryoku-hub extras catalog        fetch + merge the bundle catalogue as JSON
//	ryoku-hub extras cache          print the catalogue cache directory
//	ryoku-hub extras installer <n>  ensure installers/<n>.sh is cached, print its path
//
// The source is the ryoku-extras repo, served raw from GitHub; RYOKU_EXTRAS_BASE
// overrides it (a fork, or a local tree under test).
const defaultExtrasBase = "https://raw.githubusercontent.com/neur0map/ryoku-extras/main"

func extrasBase() string {
	if b := os.Getenv("RYOKU_EXTRAS_BASE"); b != "" {
		return strings.TrimRight(b, "/")
	}
	return defaultExtrasBase
}

func extrasCacheDir() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".cache")
	}
	return filepath.Join(base, "ryoku", "extras")
}

type registryEntry struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Tagline     string `json:"tagline,omitempty"`
	Sources     string `json:"sources,omitempty"`
	Path        string `json:"path"`
}

type registry struct {
	Version int             `json:"version"`
	Bundles []registryEntry `json:"bundles"`
}

type bundleItem struct {
	Type     string `json:"type"`
	Name     string `json:"name"`
	Detect   string `json:"detect,omitempty"`
	Summary  string `json:"summary,omitempty"`
	Source   string `json:"source,omitempty"`
	Upstream string `json:"upstream,omitempty"`
}

type bundleDef struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Description string       `json:"description"`
	Items       []bundleItem `json:"items"`
}

// catalogBundle is one bundle as the Hub renders it: the registry metadata plus
// the resolved item list.
type catalogBundle struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Description string       `json:"description"`
	Tagline     string       `json:"tagline,omitempty"`
	Sources     string       `json:"sources,omitempty"`
	Path        string       `json:"path"`
	Items       []bundleItem `json:"items"`
}

func runExtras(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("extras needs catalog|cache|installer")
	}
	switch args[0] {
	case "catalog":
		cat, err := buildCatalog()
		if err != nil {
			return err
		}
		b, err := json.Marshal(cat)
		if err != nil {
			return err
		}
		os.Stdout.Write(b)
		fmt.Println()
		return nil
	case "cache":
		fmt.Println(extrasCacheDir())
		return nil
	case "installer":
		if len(args) < 2 {
			return fmt.Errorf("extras installer needs a name")
		}
		p, err := ensureInstaller(args[1])
		if err != nil {
			return err
		}
		fmt.Println(p)
		return nil
	default:
		return fmt.Errorf("extras needs catalog|cache|installer")
	}
}

var extrasClient = &http.Client{Timeout: 12 * time.Second}

func fetch(url string) ([]byte, error) {
	resp, err := extrasClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", url, resp.Status)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 4<<20))
}

func writeCache(rel string, data []byte) {
	p := filepath.Join(extrasCacheDir(), rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return
	}
	tmp, err := os.CreateTemp(filepath.Dir(p), ".tmp-*")
	if err != nil {
		return
	}
	name := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(name)
		return
	}
	if err := tmp.Close(); err != nil {
		os.Remove(name)
		return
	}
	os.Rename(name, p)
}

// fetchOrCache returns the live bytes (caching them) or, when the network is
// unreachable, the last cached copy, so the catalogue still renders offline.
func fetchOrCache(rel string) ([]byte, error) {
	if b, err := fetch(extrasBase() + "/" + rel); err == nil {
		writeCache(rel, b)
		return b, nil
	}
	if b, err := os.ReadFile(filepath.Join(extrasCacheDir(), rel)); err == nil {
		return b, nil
	}
	return nil, fmt.Errorf("cannot fetch or find cached %s", rel)
}

func buildCatalog() (map[string][]catalogBundle, error) {
	raw, err := fetchOrCache("bundles/registry.json")
	if err != nil {
		return nil, err
	}
	var reg registry
	if err := json.Unmarshal(raw, &reg); err != nil {
		return nil, fmt.Errorf("registry.json: %w", err)
	}

	out := make([]catalogBundle, 0, len(reg.Bundles))
	for _, e := range reg.Bundles {
		path := e.Path
		if path == "" {
			path = "bundles/" + e.ID
		}
		cb := catalogBundle{ID: e.ID, Name: e.Name, Description: e.Description, Tagline: e.Tagline, Sources: e.Sources, Path: path}
		if b, err := fetchOrCache(path + "/bundle.json"); err == nil {
			var def bundleDef
			if json.Unmarshal(b, &def) == nil {
				cb.Items = def.Items
				if cb.Description == "" {
					cb.Description = def.Description
				}
				if cb.Name == "" {
					cb.Name = def.Name
				}
			}
		}
		// Warm the installer cache for any script item, best-effort and lazy.
		for _, it := range cb.Items {
			if it.Type == "script" {
				rel := "installers/" + it.Name + ".sh"
				if _, err := os.Stat(filepath.Join(extrasCacheDir(), rel)); err != nil {
					if data, err := fetch(extrasBase() + "/" + rel); err == nil {
						writeCache(rel, data)
					}
				}
			}
		}
		out = append(out, cb)
	}
	return map[string][]catalogBundle{"bundles": out}, nil
}

// ensureInstaller fetches a fresh copy of installers/<name>.sh into the cache and
// returns its path, falling back to the cached copy when offline.
func ensureInstaller(name string) (string, error) {
	rel := "installers/" + name + ".sh"
	dst := filepath.Join(extrasCacheDir(), rel)
	if b, err := fetch(extrasBase() + "/" + rel); err == nil {
		writeCache(rel, b)
		return dst, nil
	}
	if _, err := os.Stat(dst); err == nil {
		return dst, nil
	}
	return "", fmt.Errorf("installer %q not found in the catalogue", name)
}
