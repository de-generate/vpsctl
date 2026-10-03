# vps-setup

Scripts and docs for setting up and running a general-purpose Ubuntu Server VPS for side projects.

`setup.sh` turns a fresh VPS (logged in as root) into a basic, secure server:

| Step       | What it does |
|------------|--------------|
| `packages` | Full system upgrade, base tooling (curl, git, htop, ncdu, jq, tmux, …) |
| `system`   | Hostname, timezone, NTP time sync, swap file, kernel network hardening (sysctl) |
| `user`     | Non-root admin user (`vps` by default) with sudo and your SSH key(s) |
| `upgrades` | Automatic security updates, optional automatic reboot at night |
| `firewall` | UFW for IPv4 and IPv6: deny incoming, allow outgoing, open SSH, 80/tcp, 443/tcp, 443/udp |
| `fail2ban` | Bans IPs that brute-force SSH, with longer bans for repeat offenders |
| `docker`   | Docker Engine + Compose from Docker's repo, log limits, auto-upgrades |
| `caddy`    | Caddy reverse proxy (container) with automatic HTTPS, `/srv` layout |
| `vpsctl`   | App management CLI on the server, weekly auto-update of app images |
| `ssh`      | Key-only login, no root login, unused features disabled |

## Requirements

- **Server:** Ubuntu Server 24.04 LTS or newer (LTS recommended: Docker's repo supports new releases only after a few weeks), x86_64 or arm64, a fresh install with root SSH access.
- **Resources:** works on 1 vCPU / 1 GB RAM for static sites; **2 GB RAM** recommended once Docker apps are built on the server. Docker images grow quickly, so plan for 20 GB disk or more.
- **DNS:** a domain whose records (ideally a wildcard `*.example.com`) point at the server.
- **Your machine:** `ssh` and `tar`, plus bash for the deploy client (Git Bash or WSL on Windows, macOS, Linux).

## Quick start

```bash
# on your machine
scp -r vps-setup root@<server-ip>:/root/

# on the server (as root)
cd /root/vps-setup
cp setup.conf.example setup.conf && nano setup.conf
bash setup.sh
```

Then **before closing the root session**, check in a new terminal that `ssh vps@<server-ip>` works.

Full walkthrough: [docs/01-initial-setup.md](docs/01-initial-setup.md).

Steps are idempotent and can be run on their own, e.g. `bash setup.sh firewall ssh`. `bash setup.sh --list` lists them.

## Deploying apps

From your own machine, with `bin/vps` on your PATH (works in Git Bash, WSL, macOS and Linux):

```bash
vps my-vps deploy static todo.example.com ./dist        # static site → https://todo.example.com
vps my-vps deploy docker my-api ./my-api --password     # compose project, built on the server
vps my-vps ls                                           # what runs where
vps my-vps logs my-api -f
```

Full guide: [docs/02-deploying-apps.md](docs/02-deploying-apps.md).

## Layout

```
setup.sh              entry point: loads config, runs steps in order
setup.conf.example    configuration template (copy to setup.conf, which is git-ignored)
lib/common.sh         shared helpers (logging, write_file, apt_install)
lib/<step>.sh         one file per step, each defines step_<name>()
bin/vps               client: deploy/manage apps over SSH (runs on your machine)
bin/vpsctl            server-side CLI, installed to /usr/local/bin by the vpsctl step
examples/             a static site, a ready-made image and a custom-built app
docs/                 setup guide, deploying apps, security model, troubleshooting, future improvements
```

## Docs

- [Initial setup](docs/01-initial-setup.md)
- [Deploying apps](docs/02-deploying-apps.md)
- [Security model](docs/security.md): what protects what, and what doesn't
- [Troubleshooting](docs/troubleshooting.md): lockouts, fail2ban, line endings, disk space
- [Future improvements](docs/future-improvements.md): deploy ideas, backups, monitoring, protecting dashboards
