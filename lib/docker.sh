# Step: docker - Docker Engine + Compose from Docker's official apt repository.

# https://docs.docker.com/engine/install/ubuntu/ - Docker's release signing key.
DOCKER_KEY_FINGERPRINT=9DC858229FC7DD38854AE2D88D81803C0EBFCD88

step_docker() {
  log "Installing Docker Engine from Docker's apt repository"

  # Ubuntu's own packages conflict with Docker's. Remove them if present.
  local pkg
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
      apt-get remove -y "$pkg"
    fi
  done

  # Only trust the downloaded key if it is Docker's known release signing key.
  local key fingerprint
  key=$(mktemp)
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$key"
  fingerprint=$(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
  if [[ $fingerprint != "$DOCKER_KEY_FINGERPRINT" ]]; then
    rm -f "$key"
    die "Docker's apt key has an unexpected fingerprint ('$fingerprint'). Refusing to trust it."
  fi
  install -D -m 0644 "$key" /etc/apt/keyrings/docker.asc
  rm -f "$key"

  # shellcheck source=/dev/null
  . /etc/os-release
  write_file /etc/apt/sources.list.d/docker.sources <<EOF
$MANAGED_HEADER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Configuring the Docker daemon"
  # - Container logs are capped (3 x 10 MB per container) so they can't fill the disk.
  # - live-restore keeps containers running while dockerd restarts, e.g. during upgrades.
  write_file /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF
  systemctl enable --now docker.service containerd.service >/dev/null
  if $WRITE_FILE_CHANGED; then
    systemctl restart docker.service
  fi

  if [[ $DOCKER_AUTO_UPGRADE == true ]]; then
    # Origins-Pattern entries from all apt.conf.d files are merged, so this only adds Docker's repo.
    write_file /etc/apt/apt.conf.d/52unattended-upgrades-docker <<EOF
$MANAGED_HEADER
Unattended-Upgrade::Origins-Pattern {
        "origin=Docker";
};
EOF
  else
    rm -f /etc/apt/apt.conf.d/52unattended-upgrades-docker
  fi

  # Lets vpsctl manage containers without sudo. NOTE: docker group membership is root-equivalent.
  usermod -aG docker "$VPS_USER"

  # Caddy's own network. Apps get separate per-app networks from vpsctl ("vps-<app>").
  if ! docker network inspect caddy &>/dev/null; then
    docker network create caddy >/dev/null
    info "created docker network 'caddy'"
  fi

  info "$(docker --version)"
  info "$(docker compose version)"
}
