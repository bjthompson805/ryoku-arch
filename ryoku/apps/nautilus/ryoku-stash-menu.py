# Ryoku stash actions in the Nautilus right-click menu. The control deck's
# stash already knows how to install, shrink, and LocalSend a file; this hands
# the same helpers a file the user picked in the file manager instead of one
# dropped into ~/Downloads/Stash, so both surfaces behave identically.
#
# Install/compress run their helper directly (each does its own notify-send);
# send routes through the deck so it can reuse the LAN discovery + device
# picker rather than reinventing one here.
import os
import subprocess
from gi.repository import Nautilus, GObject

# Anything stash-install.sh can turn into a launcher: AppImages, self-contained
# tarballs, Arch/foreign packages, Flatpak bundles. Matched on the full suffix
# so ".pkg.tar.zst" lands via ".tar.zst".
INSTALLABLE = (
    ".appimage", ".flatpak", ".deb", ".rpm",
    ".tar.gz", ".tgz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tar",
)

# Exactly what stash-compress.sh re-encodes; offering it on anything else would
# just pop a "can't compress" error.
COMPRESSIBLE = (
    ".mp4", ".mkv", ".mov", ".webm", ".avi", ".m4v",
    ".jpg", ".jpeg", ".png", ".webp", ".bmp",
)


def _scripts_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "hypr", "scripts")


def _local_paths(files):
    paths = []
    for f in files:
        if f.get_uri_scheme() != "file" or f.is_directory():
            continue
        loc = f.get_location()
        p = loc.get_path() if loc else None
        if p:
            paths.append(p)
    return paths


def _spawn(argv, env=None):
    merged = dict(os.environ, **(env or {}))
    subprocess.Popen(
        argv, env=merged, start_new_session=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


# Run one stash helper over each selected path in turn. Sequential so N package
# installs raise their polkit prompts one at a time instead of all at once.
def _run_each(script, paths, env=None):
    _spawn(
        ["bash", "-c", 's="$1"; shift; for f in "$@"; do bash "$s" "$f"; done', "--", script, *paths],
        env=env,
    )


class RyokuStashMenu(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        paths = _local_paths(files)
        if not paths:
            return []

        scripts = _scripts_dir()
        items = []

        installable = [p for p in paths if p.lower().endswith(INSTALLABLE)]
        if installable:
            item = Nautilus.MenuItem(
                name="RyokuStashMenu::install",
                label="Install with Ryoku",
                tip="Install the selected app the way the control deck does",
                icon="system-software-install",
            )
            item.connect("activate", self._install, installable)
            items.append(item)

        compressible = [p for p in paths if p.lower().endswith(COMPRESSIBLE)]
        if compressible:
            item = Nautilus.MenuItem(
                name="RyokuStashMenu::compress",
                label="Compress with Ryoku",
                tip="Shrink the selected media in place",
                icon="application-x-archive",
            )
            item.connect("activate", self._compress, compressible)
            items.append(item)

        # Send takes one file: the deck's picker sends a single target.
        if len(paths) == 1:
            item = Nautilus.MenuItem(
                name="RyokuStashMenu::send",
                label="Send with LocalSend",
                tip="Pick a nearby device and send this file over LocalSend",
                icon="send-to",
            )
            item.connect("activate", self._send, paths[0])
            items.append(item)

        return items

    # The deck drops a stash source after installing it (it's a redundant copy by
    # then); a file the user right-clicked is theirs to keep, so hold onto it.
    def _install(self, menu, paths):
        _run_each(os.path.join(_scripts_dir(), "stash-install.sh"), paths,
                  env={"RYOKU_STASH_KEEP": "1"})

    def _compress(self, menu, paths):
        _run_each(os.path.join(_scripts_dir(), "stash-compress.sh"), paths)

    def _send(self, menu, path):
        _spawn(["ryoku-shell", "stash-send", path])
