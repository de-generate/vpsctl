# Step: firewall - UFW with deny-incoming / allow-outgoing defaults.
#
# NOTE: ports published by Docker containers bypass UFW (Docker writes its own iptables
# rules). Only Caddy (80/443) and deliberately published non-HTTP services do that; see
# "Non-HTTP services" in docs/02-deploying-apps.md.

step_firewall() {
  log "Configuring UFW firewall"

  # Make sure IPv6 traffic is filtered too. With IPV6=no, a server that has a public
  # IPv6 address would be completely unfiltered over IPv6. ufw has no drop-in
  # directory, so this one key is edited in place. Runs before the rules below so
  # they get created for IPv6 as well.
  if ! grep -q '^IPV6=yes' /etc/default/ufw; then
    if grep -q '^IPV6=' /etc/default/ufw; then
      sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
      echo 'IPV6=yes' >>/etc/default/ufw
    fi
    info "enabled IPv6 filtering in /etc/default/ufw"
  fi

  # Existing rules are kept (no reset) so manually added rules survive re-runs.
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw default deny routed >/dev/null

  ufw allow "${SSH_PORT}/tcp" comment 'SSH' >/dev/null
  ufw allow 80/tcp comment 'HTTP' >/dev/null
  ufw allow 443/tcp comment 'HTTPS' >/dev/null
  ufw allow 443/udp comment 'HTTPS (HTTP/3)' >/dev/null

  # Established connections (like this SSH session) keep working when UFW turns on.
  ufw --force enable >/dev/null
  ufw reload >/dev/null
  ufw status verbose | sed 's/^/    /'

  if [[ $SSH_PORT != 22 ]] && ufw status | grep -qE '^22/tcp .*ALLOW'; then
    warn "Port 22 is still allowed in UFW. Once you've confirmed SSH works on port ${SSH_PORT}, remove it: sudo ufw delete allow 22/tcp"
  fi
}
