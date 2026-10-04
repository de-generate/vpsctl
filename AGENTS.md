# AGENTS.md

Scripts and docs for bootstrapping and operating a general-purpose Ubuntu Server VPS (24.04 LTS+). See README.md for the overview and docs/security.md for the security model.

**Never run `setup.sh` (or `vpsctl`) on this machine.** They need root and change system configuration. In WSL they would really do it. All verification here is static; real runs happen on a server.

## Conventions

- **Bash, strict mode.** `setup.sh` runs with `set -euo pipefail`; `lib/*.sh` files are sourced, not executed, and have no shebang (`.shellcheckrc` sets the shell).
- **Shared namespace.** All `lib/*.sh` are sourced into one shell, so functions and globals are shared. Use `local` for everything in functions and give helpers step-specific names (e.g. `configure_*` in `system.sh`, `check_*` in `ssh.sh`).
- **One step per file.** `lib/<name>.sh` defines `step_<name>()`. Adding a step means updating all of:
  - `STEPS` and `STEP_DESCRIPTIONS` in `setup.sh` (order matters, `ssh` stays last)
  - the step table in `README.md`
  - the step order line and the "What exactly gets changed" table in `docs/01-initial-setup.md`
- **Idempotent.** Every step must be safe to run again. Write whole config files with `write_file` (starting with `$MANAGED_HEADER`) instead of appending or using `sed` on system files. Prefer drop-in directories (`*.d/`) over editing main configs. Accepted exceptions (no drop-in exists): `IPV6=` in `/etc/default/ufw` and the `127.0.1.1` line in `/etc/hosts`.
- **Config** lives in `setup.conf` (git-ignored). Each new option needs a default **and validation** in `load_config()` (values end up in system files), plus a documented entry in `setup.conf.example`.
- **Never lock the user out.** Anything touching SSH or the firewall must validate first (e.g. `sshd -t`, the checks in `lib/ssh.sh`) and keep the current session working.
- **LF line endings** (enforced by `.gitattributes`). The repo is edited on Windows but runs on Linux.
- Keep `docs/` in sync with behavior changes; ideas for later go in `docs/future-improvements.md`.

## App deployment (bin/vps, bin/vpsctl)

- **`bin/vps` is the client** and must stay thin and portable: **bash 3.2** (macOS) and both **GNU tar and bsdtar**, plus ssh. So no `${var,,}`, `mapfile`, `declare -A`, `[[ -v ]]`, or empty arrays under `set -u`.
- **`bin/vpsctl` does all the work on the server** (bash 5, GNU tools, jq). It's installed as a copy by the `vpsctl` step. It runs as `$VPS_USER`, not root (it re-execs itself as the owner of `/srv/vps` if started as root).
- **Security invariants in vpsctl:**
  - Validate every name and hostname (`NAME_RE` / `HOST_RE`) and every value taken from compose config (ports, container names) before using it in a path or in a Caddyfile.
  - App names never contain dots; that's how they're told apart from hostnames.
  - Every change to a route goes through `install_snippet`, which reloads Caddy and rolls back on failure.
  - In generated routes, `basic_auth` lives inside a catch-all `handle`, after the `/robots.txt` handler, so `robots.txt` never needs the password. Changing the route format needs a `vpsctl sync` on the server, which the setup run does.
  - Mutating commands take `lock` first.
  - A password route must be active before the content it protects becomes reachable.
  - Apps only share a network with Caddy (`vps-<app>`), never with each other.
- **The Caddy catch-all hostname regex** in `lib/caddy.sh` is a security boundary (Host-header path traversal). Keep it in sync with `HOST_RE`.
- `docker` group membership is root-equivalent; don't treat the sudo password as a security boundary.

## Checking changes

There is no test suite. Before committing:

- `bash -n` on changed scripts, and `shellcheck -x setup.sh lib/*.sh bin/*` (must be clean; installed on this machine).
- **Caddyfile changes:** the Caddyfile only exists as a heredoc in `lib/caddy.sh`. Render it to a temp dir (source `lib/common.sh` and `lib/caddy.sh`, override `write_file` to write to the temp dir, call `write_caddyfile`), then check it with the Caddy release binary for Windows from GitHub (`caddy validate --config Caddyfile --adapter caddyfile` and `caddy fmt`). Generated snippets can go in a `sites/` folder next to it.
- **vpsctl logic:** source it without the last lines (`sed '/^# Files in \/srv\/vps belong/,$d' bin/vpsctl`), then call functions with mocked `docker`. On Windows, wrap `jq` to strip `\r`, and set `MSYS_NO_PATHCONV=1` so Git Bash doesn't rewrite `/srv/...` arguments.
- Real verification means running against a fresh Ubuntu VM or a throwaway VPS.
