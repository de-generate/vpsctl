# Step: docker - Docker Engine + Compose from Docker's official apt repository.

step_docker() {
  log "Installing Docker Engine from Docker's apt repository"

  # Ubuntu's own packages conflict with Docker's. Remove them if present.
  local pkg
  for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed'; then
      apt-get remove -y "$pkg"
    fi
  done

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

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

  # Shared network between Caddy and every app it routes to.
  if ! docker network inspect caddy &>/dev/null; then
    docker network create caddy >/dev/null
    info "created docker network 'caddy'"
  fi

  info "$(docker --version)"
  info "$(docker compose version)"
}
