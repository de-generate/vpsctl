# Step: system - hostname, timezone, time sync, swap and kernel (sysctl) hardening.

step_system() {
  configure_hostname
  configure_time
  configure_swap
  configure_sysctl
}

configure_hostname() {
  if [[ -z $VPS_HOSTNAME ]]; then
    info "VPS_HOSTNAME not set, keeping hostname '$(hostname)'"
    return
  fi

  log "Setting hostname to '$VPS_HOSTNAME'"
  hostnamectl set-hostname "$VPS_HOSTNAME"

  # /etc/hosts has no drop-in directory, so its 127.0.1.1 line is edited in place
  # (an accepted exception, see AGENTS.md). VPS_HOSTNAME is validated in load_config.
  # For a FQDN, the short name is kept as an alias.
  local entry="127.0.1.1 $VPS_HOSTNAME"
  if [[ $VPS_HOSTNAME == *.* ]]; then entry+=" ${VPS_HOSTNAME%%.*}"; fi
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/$entry/" /etc/hosts
  else
    echo "$entry" >>/etc/hosts
  fi

  # Stop cloud-init (used by most VPS providers) from resetting the hostname and
  # regenerating /etc/hosts on reboot.
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    write_file /etc/cloud/cloud.cfg.d/99-vps-setup-hostname.cfg <<EOF
$MANAGED_HEADER
preserve_hostname: true
manage_etc_hosts: false
EOF
  fi
}

configure_time() {
  log "Setting timezone to '$VPS_TIMEZONE' and enabling time sync"
  timedatectl set-timezone "$VPS_TIMEZONE"

  # Ubuntu ships either systemd-timesyncd (24.04) or chrony (25.10+). Only install one if neither exists.
  if ! systemctl list-unit-files chrony.service systemd-timesyncd.service 2>/dev/null | grep -q '\.service'; then
    apt_install systemd-timesyncd
  fi
  timedatectl set-ntp true || warn "Could not enable NTP time sync."
}

configure_swap() {
  log "Configuring swap"
  if [[ $SWAP_SIZE == 0 ]]; then
    info "SWAP_SIZE=0, skipping"
  elif [[ -n $(swapon --show --noheadings) ]]; then
    info "Swap already active, skipping:"
    swapon --show | sed 's/^/    /'
  else
    info "Creating ${SWAP_SIZE} swap file at /swapfile"
    if ! fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null; then
      # fallocate is not supported on every filesystem; fall back to dd.
      dd if=/dev/zero of=/swapfile bs=1M count=$(( $(numfmt --from=iec "$SWAP_SIZE") / 1024 / 1024 )) status=progress
    fi
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
  fi
}

configure_sysctl() {
  log "Applying kernel network hardening (sysctl)"
  # IP forwarding is deliberately left untouched: Docker needs it.
  write_file /etc/sysctl.d/99-vps-setup.conf <<EOF
$MANAGED_HEADER

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Ignore ICMP redirects and source-routed packets (we are not a router)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore broadcast pings and bogus ICMP errors
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Hide kernel pointers and restrict dmesg to root
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# Only swap under real memory pressure
vm.swappiness = ${SWAPPINESS}
EOF
  sysctl --system >/dev/null
}
