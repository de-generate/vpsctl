#!/usr/bin/env bash
#
# Bootstrap a fresh Ubuntu Server VPS into a basic, secure state.
#
#   bash setup.sh             # run all steps
#   bash setup.sh ssh user    # run only the given steps (in the canonical order)
#   bash setup.sh --list      # list steps
#
# Configuration is read from setup.conf next to this script (see setup.conf.example).
# Every step is idempotent: re-running the script is safe.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Canonical order. ssh is last so a lockout can't happen halfway through.
STEPS=(packages snap system user upgrades firewall fail2ban docker caddy vpsctl ssh)

declare -A STEP_DESCRIPTIONS=(
  [packages]="Upgrade the system and install base packages"
  [snap]="Remove snapd and block its reinstall (refuses if snaps are installed)"
  [system]="Hostname, timezone, time sync, swap, sysctl hardening"
  [user]="Create the sudo admin user and install SSH keys"
  [upgrades]="Automatic security updates (unattended-upgrades)"
  [firewall]="UFW: deny incoming, allow SSH/HTTP/HTTPS"
  [fail2ban]="Ban IPs brute-forcing SSH"
  [docker]="Docker Engine + Compose (official repo), log limits"
  [caddy]="Caddy reverse proxy container and /srv layout"
  [vpsctl]="App management CLI and weekly app auto-updates"
  [ssh]="Key-only SSH, no root login"
)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
for step in "${STEPS[@]}"; do
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/lib/$step.sh"
done

