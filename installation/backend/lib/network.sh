#!/usr/bin/env bash
# shellcheck shell=bash
# Carry the live session's network setup into the installed system so wifi
# survives first boot. two parts, both required:
#
#   1) pin NetworkManager's wifi backend to iwd in the target. base set ships
#      iwd (not wpa_supplicant), and the live ISO already runs NM over iwd
#      (installation/iso/airootfs/etc/NetworkManager/conf.d/wifi-backend.conf).
#      that drop-in lives only on the ISO. without an equivalent in the target,
#      NM falls back to wpa_supplicant, finds nothing, wifi can't associate.
#
#   2) copy the saved connection profiles NM wrote while the user joined a
#      network during install (/etc/NetworkManager/system-connections/
#      *.nmconnection) into the target, preserving the 600 root:root perms NM
#      requires. otherwise the credentials evaporate on reboot.
#
# runs in the "configure" stage. everything routes through the dry-run wrappers.

ryoku_network() {
  log "persisting NetworkManager configuration into the target"
  ryoku_network_backend
  ryoku_network_connections
}

# ryoku_network_backend writes the iwd backend pin into the target, mirroring
# the live ISO's drop-in.
ryoku_network_backend() {
  log "pinning NetworkManager Wi-Fi backend to iwd"
  run mkdir -p /mnt/etc/NetworkManager/conf.d
  write_file /mnt/etc/NetworkManager/conf.d/wifi-backend.conf <<'EOF'
# Ryoku ships iwd, not wpa_supplicant; point NM at iwd. NM dbus-activates iwd
# on demand. mirrors the live ISO drop-in
# installation/iso/airootfs/etc/NetworkManager/conf.d/wifi-backend.conf.
[device]
wifi.backend=iwd
EOF
}

# ryoku_network_connections: copy the saved .nmconnection keyfiles from the
# live session into the target with the ownership/perms NM demands.
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
  # NM refuses keyfiles that are group/world readable or not root-owned, so
  # normalize both regardless of where they came from.
  chmod 600 "$dst"/*.nmconnection
  chown root:root "$dst"/*.nmconnection
  log "carried over ${#files[@]} saved network profile(s)"
}
