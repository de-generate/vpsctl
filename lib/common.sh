# Shared helpers sourced by setup.sh. Not meant to be executed directly.

export DEBIAN_FRONTEND=noninteractive
# Stop needrestart from opening interactive "restart services?" dialogs during apt runs.
export NEEDRESTART_MODE=a

log()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "This script must be run as root."
}

require_ubuntu() {
  # shellcheck source=/dev/null
  . /etc/os-release
  [[ ${ID:-} == ubuntu ]] || die "This script needs Ubuntu Server, detected '${PRETTY_NAME:-unknown}'."
  # full-upgrade stays within a release, so an old release would stay old.
  (( ${VERSION_ID%%.*} >= 24 )) \
    || die "Ubuntu ${VERSION_ID} is too old (24.04 or newer needed). Use a newer image," \
      "or upgrade the release on purpose first (do-release-upgrade)."
}

# apt-get that waits instead of failing when apt is busy, e.g. with cloud-init or
# unattended-upgrades right after the first boot of a fresh (old) image.
apt_get() {
  local attempt=0
  # DPkg::Lock::Timeout covers the dpkg lock, but not the package lists lock that
  # "apt-get update" needs, hence the retries.
  until apt-get -o DPkg::Lock::Timeout=600 "$@"; do
    (( ++attempt < 30 )) || die "apt-get $* kept failing. Is another apt process stuck?"
    warn "apt-get failed (apt busy?), retrying in 10 seconds ($attempt/30)..."
    sleep 10
  done
}

# Why a reboot is needed, e.g. "running kernel 6.8.0-31-generic, installed 6.8.0-85-generic".
reboot_reason() {
  local running newest
  running=$(uname -r)
  newest=$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null | sed 's/^vmlinuz-//' | sort -V | tail -n1)
  if [[ -n $newest && $newest != "$running" ]]; then
    echo "running kernel $running, installed $newest"
  else
    echo "updated: $(sort -u /var/run/reboot-required.pkgs 2>/dev/null | paste -sd, - | sed 's/,/, /g')"
  fi
}

apt_install() {
  apt_get install -y --no-install-recommends "$@"
}

# write_file PATH [MODE] - writes stdin to PATH (root-owned), creating parent dirs.
# Sets WRITE_FILE_CHANGED=true|false so callers can restart/reload only when needed.
write_file() {
  local path=$1 mode=${2:-0644} tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $path ]] && cmp -s "$tmp" "$path"; then
    rm -f "$tmp"
    chown root:root "$path"
    chmod "$mode" "$path"
    WRITE_FILE_CHANGED=false
    info "unchanged $path"
    return 0
  fi
  install -D -m "$mode" -o root -g root "$tmp" "$path"
  rm -f "$tmp"
  # shellcheck disable=SC2034 # read by the steps
  WRITE_FILE_CHANGED=true
  info "wrote $path"
}

# shellcheck disable=SC2034 # used in the steps' heredocs
MANAGED_HEADER="# Managed by vps-setup - local changes will be overwritten when setup.sh runs again."
