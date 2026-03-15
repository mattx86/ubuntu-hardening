# ubuntu-hardening

## Project Overview
A standalone, general-purpose Ubuntu 24.04 server hardening script.

**Ubuntu 24.04 only** — not intended for other Ubuntu versions or distributions.

**Caution** — hardening changes have the potential to break a system or disrupt running services. Test on a non-production system before applying to production.

## Single Script
All logic lives in `install_hardening.sh`. There are no other scripts or dependencies.

## What It Does (in order)
0. System update — apt update/upgrade/dist-upgrade, install essential packages, enable unattended-upgrades
0.5. UFW firewall — deny incoming, allow outgoing, allow SSH only
1. Filesystem hardening — disable unused filesystems, harden /tmp /var/tmp /dev/shm
2. Services — disable/remove unnecessary services and packages; disable MOTD news
2.5. AppArmor — install apparmor-utils, enforce all profiles
2.6. Ctrl+Alt+Del + debug-shell.service masked
3. Network hardening — sysctl settings (IP forwarding, ICMP, SYN cookies, ASLR, fs protections, Ubuntu 24.04 kernel params)
4. SSH hardening — strong ciphers, key auth, port 22, RekeyLimit, login/console banners
5. User accounts — password policy (pwquality), account lockout (pam_faillock), login.defs, umask, inactive lockout, sudo hardening
6. File permissions — restrict /etc/passwd, /etc/shadow, etc.; sticky bits on world-writable dirs
7. Audit — auditd with rules for logins, sudo, identity, cron, SSH, privilege escalation, time changes, kernel modules
8. Additional — core dump disable, systemd coredump, log rotation, journald persistent logging, AIDE file integrity
9. Intentionally skipped controls — IPv6 disable, TCP wrappers (superseded by UFW), MAC beyond AppArmor

## Usage
```bash
sudo ./install_hardening.sh
```

## Key Rules
- No `source` from external projects (fully self-contained)
- No CIS references anywhere in the codebase
