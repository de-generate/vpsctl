# Step: ssh - key-only SSH login for the admin user, no root login.
#
# Runs last so a mistake here can't stop the other steps. The current SSH session
# stays open while sshd restarts, so you can still fix things if the new login fails.

SSHD_DROPIN=/etc/ssh/sshd_config.d/00-vps-setup.conf

step_ssh() {
  check_ssh_login_possible
  check_firewall_allows_ssh

  log "Hardening SSH server"
  # sshd uses the FIRST value it reads for each option and includes sshd_config.d/*.conf
  # in alphabetical order. The "00-" prefix makes our settings win over files such as
  # cloud-init's 50-cloud-init.conf (which often sets PasswordAuthentication yes).
  write_file "$SSHD_DROPIN" <<EOF
$MANAGED_HEADER

Port ${SSH_PORT}

# Authentication: public keys only, never root
PermitRootLogin no
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers ${SSH_ALLOW_USERS}
MaxAuthTries 3
LoginGraceTime 30

# Features we don't need. Local port forwarding (ssh -L) stays enabled so admin
# UIs can be reached through an SSH tunnel instead of being exposed publicly.
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding local
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no
PermitUserEnvironment no

# Disconnect dead clients after ~10 minutes
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  # sshd -t needs this directory, which doesn't exist yet when sshd is socket-activated.
  mkdir -p /run/sshd
  if ! sshd -t; then
    rm -f "$SSHD_DROPIN"
    die "sshd rejected the new configuration. Removed $SSHD_DROPIN, nothing was changed."
  fi

  # Ubuntu 22.10+ starts sshd through ssh.socket, whose listening port is generated
  # from sshd_config. Reload the generators so a changed Port takes effect.
  if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    systemctl daemon-reload
    systemctl restart ssh.socket
  fi
  systemctl restart ssh.service

  info "Effective settings:"
  print_sshd_settings
}

# At least one user in AllowUsers must be able to log in with a key, or the new
# config would lock everybody out.
check_ssh_login_possible() {
  local user home ok=""
  for user in $SSH_ALLOW_USERS; do
    [[ $user != root ]] || continue
    home=$(getent passwd "$user" | cut -d: -f6) || continue
    if ssh-keygen -lf "$home/.ssh/authorized_keys" &>/dev/null; then ok+=" $user"; fi
  done
  [[ -n $ok ]] || die "No user in SSH_ALLOW_USERS ('$SSH_ALLOW_USERS') has a valid SSH key." \
    "Refusing to disable password login. Run the 'user' step first or fix SSH_ALLOW_USERS."
  info "Users who can log in with a key:$ok"
}

# A changed SSH_PORT must be open in UFW before sshd moves to it (e.g. when only this
# step is run). Accepts rules like "2222/tcp", "2222" and the OpenSSH app profile.
check_firewall_allows_ssh() {
  local status rule="${SSH_PORT}(/tcp)?"
  status=$(ufw status 2>/dev/null) || return 0
  [[ $status == *"Status: active"* ]] || return 0
  if [[ $SSH_PORT == 22 ]]; then rule="(22(/tcp)?|OpenSSH)"; fi
  grep -qE "^${rule}( \(v6\))? +(ALLOW|LIMIT)" <<<"$status" \
    || die "UFW is active but doesn't allow SSH on port ${SSH_PORT}. Run the 'firewall' step first."
}

print_sshd_settings() {
  sshd -T 2>/dev/null \
    | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|authenticationmethods|allowusers) ' \
    | sed 's/^/      /'
}
