# Step: upgrades - automatic security updates via unattended-upgrades.

step_upgrades() {
  log "Configuring unattended security upgrades"

  write_file /etc/apt/apt.conf.d/20auto-upgrades <<EOF
$MANAGED_HEADER
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # Ubuntu's 50unattended-upgrades already enables the -security pocket; this only adds overrides.
  write_file /etc/apt/apt.conf.d/52unattended-upgrades-vps-setup <<EOF
$MANAGED_HEADER
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";
EOF

  systemctl enable --now unattended-upgrades.service >/dev/null
  info "Automatic reboot: ${AUTO_REBOOT} (at ${AUTO_REBOOT_TIME} when required)"
}
