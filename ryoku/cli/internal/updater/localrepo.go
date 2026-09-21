package updater

import (
	"fmt"
	"os"
	"path/filepath"
	"ryoku-cli/internal/sys"
)

// A fork install has no hosted [ryoku] repo: the shell installer compiles the
// desktop packages from a checkout into a local file repo and records that
// checkout (sys.LocalRepo). An update advances the checkout, rebuilds the repo
// from it, and installs those packages with pacman -U. That is all it does to the
// system: no database sync and no upgrade of anything else, so nothing outside
// Ryoku changes, and a library upgrade the user runs themselves is answered by
// the rebuild the pacman hook starts (system/rebuild/).

// localRepoDir is where build-local-repo.sh publishes the packages.
// RYOKU_LOCAL_REPO overrides it for tests.
func localRepoDir() string {
	if d := os.Getenv("RYOKU_LOCAL_REPO"); d != "" {
		return d
	}
	return "/var/lib/ryoku/repo"
}

// installedVersion is the installed ryoku-desktop version. A seam for tests.
var installedVersion = sys.InstalledVersion

// pacmanInstall installs package files without touching the sync databases, so
// it can never turn into a partial upgrade. A seam for tests.
var pacmanInstall = func(pkgs []string) error {
	return sys.Sudo(append([]string{"pacman", "-U", "--needed", "--noconfirm"}, pkgs...)...)
}

// localRepoUpdate pulls the recorded checkout, rebuilds the local repo from it
// (build-local-repo.sh skips when nothing changed), and installs the result.
func localRepoUpdate() error {
	src := sys.LocalRepo()
	if src == "" {
		return fmt.Errorf("no recorded checkout to build from")
	}
	ch := ryokuChannel()
	progress.logf("Pulling the fork (channel: %s)", ch)
	gitFetch(src, ch)
	if err := syncChannel(src, ch); err != nil {
		progress.logf("warning: could not advance %s (%v); building what is checked out", src, err)
	}

	progress.logf("Building the Ryoku packages (this can take a while)")
	if err := sys.Run(filepath.Join(src, "release", "repo", "build-local-repo.sh")); err != nil {
		return fmt.Errorf("the build failed, nothing was installed: %w", err)
	}

	pkgs, _ := filepath.Glob(filepath.Join(localRepoDir(), "x86_64", "*.pkg.tar.zst"))
	if len(pkgs) == 0 {
		return fmt.Errorf("the local repo %s holds no packages", localRepoDir())
	}
	progress.logf("Installing the Ryoku packages")
	clearStalePacmanLock()
	if err := pacmanInstall(pkgs); err != nil {
		return fmt.Errorf("installing the Ryoku packages failed (if a new dependency could not be fetched, "+
			"update your system with pacman -Syu yourself first; ryoku never does): %w", err)
	}
	return nil
}

// localStatus reports how far the installed build is behind the channel, from
// the recorded checkout: the commits origin/<channel> has that the installed
// packages were not built from. ok=false when there is no recorded checkout or
// the remote has no such branch. Fetch is best-effort and bounded, like the dev
// channel's.
func localStatus() (statusReport, bool) {
	src := sys.LocalRepo()
	if src == "" {
		return statusReport{}, false
	}
	ch := ryokuChannel()
	remote := "refs/remotes/origin/" + ch
	gitFetch(src, ch)
	if _, err := sys.RunOut("git", "-C", src, "rev-parse", "--verify", "--quiet", remote); err != nil {
		return statusReport{}, false
	}

	// the installed package version embeds the commit it was built from
	base := shortCommit(installedVersion())
	if _, err := sys.RunOut("git", "-C", src, "rev-parse", "--verify", "--quiet", base+"^{commit}"); err != nil {
		base = "HEAD"
	}
	behind := gitCount(src, base+".."+remote)
	r := statusReport{
		Installed: gitShort(src, base),
		Latest:    gitShort(src, remote),
		Available: behind > 0,
		Behind:    behind,
		Updates:   gitLog(src, base+".."+remote),
		Recent:    []updateItem{},
		Channel:   ch,
		Snapshots: snapshotCount(),
	}
	if behind == 0 {
		r.Recent = gitLog(src, "-10", base)
	}
	return r, true
}
