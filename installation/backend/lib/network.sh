#!/usr/bin/env bash
# shellcheck shell=bash
# Carry the live session's network setup into the installed system so Wi-Fi keeps
# working after first boot. Two parts, both needed:
#
#   1) Pin NetworkManager's Wi-Fi backend to iwd in the target. The base set
#      ships iwd (not wpa_supplicant), and the live ISO already runs NM over iwd
#      (installation/iso/airootfs/etc/NetworkManager/conf.d/wifi-backend.conf).
#      That file lives only on the ISO; without an equivalent in the target, the
#      installed NetworkManager falls back to its wpa_supplicant default, finds
#      no such backend, and Wi-Fi cannot associate at all.
#
#   2) Copy the saved connection profiles NetworkManager wrote while the user
#      joined a network during install (/etc/NetworkManager/system-connections/
#      *.nmconnection) into the target, preserving the 600 root:root perms NM
#      requires, so the credentials survive the reboot instead of being lost.
#
# Runs in the "configure" stage. Everything routes through the dry-run wrappers.

ryoku_network() {
  log "persisting NetworkManager configuration into the target"
  ryoku_network_backend
  ryoku_network_connections
}

# ryoku_network_backend writes the iwd backend pin into the installed system,
# mirroring the live ISO's conf.d drop-in.
ryoku_network_backend() {
  log "pinning NetworkManager Wi-Fi backend to iwd"
  run mkdir -p /mnt/etc/NetworkManager/conf.d
  write_file /mnt/etc/NetworkManager/conf.d/wifi-backend.conf <<'EOF'
# Ryoku ships iwd, not wpa_supplicant, so point NetworkManager's Wi-Fi backend
# at iwd. NetworkManager dbus-activates iwd on demand. Mirrors the live ISO drop-in
# installation/iso/airootfs/etc/NetworkManager/conf.d/wifi-backend.conf.
[device]
wifi.backend=iwd
EOF
}

# ryoku_network_connections copies the saved .nmconnection keyfiles from the live
# session into the target with the ownership/permissions NetworkManager demands.
ryoku_network_connections() {
  local srcdir=/etc/NetworkManager/system-connections
  local dst=/mnt/etc/NetworkManager/system-connections
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    printf 'DRYRUN: copy saved network profiles %s/*.nmconnection -> %s/ (chmod 600, chown root:root)\n' \
      "$srcdir" "$dst"
    return 0
  fi
  [[ -d $srcdir ]] || { log "skip: $srcdir not present"; return 0; }
  local files=()
  shopt -s nullglob
  files=("$srcdir"/*.nmconnection)
  shopt -u nullglob
  (( ${#files[@]} )) || { log "no saved network profiles to carry over"; return 0; }
  mkdir -p "$dst"
  cp "${files[@]}" "$dst"/
  # NetworkManager refuses to load keyfiles that are group/world readable or not
  # owned by root, so normalize both regardless of the source's state.
  chmod 600 "$dst"/*.nmconnection
  chown root:root "$dst"/*.nmconnection
  log "carried over ${#files[@]} saved network profile(s)"
}
