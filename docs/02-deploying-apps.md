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
- **Docker apps** get a generated route per service with a `vps.domains` label. vpsctl also attaches those services to a network of their own (`vps-<name>`) that only Caddy joins, so compose files don't need any network or port configuration. Apps can't reach each other over it, and a password set with `--password` can't be bypassed by talking to the container from another app. **Web apps don't publish ports** (`ports:`). Caddy reaches them over the network, and published ports bypass the firewall. Non-HTTP services are the exception, see [Non-HTTP services](#non-http-services-game-servers-voice-chat-).
- Every deploy **replaces** the app folder completely. Persistent data goes in named volumes or `/srv/data/<name>/` (see [Data](#data)).

## Setting up the client

The `vps` client is a bash script that needs only `ssh` and `tar`. It works in Git Bash or WSL on Windows, and on macOS and Linux. It's kept compatible with bash 3.2 (macOS's default) and with both GNU tar and bsdtar.

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
    IdentitiesOnly yes
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
- Symlinks must stay inside the site folder and be relative. Others are rejected, because Caddy follows them and could otherwise serve files from outside the site.
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
      vps.http-port: "80"
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
      vps.http-port: "8080"
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

`vps.domains` and `vps.http-port` together configure **HTTP routing through Caddy** (HTTPS, certificates, optional password). They only make sense for services that speak HTTP. For anything else, see [Non-HTTP services](#non-http-services-game-servers-voice-chat-).

| Label | Meaning |
|---|---|
| `vps.domains` | Hostname(s) Caddy routes to this service over HTTPS, separated by commas or spaces. Without it, the service gets no web route. |
| `vps.http-port` | Port the service serves HTTP on *inside* the container (not a published host port). Default `80`. Quote it in YAML (`"8080"`). |
| `vps.auto-update` | `"false"` excludes the service from the weekly automatic update. |

A hostname can only belong to one app or static site; deploys that would take over someone else's hostname are refused. A service with `vps.domains` can't use `network_mode` (Caddy couldn't reach it).

## Compose file checklist

- **`restart: unless-stopped` on every service.** Without it, the service stays down after a reboot, and with `AUTO_REBOOT=true` the server reboots on its own after kernel updates. `vpsctl` warns about services without a restart policy.
- **`mem_limit`** on every service (see [Resource limits](#resource-limits)).
- **No `ports:`** for web apps; routing goes through `vps.domains`.
- **Persistent data** in named volumes or `/srv/data/<name>/` (see [Data](#data)).
- **Pinned tags** for anything stateful, especially databases (see [Updates](#updates)).

## robots.txt

Every site answers `/robots.txt` with a global file, [`config/robots.txt`](../config/robots.txt) in this repo. It's served publicly as-is, so it contains no comments.

- **Static sites** can ship their own `robots.txt`; it takes precedence over the global one.
- **Docker apps** always get the global file, even if the app serves its own.
- `robots.txt` is reachable **without** the password on password-protected sites, so crawlers get a clear answer instead of a 401.

The default is an **allowlist**: everything is disallowed (`User-agent: *`), except for named crawlers:

- **Search engines:** Googlebot, Bingbot (also behind DuckDuckGo, Ecosia and Yahoo results), DuckDuckBot, Applebot (Siri/Spotlight), MojeekBot.
- **Link previews** for links shared in chats and social media: Twitterbot, facebookexternalhit, LinkedInBot, Slackbot, Discordbot, TelegramBot. Without them, shared links show no title or image on the services that respect `robots.txt`.

Everything else falls under `User-agent: *` and is disallowed. That includes AI training crawlers (GPTBot, ClaudeBot, CCBot, …), new ones nobody has listed yet, and the AI-use tokens `Google-Extended` and `Applebot-Extended`. Those tokens let Google and Apple keep indexing a site for search while it opts out of AI training.

Keep in mind that `robots.txt` is a request, not access control. Well-behaved crawlers follow it; scrapers that ignore it aren't stopped. Actually blocking user agents in Caddy is listed in [future-improvements.md](future-improvements.md#deploying-apps-vps--vpsctl).

To change it, edit `config/robots.txt` and run `sudo bash setup.sh caddy` on the server (no restart needed). To allow another crawler, add a `User-agent:` line to the first group. To keep all crawlers out:

```
User-agent: *
Disallow: /
```

The opposite approach, allowing everything and blocking known AI crawlers by name, is maintained as a list at [ai-robots-txt/ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt). It needs regular updates, while the allowlist doesn't.

Hostnames that don't serve anything can't answer either, because there is no certificate for them (see [Troubleshooting](troubleshooting.md#apps-and-sites)).

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
# TYPE    NAME               DOMAINS             PORTS              STATUS       PASSWORD
# static  todo.example.com   todo.example.com    -                  -            -
# docker  my-api             api.example.com     -                  running 2/2  yes
# docker  mumble             -                   1234/tcp,1234/udp  running 1/1  -
# Auto-update: last run Sun 2026-10-04 03:07:12 UTC (ok).

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

Auto-updates follow the image **tag**. `:latest` gets every new version, including breaking ones. Pin what must stay stable, **especially databases**: `postgres:latest` jumping a major version can't read its old data files, while `postgres:17` only gets patch releases. `vps <target> ls` shows the result of the last run (and a warning if it failed); details are in `journalctl -u vps-auto-update`.

## Data

A deploy replaces `/srv/docker/<name>/` completely. Data written there is lost (vpsctl warns about writable bind mounts into the app folder). Use one of:

- **Named volumes** (`volumes: [db:/var/lib/postgresql/data]`). Managed by Docker, kept on redeploy and on `rm` (unless `--volumes`).
- **Bind mounts to `/srv/data/<name>/`** (`/srv/data/my-api:/data`). Plain files you can inspect, and never touched by vpsctl. Create the folder once with the owner your container expects. `/srv/data` belongs to the `vps` user.

Both locations are what a backup needs to cover later.

## What gets uploaded

- The whole folder, except `.git`, and also `node_modules` for docker deploys.
- Extra patterns can go in a `.vpsignore` file in the folder (tar exclude patterns, one per line, e.g. `*.log`, `tmp`).
- `.env` files **are** uploaded on purpose: that's how secrets reach the server without being in git. On the server they're made readable only by the `vps` user.

## Non-HTTP services (game servers, voice chat, …)

Services that don't speak HTTP can't go through Caddy. They publish a port directly instead, e.g. a Mumble server:

```yaml
services:
  mumble:
    image: mumblevoip/mumble-server:latest
    restart: unless-stopped
    mem_limit: 128m
    ports:
      - "1234:64738/tcp"   # host port : container port
      - "1234:64738/udp"   # many such services need UDP as well; TCP is the default
    volumes:
      - data:/data

volumes:
  data:
```

```bash
vps my-vps deploy docker mumble ./mumble
# Deployed mumble.
#   published ports: 1234/tcp, 1234/udp
```

Things to know:

- **No `vps.*` routing labels.** They create an HTTPS route in Caddy, which would only show a 502 for a non-HTTP service. The hostname works without them: with DNS pointing at the server, clients connect to `mumble.example.com:1234` directly.
- **UFW does not apply.** Docker opens published ports itself, on IPv4 and IPv6, as soon as the container runs. A `sudo ufw allow 1234` documents the intent but doesn't change anything. **The provider firewall is the real gate:** open the port there (TCP and/or UDP, and IPv6 if it has separate rules).
- **Ports 80 and 443 belong to Caddy.** Any other free port works. Two apps can't publish the same host port; the second deploy fails with "port is already allocated".
- **No Caddy protection.** TLS and `--password` only apply to HTTP routes, and fail2ban only watches SSH. Security is whatever the service itself provides (e.g. Mumble's own encryption and server password).
- **Admin ports you don't want public:** bind them to localhost (`"127.0.0.1:8081:8080"`) and use an SSH tunnel: `ssh -L 8081:localhost:8081 my-vps`.
- `vps <target> ls` shows published ports in the `PORTS` column. Localhost-only ports are listed with their address (`127.0.0.1:8081/tcp`).
- An app can mix both: a web UI routed via `vps.domains` plus a published game port.

## Resource limits

With 2 GB RAM, set `mem_limit` on every service. A runaway app then gets killed instead of taking the whole server (and every other app) down. Building images on the server works thanks to the swap file, but can be slow for large projects.
