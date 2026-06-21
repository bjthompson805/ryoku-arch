package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// extrasServer serves a tiny catalogue (registry + one bundle + one installer)
// and lets a test simulate the network going away by flipping `down`.
func extrasServer(t *testing.T) (*httptest.Server, *bool) {
	t.Helper()
	down := false
	files := map[string]string{
		"/bundles/registry.json": `{"version":1,"bundles":[
			{"id":"demo","name":"Demo","description":"A demo bundle.","sources":"pacman / script","path":"bundles/demo"}]}`,
		"/bundles/demo/bundle.json": `{"id":"demo","name":"Demo","description":"A demo bundle.","items":[
			{"type":"package","name":"cmatrix","detect":"cmatrix","summary":"rain","source":"official"},
			{"type":"script","name":"demo-cli","detect":"demo","summary":"a cli","source":"curl"}]}`,
		"/installers/demo-cli.sh": "#!/bin/bash\necho demo\n",
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if down {
			http.Error(w, "down", http.StatusServiceUnavailable)
			return
		}
		body, ok := files[r.URL.Path]
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return srv, &down
}

func TestBuildCatalog(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	srv, down := extrasServer(t)
	t.Setenv("RYOKU_EXTRAS_BASE", srv.URL)

	cat, err := buildCatalog()
	if err != nil {
		t.Fatalf("buildCatalog: %v", err)
	}
	bundles := cat["bundles"]
	if len(bundles) != 1 {
		t.Fatalf("want 1 bundle, got %d", len(bundles))
	}
	b := bundles[0]
	if b.ID != "demo" || b.Sources != "pacman / script" {
		t.Fatalf("registry metadata not carried through: %+v", b)
	}
	if len(b.Items) != 2 || b.Items[0].Name != "cmatrix" || b.Items[1].Type != "script" {
		t.Fatalf("items not resolved: %+v", b.Items)
	}

	// The script installer should have been warmed into the cache.
	if _, err := os.Stat(filepath.Join(cache, "ryoku", "extras", "installers", "demo-cli.sh")); err != nil {
		t.Fatalf("installer not cached: %v", err)
	}

	// With the network down the catalogue must still resolve from cache.
	*down = true
	cat2, err := buildCatalog()
	if err != nil {
		t.Fatalf("offline buildCatalog: %v", err)
	}
	if len(cat2["bundles"]) != 1 || len(cat2["bundles"][0].Items) != 2 {
		t.Fatalf("offline catalogue did not come from cache: %+v", cat2["bundles"])
	}
}

func TestEnsureInstaller(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	srv, down := extrasServer(t)
	t.Setenv("RYOKU_EXTRAS_BASE", srv.URL)

	p, err := ensureInstaller("demo-cli")
	if err != nil {
		t.Fatalf("ensureInstaller: %v", err)
	}
	if want := filepath.Join(cache, "ryoku", "extras", "installers", "demo-cli.sh"); p != want {
		t.Fatalf("path = %q, want %q", p, want)
	}

	// Offline but cached: still resolves.
	*down = true
	if _, err := ensureInstaller("demo-cli"); err != nil {
		t.Fatalf("offline ensureInstaller: %v", err)
	}
	// Offline and never cached: a clear error.
	if _, err := ensureInstaller("missing"); err == nil {
		t.Fatal("expected an error for an uncached, unreachable installer")
	}
}
