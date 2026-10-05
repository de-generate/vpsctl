# Troubleshooting

## Locked out of SSH

**If the root session from setup is still open**, fix things there:

```bash
cat /home/vps/.ssh/authorized_keys                 # is your public key in there?
ls -ld /home/vps/.ssh /home/vps/.ssh/authorized_keys   # must be 700 / 600, owned by vps
sshd -T | grep -E 'port|allowusers|passwordauth'   # effective SSH config
journalctl -u ssh -n 50                            # why logins were rejected
fail2ban-client status sshd                        # did you ban yourself?
```

On your machine, `ssh -v vps@<server-ip>` shows which keys are offered and why they are rejected.

**If no session is open anymore**, use your provider's **web/VNC console**. It logs in on the local terminal, so the SSH rules don't apply. Log in as root (or reset the root password from the provider panel), then:

```bash
rm /etc/ssh/sshd_config.d/00-vps-setup.conf      # back to the default SSH config (port 22, ...)
systemctl daemon-reload                         # Ubuntu 22.10+: sshd's listening port comes from
systemctl restart ssh.socket ssh.service        # ssh.socket, which must be regenerated
ufw status                                      # is the SSH port allowed? if not:
ufw allow 22/tcp                                # (or, as a last resort: ufw disable)
```

Also check the **provider firewall**: if you changed `SSH_PORT`, the new port has to be open there too.

Fix the cause, then run `bash setup.sh firewall ssh` again. (The `ssh` step refuses to run if UFW doesn't allow `SSH_PORT`, or if no user in `SSH_ALLOW_USERS` has a valid key.)

The root password is not locked by the script for exactly this reason: the console fallback needs it.

## Banned by fail2ban

From another IP (phone hotspot) or the web console:

```bash
sudo fail2ban-client status sshd             # list banned IPs
sudo fail2ban-client set sshd unbanip <your-ip>
```

To never ban a static home IP, set `FAIL2BAN_IGNOREIP="<your-ip>"` in `setup.conf` and run `sudo bash setup.sh fail2ban`.

If you're banned right after setup without any typos, your SSH agent may be offering too many keys: see `IdentitiesOnly` in [01-initial-setup.md](01-initial-setup.md#6-client-convenience).

## Line endings: `$'\r': command not found`

The scripts were saved with Windows (CRLF) line endings. Fix them on the server:

```bash
sed -i 's/\r$//' setup.sh setup.conf lib/*.sh bin/*
```

To prevent it, keep `.gitattributes` and set your editor to LF for this repo.

## Apps and sites

**Site shows "Not found" (static).** The folder name must equal the hostname exactly: check `vps <target> ls`. DNS must point at the server: `nslookup foo.example.com`.

**TLS/certificate error for a hostname where nothing is deployed.** Expected: the server only has certificates for hostnames that serve something, so the browser stops before a "Not found" page could be shown. Only a wildcard certificate would change that (see [future-improvements.md](future-improvements.md#deploying-apps-vps--vpsctl)).

**Certificate errors / site doesn't load over HTTPS.** Right after deploying a *new* domain this is normal: Docker apps and password-protected sites get their certificate in the background, and until it arrives (usually within a minute) HTTPS connections fail (`curl` reports `000`). If it persists, look at the proxy logs: `vps <target> logs caddy`. Common causes:
- DNS doesn't point at this server yet (or still has the old IP cached).
- Port 80 or 443 is closed in the provider firewall.
- Let's Encrypt rate limits after many failed attempts. Wait an hour.

**502 Bad Gateway (Docker app).** Caddy can't reach the container:
- `vps <target> ls`: is the app running? `vps <target> logs <name>` shows why not.
- `vps.http-port` must be the port the app listens on *inside* the container, and the app must listen on `0.0.0.0`, not `127.0.0.1`.
- `vps <target> ls` shows `NOT ROUTED` (and a warning with the fix) if Caddy and the app don't share the app's network. Caddy's log then says `lookup <container> … server misbehaving`. Two causes:
  - The app's containers were recreated by a plain `docker compose up` without the vpsctl override: run `vps <target> compose <name> up -d` (see [Running docker compose by hand](02-deploying-apps.md#running-docker-compose-by-hand)).
  - Caddy lost its connection to the network (e.g. its container was recreated by hand): run `vps <target> sync`.

**Routes are missing or stale**, e.g. after restoring files: `vps <target> sync` regenerates all routes and compose overrides from what's in `/srv/docker` and `/srv/static`.

**`Cannot access Docker as 'vps'`.** Group membership only applies to new logins. Disconnect and reconnect (or reboot after setup).

**`vpsctl: command not found`.** The `vpsctl` step hasn't run. Run `sudo bash setup.sh docker caddy vpsctl` (it also installs the latest `bin/vpsctl` after you update the repo).

**Deploy failed halfway.** The new files are already in `/srv/docker/<name>/` and the old containers may still run. Fix the problem and deploy again. `vps <target> logs <name>` and the build output show what went wrong.

**Weekly auto-update:** `journalctl -u vps-auto-update` shows the last runs; `systemctl list-timers vps-auto-update` the next one.

## Disk full

```bash
df -h                          # which filesystem is full
sudo ncdu -x /                 # interactive: what uses the space
sudo journalctl --vacuum-size=200M
sudo apt-get autoremove --purge && sudo apt-get clean
docker system df               # images / volumes / build cache
docker image prune -a          # images no container uses (the weekly update does this too)
docker builder prune           # build cache
```

## Did automatic updates run? Will the server reboot?

```bash
cat /var/log/unattended-upgrades/unattended-upgrades.log
ls /var/run/reboot-required && cat /var/run/reboot-required.pkgs
systemctl list-timers apt-daily*
```

## Checking the hardening

```bash
sudo ufw status verbose     # each rule should also appear with "(v6)"
grep IPV6 /etc/default/ufw  # must be IPV6=yes
sudo ss -tulpn              # what listens where (0.0.0.0 / [::] = all IPv4 / IPv6 addresses)
sudo fail2ban-client status sshd
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|allowusers)'
sudo sysctl net.ipv4.tcp_syncookies vm.swappiness
swapon --show
timedatectl
```
