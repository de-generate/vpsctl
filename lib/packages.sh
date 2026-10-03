# Step: packages - bring the system up to date and install base tooling.

step_packages() {
  log "Updating package lists and upgrading the system"
  apt-get update
  apt-get -y \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    full-upgrade

  log "Installing base packages"
  apt_install \
    ca-certificates curl wget gnupg git \
    ufw fail2ban python3-systemd \
    unattended-upgrades apt-listchanges \
    htop ncdu jq tmux vim less unzip rsync

  apt-get -y autoremove --purge
  apt-get -y autoclean

  if [[ -f /var/run/reboot-required ]]; then
    warn "A reboot is required to finish applying updates (e.g. a new kernel). Reboot once setup is done."
  fi
}
