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
  if [[ ${ID:-} != ubuntu ]]; then
    warn "This script targets Ubuntu Server, detected '${PRETTY_NAME:-unknown}'. Continuing anyway."
  fi
}

apt_install() {
  apt-get install -y --no-install-recommends "$@"
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
