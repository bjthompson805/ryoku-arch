# system/boot/

The boot chain: what runs from power-on to the login screen, and how Ryoku
puts its name and colors on it.

## The chain

1. **Limine** is the bootloader. It draws the Ryoku-branded menu, then loads
   the kernel as a single signed image (a UKI, see below).
2. **The kernel** starts and unpacks the **initramfs**, a tiny early system
   that finds the disk, unlocks it if encrypted, and mounts the real root.
3. **Plymouth** shows the Ryoku splash over that whole early stage, so the
   user sees the logo and a progress bar instead of scrolling boot text.
4. Control passes to systemd, then to SDDM for login.

## What's here

- `limine/limine.conf` The bootloader's look: the "Ryoku Bootloader" branding,
  the orange accent, and the Greek Noir terminal palette. The actual boot
  entries are filled in automatically; this file owns the branding.
- `limine/default.conf` Settings for the tool that builds the boot entries
  (deployed to `/etc/default/limine`). It names the OS "Ryoku", builds a UKI
  called `ryoku`, sets the kernel command line, and wires up snapshot entries.
- `plymouth/ryoku/` The splash theme: the manifest, the animation script, and
  the image assets (logo, progress bar, password prompt). Vendored as-is.
- `mkinitcpio/ryoku.conf` The list of initramfs hooks, including `plymouth`
  for the splash and `kms` for an early, flicker-free GPU handoff.

## UKI, in one line

A Unified Kernel Image bundles the kernel, the initramfs, and the command line
into one EFI file (`ryoku.efi`). One file to load, easy to sign.

## How the installer uses this

During install the backend copies these files into place: `limine/*` to
`/boot` and `/etc/default/limine`, `plymouth/ryoku/` to
`/usr/share/plymouth/themes/ryoku`, and the hooks into `/etc/mkinitcpio.conf`.
The `encrypt` hook and the `cryptdevice=` command line are kept only when the
user chose disk encryption.
