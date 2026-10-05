# Security model

What protects what on a server set up with this repo, and what doesn't. The details are spread over the other docs; this page puts them in one place.

## Who can do what

| Who | Can do | Protected by |
|---|---|---|
| Anyone on the internet | Reach ports 80/443 (Caddy) and any port a Docker app publishes on purpose | Provider firewall, UFW (not for Docker-published ports), Caddy |
| Anyone with **your SSH private key** | Log in as `vps` and become **root** | Only the key itself |
| `vps` user | Everything, via `sudo` (password) **or** via Docker (no password) | — |
| A compromised app container | Whatever its container can reach: its own app's networks, and the internet | Per-app networks, Docker's isolation |

## The SSH key is the key to everything

- SSH accepts only keys, only for `SSH_ALLOW_USERS`, never for root.
- The `vps` user has a sudo password, but **it is not a second factor**: `vps` is in the `docker` group (so `vpsctl` works without sudo), and anyone in that group can become root, e.g. with `docker run -v /:/host …`.
- So: **protect the private key.** Use a passphrase (with an agent so you don't type it constantly), or a hardware key (`ssh-keygen -t ed25519-sk`). Don't copy it to machines you don't trust.
- fail2ban slows down brute force against SSH, but with key-only login that's mostly log hygiene.

## Network

- **UFW** denies everything incoming except SSH, 80/tcp, 443/tcp and 443/udp, for IPv4 and IPv6.
- **Docker-published ports bypass UFW.** Caddy's 80/443 are meant to be public. Web apps don't publish ports. Non-HTTP services that publish a port are public on purpose. The **provider firewall** is the real outer gate for those (see [Non-HTTP services](02-deploying-apps.md#non-http-services-game-servers-voice-chat-)).
- **Per-app networks:** each routed app gets its own Docker network (`vps-<name>`) that only its routed services and Caddy join. Apps can't reach each other's containers, and a service called `api` in one app never resolves to another app's `api`.

## Web traffic (Caddy)

- Every hostname gets HTTPS with a Let's Encrypt certificate. Certificates for static sites are only requested for hostnames that have a folder in `/srv/static` (no certificate spam for random hostnames).
- `--password` (HTTP basic auth) is enforced **by Caddy**. It protects the route, not the container. Thanks to the per-app networks, other apps can't go around it.
- For static sites, the password route is installed before the files go live, so a protected site is never briefly public.
- Static sites never serve dotfiles (`.env`, `.git/`), and uploads with symlinks pointing outside the site are rejected.
- **Not included:** no web application firewall, no rate limiting, no protection against bugs in your apps. fail2ban only watches SSH.
- Certificate Transparency logs are public, so every hostname that gets a certificate is **publicly listed**. Unlisted is not secret; use `--password` for things that must stay private.

## Secrets and data

- `.env` files uploaded with Docker apps are readable only by the `vps` user. Other uploaded files keep normal permissions, so secrets belong in `.env` (see [Secrets](02-deploying-apps.md#secrets)). Password hashes for basic auth are in `/srv/vps/auth/` (mode 600).
- There are no backups yet (see [future-improvements.md](future-improvements.md#backups)).

## Updates

- Ubuntu security updates install automatically (unattended-upgrades). With `AUTO_REBOOT=true` the server reboots at night when a kernel update needs it.
- Docker itself is upgraded the same way (`DOCKER_AUTO_UPGRADE`). Containers keep running during the upgrade.
- App images using ready-made images are updated weekly (`AUTO_UPDATE`); custom-built ones only when you redeploy or run `vps <target> update <name>`.
- Docker's apt key is only trusted if its fingerprint matches Docker's published release key.
