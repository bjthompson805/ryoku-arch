# nautilus

The file manager. There is no config file to ship: Nautilus stores its settings
in dconf (GSettings), and it reads the standard home folders directly.

## Home folders

The folders you see in the sidebar (Documents, Downloads, Pictures, Videos,
Music, Desktop) come from `xdg-user-dirs`. On first graphical login,
`xdg-user-dirs-update` creates them and writes `~/.config/user-dirs.dirs`.
Nautilus picks them up natively, so install `xdg-user-dirs` and make sure the
update runs once and nothing else is needed here.

## Optional defaults

If you want to set Nautilus preferences during install, apply them per user with
`gsettings` (the user session must be reachable, so run this as the logged-in
user, not via the chroot):

```sh
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.preferences show-hidden-files false
gsettings set org.gtk.Settings.FileChooser sort-directories-first true
```

These are conveniences, not requirements: a fresh Nautilus works without them.
