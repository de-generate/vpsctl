# Step: vpsctl - install the app management CLI and the weekly auto-update timer.

step_vpsctl() {
  [[ -d /srv/vps ]] || die "/srv/vps is missing. Run the 'caddy' step first."

  log "Installing vpsctl"
  install -m 755 -o root -g root "$SCRIPT_DIR/bin/vpsctl" /usr/local/bin/vpsctl
  info "installed /usr/local/bin/vpsctl"

  log "Configuring automatic app updates"
  if [[ $AUTO_UPDATE == true ]]; then
    write_file /etc/systemd/system/vps-auto-update.service <<EOF
$MANAGED_HEADER
[Unit]
Description=Update Docker apps managed by vpsctl (image-based services only)
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
User=${VPS_USER}
ExecStart=/usr/local/bin/vpsctl update --all --auto
EOF
    write_file /etc/systemd/system/vps-auto-update.timer <<EOF
$MANAGED_HEADER
[Unit]
Description=Weekly update of Docker apps managed by vpsctl

[Timer]
OnCalendar=${AUTO_UPDATE_SCHEDULE}
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now vps-auto-update.timer >/dev/null
    info "next run: $(systemctl show vps-auto-update.timer -p NextElapseUSecRealtime --value)"
  else
    systemctl disable --now vps-auto-update.timer &>/dev/null || true
    rm -f /etc/systemd/system/vps-auto-update.{service,timer}
    systemctl daemon-reload
    info "AUTO_UPDATE=false, timer disabled"
  fi

  log "Syncing Caddy routes"
  runuser -u "$VPS_USER" -- /usr/local/bin/vpsctl sync
}
