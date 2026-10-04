# Step: packages - bring the system up to date and install base tooling.

step_packages() {
  # On a fresh VPS, cloud-init may still be configuring the system (and running apt).
  if command -v cloud-init >/dev/null; then
    log "Waiting for cloud-init to finish the first boot"
    cloud-init status --wait >/dev/null || warn "cloud-init reported a problem (see: cloud-init status --long). Continuing."
  fi

  log "Updating package lists and upgrading the system"
  apt_get update
  apt_get -y \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    full-upgrade

  log "Installing base packages"
  apt_install \
    ca-certificates curl wget gnupg git \
    ufw fail2ban python3-systemd \
    unattended-upgrades apt-listchanges \
    htop ncdu jq tmux vim less unzip rsync

  apt_get -y autoremove --purge
  apt_get -y autoclean

  if [[ -f /var/run/reboot-required ]]; then
    warn "A reboot is required to finish the updates ($(reboot_reason))." \
      "Setup continues on the current kernel; reboot once it's done."
  fi
}
