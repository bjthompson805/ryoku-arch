# system/rebuild/

Keeps the locally built Ryoku packages working after a system upgrade.

Packages built on the machine record no library dependencies, so upgrading
Hyprland, Qt, ffmpeg, or another library they link against can leave them
pointing at libraries that are gone.

- `ryoku-rebuild.hook` a pacman hook. `ryoku-desktop` fills in one `Target` per
  package listed in `release/repo/abi.packages` and installs it to
  `/usr/share/libalpm/hooks/`. After an upgrade of any of them it starts
  `ryoku-rebuild-abi` as a transient, low-priority systemd unit.
- `ryoku-rebuild-abi` runs as root from that unit. It waits for pacman to finish,
  builds as the checkout's owner (`release/repo/build-local-repo.sh
  --stage-only`), publishes with the root-owned `/usr/lib/ryoku/publish-local-repo`,
  installs with `pacman -U`, and notifies the desktop.

It only builds the commit the owner last built with sudo, from a clean checkout.
If the checkout has changed since, it notifies and leaves the rebuild to
`ryoku update`, so an edit is never built and installed as root unattended.
