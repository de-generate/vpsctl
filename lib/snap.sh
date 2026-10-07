# Step: snap - remove snapd and keep apt from installing it again.
# Installed snaps are never removed silently: the step refuses until they are
# removed by hand, unless REMOVE_SNAP_FORCE=true.

SNAP_PIN_FILE=/etc/apt/preferences.d/no-snapd

step_snap() {
  if [[ $REMOVE_SNAP != true ]]; then
    log "Keeping snapd (REMOVE_SNAP=false)"
    if [[ -f $SNAP_PIN_FILE ]]; then
      rm -f "$SNAP_PIN_FILE"
      info "removed $SNAP_PIN_FILE"
    fi
    return 0
  fi

  log "Removing snapd"
  if dpkg-query -W -f='${Status}' snapd 2>/dev/null | grep -q 'ok installed'; then
    check_snap_list || return 0
    apt_get -y purge snapd
    apt_get -y autoremove --purge
  else
    info "snapd is not installed"
  fi
  # Usually already gone after the purge; leftovers of a broken removal otherwise.
  rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

  write_file "$SNAP_PIN_FILE" <<EOF
$MANAGED_HEADER
# Some Ubuntu packages pull in snapd as a dependency (e.g. lxd-installer).
# This makes apt refuse to install it. Set REMOVE_SNAP=false to allow it again.
Package: snapd
Pin: release a=*
Pin-Priority: -1
EOF
}

# Returns 1 (and warns) if snaps are installed and REMOVE_SNAP_FORCE is not set.
check_snap_list() {
  local snaps
  if ! snaps=$(snap list --all 2>/dev/null); then
    if [[ $REMOVE_SNAP_FORCE == true ]]; then
      warn "Could not list installed snaps. Removing snapd anyway (REMOVE_SNAP_FORCE=true)."
      return 0
    fi
    warn "Could not list installed snaps (is snapd running?). Leaving snapd installed." \
      "Check with: snap list --all"
    return 1
  fi
  [[ -z $snaps ]] && return 0

  if [[ $REMOVE_SNAP_FORCE == true ]]; then
    warn "Removing snapd together with these snaps (REMOVE_SNAP_FORCE=true):"
    printf '%s\n' "$snaps" | sed 's/^/    /' >&2
    return 0
  fi
  warn "Snaps are installed, leaving snapd alone:"
  printf '%s\n' "$snaps" | sed 's/^/    /' >&2
  info "Check that nothing on this server needs them (e.g. a provider agent or canonical-livepatch)," \
    "then remove them: apps first, base snaps (core*) next, snapd last:"
  info "    snap remove --purge <name>"
  info "and run again: sudo bash setup.sh snap"
  info "To keep snapd instead, set REMOVE_SNAP=false in setup.conf."
  return 1
}
