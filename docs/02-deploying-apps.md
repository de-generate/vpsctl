# Deploying apps

Two kinds of things can be hosted, both deployed from your own machine with one command:

| Type | What you deploy | Lives on the server at | Reachable at |
|---|---|---|---|
| **static** | a folder of files (HTML/JS/CSS, a built frontend) | `/srv/static/<hostname>/` | `https://<hostname>` |
| **docker** | a folder with a `compose.yaml` (plus optional Dockerfile, source, `.env`) | `/srv/docker/<name>/` | the domains in its `vps.domains` labels |

Nothing needs a git repo or an image registry. Docker images are either pulled (ready-made images) or built on the server from the uploaded folder.

## How it works

```
your machine                         server
────────────                         ──────────────────────────────────────────────────
vps (bin/vps)  ── tar over SSH ──▶   vpsctl  ──▶ /srv/static/<hostname>/
                                             ──▶ /srv/docker/<name>/ + docker compose up
                                             ──▶ /srv/vps/caddy/etc/sites/*.caddy (routes)
                                                         │
                                     Caddy container ◀───┘ reload
                                     (ports 80/443, HTTPS certificates)
```

- **Caddy** runs as a container on ports 80/443 and gets a Let's Encrypt certificate for every hostname it serves.
- **Static sites** are served by a catch-all: a request for `foo.example.com` is answered from `/srv/static/foo.example.com/` if that folder exists. The certificate is requested on the first visit, only for hostnames that have a folder.
- **Docker apps** get a generated route per service with a `vps.domains` label. vpsctl also attaches those services to the shared `caddy` network, so compose files don't need any network or port configuration. **Don't publish ports** (`ports:`); they'd bypass the firewall (see [future-improvements.md](future-improvements.md#docker-and-ufw)).
- Every deploy **replaces** the app folder completely. Persistent data goes in named volumes or `/srv/data/<name>/` (see [Data](#data)).

## Setting up the client

The `vps` client is a bash script that needs only `ssh` and `tar`. It works in Git Bash or WSL on Windows, and on macOS and Linux.

Put this repo's `bin/` folder on your PATH, e.g. in `~/.bashrc`:

```bash
export PATH="$PATH:$HOME/projects/vps-setup/bin"
```

The first argument of every command is an **SSH target**, which is passed straight to `ssh`. That's a host from `~/.ssh/config` or `user@ip`. With several servers, give each one a Host entry:

```
# ~/.ssh/config
Host my-vps
    HostName 203.0.113.10
    User vps
```

```bash
vps my-vps ls
vps vps@203.0.113.10 ls      # works too
```

Your DNS needs to point each hostname at the server. With a wildcard record (`*.example.com → server IP`), every subdomain works without touching DNS. A bare domain (`example.com`) needs its own A/AAAA record.

## Workflows

### Static site / frontend app

```bash
npm run build
vps my-vps deploy static todo.example.com ./dist
# → https://todo.example.com
```

- Any hostname works, including bare domains (`example.com`) and other domains you own.
- Redeploying replaces the whole folder, so files deleted locally disappear from the server too.
- **Single-page apps:** a path without a file extension that doesn't exist (e.g. `/settings/profile`) is answered with `/index.html`, so client-side routing works. Missing files with an extension (`/app.js`) still return 404.
- Dotfiles (`.env`, `.git/…`) are never served.
- The first visit takes a few seconds while the certificate is issued.

### Ready-made image (compose file only)

```yaml
# whoami/compose.yaml
services:
  web:
    image: traefik/whoami:latest
    restart: unless-stopped
    mem_limit: 64m
    labels:
      vps.domains: whoami.example.com
      vps.port: "80"
```

```bash
vps my-vps deploy docker whoami ./whoami
```

### Custom app with a Dockerfile

```
my-api/
├── Dockerfile
├── compose.yaml      # build: .
├── .env              # secrets, uploaded with the deploy (keep it out of git)
└── src/…
```

```yaml
services:
  web:
    build: .
    restart: unless-stopped
    mem_limit: 256m
    env_file: .env
    volumes:
      - /srv/data/my-api:/data
    labels:
      vps.domains: api.example.com, api.example2.com
      vps.port: "8080"
  db:
    image: postgres:17          # pin major versions of databases!
    restart: unless-stopped
    mem_limit: 256m
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - db:/var/lib/postgresql/data

volumes:
  db:
```

```bash
vps my-vps deploy docker my-api ./my-api
```

The image is built on the server (`docker compose up -d --build`). Only the service with `vps.domains` is reachable from outside. `db` stays on the app's private network.

Working examples are in [`examples/`](../examples): `static-site`, `docker-image` and `docker-build`.

## Labels

| Label | Meaning |
|---|---|
| `vps.domains` | Hostname(s) to route to this service, separated by commas or spaces. Required for the service to be reachable. |
| `vps.port` | Port the service listens on inside the container. Default `80`. Quote it in YAML (`"8080"`). |
| `vps.auto-update` | `"false"` excludes the service from the weekly automatic update. |

A hostname can only belong to one app or static site; deploys that would take over someone else's hostname are refused.

## Password protection

Any static site or Docker app can be put behind HTTP basic auth:

```bash
vps my-vps deploy static secret.example.com ./dist --password          # asks for the password
vps my-vps deploy docker my-api ./my-api --password --user friend
vps my-vps deploy docker my-api ./my-api --password='s3cret'            # non-interactive; ends up in shell history
vps my-vps deploy docker my-api ./my-api --no-password                  # remove it
```

The password is sent over the SSH connection and only a bcrypt hash is stored on the server. It **stays in place on later deploys** until you use `--no-password`. The default username is `user`.

## Managing apps

```bash
vps my-vps ls
# TYPE    NAME               DOMAINS             STATUS       PASSWORD
# static  todo.example.com   todo.example.com    -            -
# docker  my-api             api.example.com     running 2/2  yes

vps my-vps logs my-api            # last 200 lines
vps my-vps logs my-api -f         # follow (Ctrl+C to stop)
vps my-vps logs caddy             # the reverse proxy, for certificate problems
vps my-vps restart my-api
vps my-vps update my-api          # pull new images + rebuild with fresh base images
vps my-vps update --all
vps my-vps rm todo.example.com    # asks for confirmation (--yes skips it)
vps my-vps rm my-api              # keeps named volumes and /srv/data/my-api
vps my-vps rm my-api --volumes    # also deletes named volumes
vps my-vps sync                   # regenerate all routes (see troubleshooting)
```

When logged in to the server, the same commands are available as `vpsctl …` (e.g. `vpsctl ls`).

## Updates

- **Weekly (automatic):** every Sunday around 03:00, services that use a **ready-made image** get the newest version of their tag and are restarted, including Caddy itself. Then unused images and old build cache are removed. Custom-built services are **not** rebuilt automatically.
- **Manual:** `vps <target> update <name>` pulls images *and* rebuilds custom services with fresh base images.
- **Opting out:** `vps.auto-update: "false"` on a service. Change the schedule with `AUTO_UPDATE_SCHEDULE`, or disable it with `AUTO_UPDATE=false` in `setup.conf`.

Auto-updates follow the image **tag**. `:latest` gets every new version, including breaking ones. Pin what must stay stable, **especially databases**: `postgres:latest` jumping a major version can't read its old data files, while `postgres:17` only gets patch releases. Check the timer's last run with `journalctl -u vps-auto-update`.

## Data

A deploy replaces `/srv/docker/<name>/` completely. Data written there is lost (vpsctl warns about writable bind mounts into the app folder). Use one of:

- **Named volumes** (`volumes: [db:/var/lib/postgresql/data]`). Managed by Docker, kept on redeploy and on `rm` (unless `--volumes`).
- **Bind mounts to `/srv/data/<name>/`** (`/srv/data/my-api:/data`). Plain files you can inspect, and never touched by vpsctl. Create the folder once with the owner your container expects. `/srv/data` belongs to the `vps` user.

Both locations are what a backup needs to cover later.

## What gets uploaded

- The whole folder, except `.git`, and also `node_modules` for docker deploys.
- Extra patterns can go in a `.vpsignore` file in the folder (tar exclude patterns, one per line, e.g. `*.log`, `tmp`).
- `.env` files **are** uploaded on purpose: that's how secrets reach the server without being in git.

## Resource limits

With 2 GB RAM, set `mem_limit` on every service. A runaway app then gets killed instead of taking the whole server (and every other app) down. Building images on the server works thanks to the swap file, but can be slow for large projects.
