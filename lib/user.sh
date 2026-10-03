# Step: user - create the non-root admin user with sudo rights and SSH keys.

step_user() {
  local home ssh_dir keys_file

  log "Setting up admin user '$VPS_USER'"
  if id "$VPS_USER" &>/dev/null; then
    info "User already exists"
  else
    adduser --disabled-password --gecos "" "$VPS_USER"
  fi
  usermod -aG sudo "$VPS_USER"

  # sudo asks for this password. SSH login itself is key-only, so the password is
  # a second factor for becoming root, not a way to log in.
  if [[ $(passwd -S "$VPS_USER" | awk '{print $2}') != P ]]; then
    [[ -t 0 ]] || die "User '$VPS_USER' has no password and stdin is not a terminal. Run setup.sh interactively."
    info "Choose a password for '$VPS_USER' (used for sudo, not for SSH login):"
    until passwd "$VPS_USER"; do warn "Try again."; done
  else
    info "Password already set"
  fi

  home=$(getent passwd "$VPS_USER" | cut -d: -f6)
  ssh_dir="$home/.ssh"
  keys_file="$ssh_dir/authorized_keys"
  install -d -m 700 -o "$VPS_USER" -g "$VPS_USER" "$ssh_dir"
  touch "$keys_file"

  log "Installing SSH keys for '$VPS_USER'"
  {
    if [[ -n $SSH_PUBKEY ]]; then printf '%s\n' "$SSH_PUBKEY"; fi
    # Reuse root's keys. Providers sometimes prefix them with options such as
    # command="echo 'Please login as ...'", so only keep "<type> <key> [comment]".
    if [[ -f /root/.ssh/authorized_keys ]]; then extract_pubkeys </root/.ssh/authorized_keys; fi
  } | while IFS= read -r key; do
    [[ -n $key ]] || continue
    if ! grep -qF -- "$(awk '{print $2}' <<<"$key")" "$keys_file"; then
      printf '%s\n' "$key" >>"$keys_file"
      info "added: $(ssh-keygen -lf - <<<"$key" 2>/dev/null || echo "$key")"
    fi
  done

  chown "$VPS_USER:$VPS_USER" "$keys_file"
  chmod 600 "$keys_file"

  if ! ssh-keygen -lf "$keys_file" &>/dev/null; then
    die "No valid SSH public key for '$VPS_USER'. Set SSH_PUBKEY in setup.conf (or add a key to /root/.ssh/authorized_keys) and re-run."
  fi
}

# Reads authorized_keys lines on stdin and prints them without leading options.
extract_pubkeys() {
  awk '!/^[[:space:]]*(#|$)/ {
    for (i = 1; i < NF; i++)
      if ($i ~ /^(ssh-|ecdsa-|sk-)/ && $(i + 1) ~ /^AAAA/) {
        out = $i
        for (j = i + 1; j <= NF; j++) out = out " " $j
        print out
        next
      }
  }'
}
