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
rm /etc/ssh/sshd_config.d/00-vps-setup.conf && systemctl restart ssh   # back to the default SSH config
```

Fix the cause, then run `bash setup.sh ssh` again.

The root password is not locked by the script for exactly this reason: the console fallback needs it.

## Banned by fail2ban

From another IP (phone hotspot) or the web console:

```bash
sudo fail2ban-client status sshd             # list banned IPs
sudo fail2ban-client set sshd unbanip <your-ip>
```

To never ban a static home IP, add `ignoreip = 127.0.0.1/8 ::1 <your-ip>` to the `[DEFAULT]` section of `/etc/fail2ban/jail.local` (or, so that re-runs keep it, in `lib/fail2ban.sh`).

## Line endings: `$'\r': command not found`

The scripts were saved with Windows (CRLF) line endings. Fix them on the server:

```bash
sed -i 's/\r$//' setup.sh setup.conf lib/*.sh bin/*
```

To prevent it, keep `.gitattributes` and set your editor to LF for this repo.

## Apps and sites

**Site shows "Not found" (static).** The folder name must equal the hostname exactly: check `vps <target> ls`. DNS must point at the server: `nslookup foo.example.com`.

**Certificate errors / site doesn't load over HTTPS.** Look at the proxy logs: `vps <target> logs caddy`. Common causes:
- DNS doesn't point at this server yet (or still has the old IP cached).
- Port 80 or 443 is closed in the provider firewall.
- Let's Encrypt rate limits after many failed attempts. Wait an hour.

**502 Bad Gateway (Docker app).** Caddy can't reach the container:
- `vps <target> ls`: is the app running? `vps <target> logs <name>` shows why not.
- `vps.http-port` must be the port the app listens on *inside* the container, and the app must listen on `0.0.0.0`, not `127.0.0.1`.

**Routes are missing or stale**, e.g. after running `docker compose` by hand or restoring files: `vps <target> sync` regenerates all routes and compose overrides from what's in `/srv/docker` and `/srv/static`.

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
