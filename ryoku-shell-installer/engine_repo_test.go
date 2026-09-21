package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

const baseConf = "[options]\nHoldPkg = pacman glibc\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n"

func TestWithLocalRepoAppendsWhenAbsent(t *testing.T) {
	next, changed := withLocalRepo(baseConf)
	if !changed {
		t.Fatal("a conf with no [ryoku] section must change")
	}
	if !strings.HasPrefix(next, baseConf) {
		t.Errorf("existing sections were disturbed:\n%s", next)
	}
	if !strings.Contains(next, "[ryoku]\nSigLevel = Never\nServer = file://"+localRepoDir+"/$arch") {
		t.Errorf("local stanza missing:\n%s", next)
	}
}

func TestWithLocalRepoReplacesHostedStanza(t *testing.T) {
	hosted := baseConf + "\n[ryoku]\nSigLevel = Required\nServer = https://repo.ryoku.dev/stable/$arch\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n"
	next, changed := withLocalRepo(hosted)
	if !changed {
		t.Fatal("a hosted [ryoku] stanza must be replaced")
	}
	if strings.Contains(next, "repo.ryoku.dev") {
		t.Errorf("hosted server still present:\n%s", next)
	}
	if !strings.Contains(next, "[extra]") || strings.Count(next, "[ryoku]") != 1 {
		t.Errorf("neighbouring sections lost or [ryoku] duplicated:\n%s", next)
	}
}

func TestWithLocalRepoIsIdempotent(t *testing.T) {
	once, _ := withLocalRepo(baseConf)
	twice, changed := withLocalRepo(once)
	if changed || twice != once {
		t.Errorf("second pass must be a no-op, changed=%v", changed)
	}
}

func TestSwapFileScriptWritesContentVerbatim(t *testing.T) {
	dst := filepath.Join(t.TempDir(), "pacman.conf")
	if err := os.WriteFile(dst, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	next, _ := withLocalRepo("# it's a comment with 100% quotes '\"\n" + baseConf)
	if out, err := exec.Command("sh", "-c", swapFileScript(dst, next)).CombinedOutput(); err != nil {
		t.Fatalf("swap script failed: %v\n%s", err, out)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != next {
		t.Errorf("content changed in transit:\n got %q\nwant %q", got, next)
	}
	if fi, _ := os.Stat(dst); fi.Mode().Perm() != 0o644 {
		t.Errorf("mode = %v, want 0644", fi.Mode().Perm())
	}
}
