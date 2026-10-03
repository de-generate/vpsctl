# Initial setup

How to turn a fresh Ubuntu Server VPS into a basic, secure server with `setup.sh`.

## 1. Before you start

**An SSH key on your machine.** If you don't have one yet (Windows PowerShell, macOS and Linux all work the same way):

```bash
ssh-keygen -t ed25519 -C "you@your-machine"
cat ~/.ssh/id_ed25519.pub     # this is the public key to put in setup.conf
```

Most providers let you add this key when you create the VPS. The script copies keys from `/root/.ssh/authorized_keys` to the new user automatically.

**Provider firewall.** If your provider has a firewall in front of the VPS, allow:

| Port | Protocol | Purpose |
|------|----------|---------|
| 22 (or your `SSH_PORT`) | TCP | SSH |
| 80   | TCP | HTTP (also needed for Let's Encrypt certificates) |
| 443  | TCP | HTTPS |
| 443  | UDP | HTTP/3 |

Use the same rules as UFW on the server. The provider firewall matters because Docker can bypass UFW (see [future-improvements.md](future-improvements.md#docker-and-ufw)). Some provider panels keep separate IPv4 and IPv6 rule lists, or only filter IPv4. Make sure IPv6 is covered too.

**A snapshot (optional).** If your provider has snapshots, taking one of the fresh VPS lets you start over in seconds.

## 2. Copy the repo to the server

From the folder that contains `vps-setup`:

```bash
scp -r vps-setup root@<server-ip>:/root/
```

If the repo is pushed to a git host, run `git clone <url>` on the server instead.

> The scripts must have LF line endings. `.gitattributes` handles this for git checkouts, but some Windows editors save files with CRLF anyway. See [troubleshooting.md](troubleshooting.md#line-endings-r-command-not-found).

## 3. Configure

```bash
ssh root@<server-ip>
cd /root/vps-setup
cp setup.conf.example setup.conf
nano setup.conf
```

Each option is documented in [`setup.conf.example`](../setup.conf.example). Usually you only set `SSH_PUBKEY` (unless the provider already installed your key), `VPS_HOSTNAME`, `VPS_TIMEZONE` and `ACME_EMAIL` (for Let's Encrypt expiry notices).

## 4. Run

```bash
bash setup.sh
```

The script asks once for a password for the `vps` user. SSH login is key-only, so this password is only used for `sudo`. Use a strong one and store it in your password manager.

Steps run in this order: `packages → system → user → upgrades → firewall → fail2ban → docker → caddy → vpsctl → ssh`. SSH is hardened last, and only if the new user has a valid key.

## 5. Check the login (do not skip)

**Keep the root session open.** In a new terminal:

```bash
ssh vps@<server-ip>          # add -p <port> if you changed SSH_PORT
sudo -v                      # asks for the password, should succeed
```

If this fails, fix it from the root session that is still open (see [troubleshooting.md](troubleshooting.md)). Once it works:

```bash
sudo reboot                  # recommended if the script reported a required reboot
```

These should now be **refused**: `ssh root@<server-ip>`, and `ssh -o PubkeyAuthentication=no vps@<server-ip>` (password login).

If the VPS has an IPv6 address, check it from outside too (from a machine with IPv6): `nmap -6 -Pn <server-ipv6>` should show only 22, 80 and 443.

## IPv6

IPv6 is deliberately **not** disabled. The common advice to turn it off comes from setups where the firewall only filtered IPv4, which left IPv6 wide open. Here, every UFW rule applies to both (`ufw status` lists each rule a second time with `(v6)`), and the firewall step makes sure `IPV6=yes` is set in `/etc/default/ufw`. fail2ban and the sysctl hardening cover IPv6 as well. Disabling it adds no security, but it makes the server unreachable from IPv6-only networks.

## 6. Client convenience

Add a host entry to `~/.ssh/config` on your machine:

```
Host vps
    HostName <server-ip or domain>
    User vps
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

Now `ssh vps` is enough. The same name works for the deploy client: `vps vps ls` (see [02-deploying-apps.md](02-deploying-apps.md)).

## What exactly gets changed

| File | Step |
|------|------|
| `/etc/hostname`, `/etc/hosts`, `/etc/cloud/cloud.cfg.d/99-vps-setup-hostname.cfg` | system |
| `/swapfile`, `/etc/fstab` | system |
| `/etc/sysctl.d/99-vps-setup.conf` | system |
| `/home/vps/.ssh/authorized_keys` | user |
| `/etc/apt/apt.conf.d/20auto-upgrades`, `52unattended-upgrades-vps-setup` | upgrades |
| UFW rules (`ufw status verbose`) | firewall |
| `/etc/fail2ban/jail.local` | fail2ban |
| `/etc/apt/sources.list.d/docker.sources`, `/etc/docker/daemon.json`, `52unattended-upgrades-docker` | docker |
| `/srv/static`, `/srv/docker`, `/srv/data`, `/srv/vps` (incl. `/srv/vps/caddy/` with the Caddy container) | caddy |
| `/usr/local/bin/vpsctl`, `vps-auto-update.service` / `.timer` | vpsctl |
| `/etc/ssh/sshd_config.d/00-vps-setup.conf` | ssh |

Files that start with `# Managed by vps-setup` are rewritten on every run. Put your own changes in separate files, or change the script.

## Re-running

Every step is idempotent. To apply a config change, run only the steps it affects:

```bash
sudo bash setup.sh ssh firewall fail2ban   # e.g. after changing SSH_PORT
```

After the first run root can no longer log in over SSH, so later runs use `sudo` as `vps`.
