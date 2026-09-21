package sys

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestLocalRepo(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	rec := filepath.Join(state, "ryoku", "local-repo")

	if got := LocalRepo(); got != "" {
		t.Fatalf("no record must mean no local repo, got %q", got)
	}

	if err := os.MkdirAll(filepath.Dir(rec), 0o755); err != nil {
		t.Fatal(err)
	}
	checkout := t.TempDir()
	if err := os.WriteFile(rec, []byte(checkout+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := LocalRepo(); got != "" {
		t.Fatalf("a path that is not a git work tree must be ignored, got %q", got)
	}

	if out, err := exec.Command("git", "-C", checkout, "init", "-q").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v\n%s", err, out)
	}
	if got := LocalRepo(); got != checkout {
		t.Fatalf("recorded checkout = %q, want %q", got, checkout)
	}
}
