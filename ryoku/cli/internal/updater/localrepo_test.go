package updater

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// recordLocalRepo points the recorded-checkout state at src.
func recordLocalRepo(t *testing.T, src string) {
	t.Helper()
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	writeFile(t, filepath.Join(state, "ryoku", "local-repo"), src+"\n")
}

func TestLocalStatusCountsCommitsBehindTheChannel(t *testing.T) {
	origin := t.TempDir()
	mustGit(t, origin, "init", "-q", "-b", "main")
	var shas []string
	for _, subject := range []string{"first", "second", "third"} {
		mustGit(t, origin, "commit", "-q", "--allow-empty", "-m", subject)
		shas = append(shas, strings.TrimSpace(mustGit(t, origin, "rev-parse", "--short=7", "HEAD")))
	}

	src := filepath.Join(t.TempDir(), "src")
	mustGit(t, "", "clone", "-q", origin, src)
	mustGit(t, src, "reset", "-q", "--hard", shas[0])
	recordLocalRepo(t, src)
	t.Setenv("RYOKU_CHANNEL", "main")

	// the installed package version embeds the commit it was built from
	origVersion := installedVersion
	t.Cleanup(func() { installedVersion = origVersion })
	installedVersion = func() string { return "0.12.8.r1.g" + shas[0] + ".1-1" }

	r, ok := localStatus()
	if !ok {
		t.Fatal("a recorded checkout with an origin/main must report a status")
	}
	if r.Behind != 2 || !r.Available {
		t.Errorf("behind = %d, available = %v, want 2 and true", r.Behind, r.Available)
	}
	if r.Installed != shas[0] || r.Latest != shas[2] {
		t.Errorf("installed/latest = %s/%s, want %s/%s", r.Installed, r.Latest, shas[0], shas[2])
	}
	if len(r.Updates) != 2 || r.Updates[0].Name != "third" {
		t.Errorf("updates = %+v, want two commits, newest (third) first", r.Updates)
	}

	installedVersion = func() string { return "0.12.8.r3.g" + shas[2] + ".2-1" }
	r, _ = localStatus()
	if r.Behind != 0 || r.Available || len(r.Recent) == 0 {
		t.Errorf("up to date: behind = %d, available = %v, recent = %d; want 0, false, some history", r.Behind, r.Available, len(r.Recent))
	}
}

func TestLocalStatusWithoutARecord(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	if _, ok := localStatus(); ok {
		t.Error("no recorded checkout must mean no local status")
	}
}

// buildScript writes a fake build-local-repo.sh into a recorded checkout.
func buildScript(t *testing.T, src, body string) {
	t.Helper()
	script := filepath.Join(src, "release", "repo", "build-local-repo.sh")
	writeFile(t, script, "#!/bin/sh\n"+body+"\n")
	if err := os.Chmod(script, 0o755); err != nil {
		t.Fatal(err)
	}
}

func TestLocalRepoUpdateBuildsThenInstallsThePackages(t *testing.T) {
	src := t.TempDir()
	mustGit(t, src, "init", "-q")
	built := filepath.Join(t.TempDir(), "built")
	buildScript(t, src, "touch '"+built+"'")
	recordLocalRepo(t, src)

	repo := t.TempDir()
	pkg := filepath.Join(repo, "x86_64", "ryoku-1-1-any.pkg.tar.zst")
	writeFile(t, pkg, "x")
	t.Setenv("RYOKU_LOCAL_REPO", repo)

	var got []string
	origInstall := pacmanInstall
	t.Cleanup(func() { pacmanInstall = origInstall })
	pacmanInstall = func(pkgs []string) error { got = pkgs; return nil }

	if err := localRepoUpdate(); err != nil {
		t.Fatalf("localRepoUpdate: %v", err)
	}
	if _, err := os.Stat(built); err != nil {
		t.Errorf("the recorded checkout's build script did not run: %v", err)
	}
	if len(got) != 1 || got[0] != pkg {
		t.Errorf("installed %v, want just %s", got, pkg)
	}
}

func TestLocalRepoUpdateInstallsNothingWhenTheBuildFails(t *testing.T) {
	src := t.TempDir()
	mustGit(t, src, "init", "-q")
	buildScript(t, src, "exit 1")
	recordLocalRepo(t, src)

	repo := t.TempDir()
	writeFile(t, filepath.Join(repo, "x86_64", "old-1-1-any.pkg.tar.zst"), "x")
	t.Setenv("RYOKU_LOCAL_REPO", repo)

	called := false
	origInstall := pacmanInstall
	t.Cleanup(func() { pacmanInstall = origInstall })
	pacmanInstall = func([]string) error { called = true; return nil }

	if err := localRepoUpdate(); err == nil {
		t.Fatal("a failed build must fail the update")
	}
	if called {
		t.Error("packages were installed after a failed build")
	}
}

func TestLocalRepoUpdateWithoutARecord(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	if err := localRepoUpdate(); err == nil {
		t.Error("no recorded checkout must be an error")
	}
}