load_config() {
  # Required, so a missing or misplaced config can't silently apply defaults
  # (e.g. after moving the repo, which would reset SSH_PORT or the hostname).
  [[ -f $SCRIPT_DIR/setup.conf ]] \
    || die "No setup.conf found in $SCRIPT_DIR. Create it first: cp setup.conf.example setup.conf"
  # shellcheck source=setup.conf.example
  source "$SCRIPT_DIR/setup.conf"

  VPS_USER=${VPS_USER:-vps}
  SSH_PUBKEY=${SSH_PUBKEY:-}
  SSH_PORT=${SSH_PORT:-22}
  SSH_ALLOW_USERS=${SSH_ALLOW_USERS:-$VPS_USER}
  VPS_HOSTNAME=${VPS_HOSTNAME:-}
  VPS_TIMEZONE=${VPS_TIMEZONE:-Etc/UTC}
  SWAP_SIZE=${SWAP_SIZE:-2G}
  SWAPPINESS=${SWAPPINESS:-10}
  AUTO_REBOOT=${AUTO_REBOOT:-true}
  AUTO_REBOOT_TIME=${AUTO_REBOOT_TIME:-04:00}
  ACME_EMAIL=${ACME_EMAIL:-}
  DOCKER_AUTO_UPGRADE=${DOCKER_AUTO_UPGRADE:-true}
  AUTO_UPDATE=${AUTO_UPDATE:-true}
  AUTO_UPDATE_SCHEDULE=${AUTO_UPDATE_SCHEDULE:-Sun *-*-* 03:00}
  FAIL2BAN_IGNOREIP=${FAIL2BAN_IGNOREIP:-}
  REMOVE_SNAP=${REMOVE_SNAP:-true}
  REMOVE_SNAP_FORCE=${REMOVE_SNAP_FORCE:-false}

  # Values end up in system config files, so validate all of them.
  local user_re='^[a-z_][a-z0-9_-]*$' user
  [[ $VPS_USER =~ $user_re ]] || die "Invalid VPS_USER '$VPS_USER'."
  [[ -n ${SSH_ALLOW_USERS// /} ]] || die "SSH_ALLOW_USERS must not be empty."
  for user in $SSH_ALLOW_USERS; do
    [[ $user =~ $user_re ]] || die "Invalid user '$user' in SSH_ALLOW_USERS."
  done
  # No leading zeros: (( )) would read "022" as octal.
  if ! [[ $SSH_PORT =~ ^[1-9][0-9]{0,4}$ ]] || (( SSH_PORT > 65535 )); then die "Invalid SSH_PORT '$SSH_PORT'."; fi
  [[ -z $VPS_HOSTNAME || $VPS_HOSTNAME =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$ ]] \
    || die "Invalid VPS_HOSTNAME '$VPS_HOSTNAME' (lowercase letters, digits, - and dots)."
  [[ $SWAP_SIZE =~ ^(0|[1-9][0-9]*[KMG])$ ]] || die "Invalid SWAP_SIZE '$SWAP_SIZE' (e.g. 2G, 512M or 0)."
  if ! [[ $SWAPPINESS =~ ^[0-9]{1,3}$ ]] || (( 10#$SWAPPINESS > 100 )); then die "SWAPPINESS must be 0-100."; fi
  [[ $AUTO_REBOOT_TIME =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "Invalid AUTO_REBOOT_TIME '$AUTO_REBOOT_TIME' (HH:MM)."
  [[ $FAIL2BAN_IGNOREIP =~ ^[0-9A-Fa-f.:/\ ]*$ ]] || die "Invalid FAIL2BAN_IGNOREIP '$FAIL2BAN_IGNOREIP' (IPs/CIDRs, space-separated)."
  [[ $AUTO_REBOOT =~ ^(true|false)$ ]] || die "AUTO_REBOOT must be 'true' or 'false'."
  [[ $DOCKER_AUTO_UPGRADE =~ ^(true|false)$ ]] || die "DOCKER_AUTO_UPGRADE must be 'true' or 'false'."
  [[ $AUTO_UPDATE =~ ^(true|false)$ ]] || die "AUTO_UPDATE must be 'true' or 'false'."
  [[ $REMOVE_SNAP =~ ^(true|false)$ ]] || die "REMOVE_SNAP must be 'true' or 'false'."
  [[ $REMOVE_SNAP_FORCE =~ ^(true|false)$ ]] || die "REMOVE_SNAP_FORCE must be 'true' or 'false'."
  systemd-analyze calendar "$AUTO_UPDATE_SCHEDULE" &>/dev/null || die "Invalid AUTO_UPDATE_SCHEDULE '$AUTO_UPDATE_SCHEDULE'."
  [[ -z $ACME_EMAIL || $ACME_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || die "Invalid ACME_EMAIL '$ACME_EMAIL'."
  [[ -e /usr/share/zoneinfo/$VPS_TIMEZONE ]] || die "Unknown timezone '$VPS_TIMEZONE' (see: timedatectl list-timezones)."
}

usage() {
  sed -n '3,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  echo
  list_steps
}

list_steps() {
  echo "Steps:"
  for step in "${STEPS[@]}"; do
    printf '  %-10s %s\n' "$step" "${STEP_DESCRIPTIONS[$step]}"
  done
}

main() {
  case ${1:-} in
    -h|--help) usage; exit 0 ;;
    -l|--list) list_steps; exit 0 ;;
  esac

  local -a selected=()
  if (( $# == 0 )); then
    selected=("${STEPS[@]}")
  else
    for arg in "$@"; do
      [[ -v STEP_DESCRIPTIONS[$arg] ]] || die "Unknown step '$arg'. Use --list to see available steps."
    done
    # Keep canonical order regardless of argument order.
    for step in "${STEPS[@]}"; do
      for arg in "$@"; do
        [[ $arg == "$step" ]] && selected+=("$step") && break
      done
    done
  fi

  require_root
  require_ubuntu
  load_config

  log "Running steps: ${selected[*]}"
  for step in "${selected[@]}"; do
    "step_$step"
  done

  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  log "Done"
  cat <<EOF

    Before closing this root session, open a NEW terminal and check that you can log in:

        ssh -p ${SSH_PORT} ${VPS_USER}@${ip:-<server-ip>}
        sudo -v      # check that sudo works with the password you chose

    If that fails, fix it from this session (see docs/troubleshooting.md).

    Deploy apps from your own machine with bin/vps, see docs/02-deploying-apps.md:

        vps ${VPS_USER}@${ip:-<server-ip>} ls
EOF
  # Last thing printed on purpose, so it can't scroll away.
  if [[ -f /var/run/reboot-required ]]; then
    printf '\n\033[1;33m%s\033[0m\n' "  ┌─ REBOOT REQUIRED ─────────────────────────────────────────────"
    printf '\033[1;33m  │\033[0m %s\n' \
      "Reason: $(reboot_reason)" \
      "After confirming the new login works (see above), run: sudo reboot"
    printf '\033[1;33m%s\033[0m\n' "  └───────────────────────────────────────────────────────────────"
  fi
}

main "$@"
