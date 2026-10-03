# Future improvements

Things that are planned or worth doing later, so they don't get forgotten.

## Docker and UFW

Already handled by convention, but good to remember: **ports published by Docker (`ports:` / `-p 8080:80`) bypass UFW**, because Docker writes its own iptables rules. This applies to **IPv6 as well**: even with Docker's own IPv6 support off, published ports listen on `[::]` and forward IPv6 traffic to the container.

The setup avoids it for web apps: only Caddy publishes ports (80/443, meant to be public), and apps are reached over per-app Docker networks. Non-HTTP services publish their port on purpose (see [Non-HTTP services](02-deploying-apps.md#non-http-services-game-servers-voice-chat-)). For ports that should *not* be public:

1. Bind it to localhost: `127.0.0.1:8080:80` (reach it through an SSH tunnel).
2. Use the provider firewall as an outer layer (only 22/80/443 open).
3. Optionally use [ufw-docker](https://github.com/chaifeng/ufw-docker) to make UFW rules apply to containers.

## Deploying apps (vps / vpsctl)

Ideas that were deliberately left out of the first version:

- **`--build-local`**: build images on your machine and stream them to the server (`docker save | ssh … docker load`) instead of building on the 2 GB server. Needs the same CPU architecture (or `docker buildx --platform linux/amd64`).
- **Rollbacks**: keep the previous `/srv/docker/<name>/` (and image tag) and add `vps <target> rollback <name>`. Today a failed deploy leaves the new files in place; fix and deploy again.
- **Changing a password without redeploying**: e.g. `vps <target> password <name>`. Today it's set with `deploy … --password`.
- **Per-site static options**: SPA fallback on/off, custom 404 page, caching headers, redirects (e.g. `www.` → bare domain). Could be a small `.vps.json` in the uploaded folder.
- **Default target**: a `VPS_TARGET` environment variable so the SSH target can be omitted.
- **Less privilege for vpsctl**: the `vps` user is in the `docker` group, which is root-equivalent (see [security.md](security.md)). Alternatives: rootless Docker, or a narrow `sudo` rule that only allows `vpsctl` (needs passwordless sudo for that one command, since deploys run non-interactively).
- **Update notifications**: report failed weekly auto-updates (e.g. to a self-hosted ntfy) instead of only `vps <target> ls` and the journal.
- **Access logs** for static sites and apps (Caddy `log` directive, with rotation).
- **App catalog**: pre-configured compose files for common self-hosted tools (Uptime Kuma, IT-Tools, …), possibly in a separate repo.
- **Web UI**: something like Dockge pointed at `/srv/docker`, reachable only through an SSH tunnel.
- **Git-based deploys**: `git push` to the server triggering a deploy. Only worth it if uploading folders starts to feel limiting.
- **Wildcard certificates**: would hide subdomain names from public Certificate Transparency logs. Needs a DNS API (Namecheap's has account requirements and IP whitelisting) and a custom Caddy build with the DNS plugin.

## Backups

Skipped for now: there is no backup target yet. Until then, back up manually before risky changes, and use provider snapshots if available.

When it's time:

- **Tool:** [restic](https://restic.net/). Encrypted, deduplicated and incremental, with retention policies (`forget --keep-daily 7 --keep-weekly 4`).
- **Target:** anything you control, such as a home server or NAS (over SFTP), a second cheap VPS or storage box, or a self-hosted S3-compatible store.
- **What to back up:** Docker named volumes, `/srv/data/`, `/srv/vps/auth/` (password hashes), **database dumps** (`pg_dump` / `mysqldump` before backing up; copying live database files is not safe), `/etc` and this repo's `setup.conf`.
- **Automation:** a systemd timer that runs dump → `restic backup` → `restic forget --prune`.
- **Test restoring.** A backup you've never restored is a guess.

## Monitoring

- **Uptime:** [Uptime Kuma](https://github.com/louislam/uptime-kuma) checks your sites and services and sends notifications (e.g. a self-hosted ntfy, or email). It's best run *somewhere other than* the VPS, or it can't tell you the VPS is down.
- **Resources:** [Beszel](https://github.com/henrygd/beszel) is lightweight CPU/RAM/disk/container history, a good fit for a 2 GB box. Netdata is more detailed but heavier.
- **Alerts worth having:** disk > 80 %, memory/swap pressure, a site is down, a certificate is close to expiring.
- Even without tools: `htop`, `ncdu`, `docker stats`, `journalctl -p warning -b`.

## Protecting dashboards

Any admin UI (Dockge, Portainer, Beszel, …) can usually take over the server. Ways to protect them, from simplest to most locked-down:

1. **Strong password + 2FA** (where supported), served over HTTPS on its own subdomain.
2. **Don't publish its port.** Route it through Caddy with `vps.domains`. Docker-published ports bypass UFW (see above).
3. **Extra auth in front of it:** `vps … deploy docker … --password` (Caddy basic auth), or a self-hosted SSO such as Authelia or Authentik for several apps.
4. **Don't expose it at all:** bind it to `127.0.0.1` and use an SSH tunnel. `setup.sh` keeps local forwarding enabled for this:
   ```bash
   ssh -L 8000:localhost:8000 vps     # then open http://localhost:8000
   ```
5. **Private network:** a self-hosted WireGuard tunnel to the VPS; admin UIs only listen on the WireGuard interface.

## Smaller ideas

- SSH login notifications (e.g. a PAM hook that sends to a self-hosted ntfy).
- `needrestart`/`checkrestart` reports after unattended upgrades.
- A `status.sh` that prints an overview: disk, memory, running containers, open ports (`ss -tulpn`), failed systemd units, pending reboot.
