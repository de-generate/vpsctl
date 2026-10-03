# Step: fail2ban - ban IPs that repeatedly fail SSH authentication.

step_fail2ban() {
  log "Configuring fail2ban"

  write_file /etc/fail2ban/jail.local <<EOF
$MANAGED_HEADER

[DEFAULT]
# Read logs from the systemd journal (works even without rsyslog / auth.log)
backend = systemd
ignoreip = 127.0.0.1/8 ::1${FAIL2BAN_IGNOREIP:+ $FAIL2BAN_IGNOREIP}
findtime = 10m
maxretry = 5
bantime = 1h
# Repeat offenders get exponentially longer bans, up to one week
bantime.increment = true
bantime.maxtime = 1w

[sshd]
enabled = true
port = ${SSH_PORT}
mode = aggressive
EOF

  systemctl enable fail2ban >/dev/null
  systemctl restart fail2ban
  sleep 2
  fail2ban-client status sshd | sed 's/^/    /' || warn "fail2ban sshd jail is not running. Check: journalctl -u fail2ban"
}
