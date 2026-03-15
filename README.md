# ubuntu-hardening

General-purpose Ubuntu 24.04 server hardening script.

> **Ubuntu 24.04 only.** This script is written and tested for Ubuntu 24.04 exclusively. It is not intended for other Ubuntu versions or distributions.

> **Caution.** Hardening changes have the potential to break a system or disrupt running services. Always test on a non-production system before applying to production. Use at your own risk.

## Usage

```bash
git clone https://github.com/mattx86/ubuntu-hardening.git
cd ubuntu-hardening
sudo ./install_hardening.sh
```

A reboot is recommended after the script completes.

## What It Does

| Step | Description |
|------|-------------|
| 0 | System update — full apt upgrade, essential packages, unattended-upgrades |
| 0.5 | UFW firewall — deny all incoming except SSH |
| 1 | Filesystem hardening — disable unused filesystems, harden /tmp /var/tmp /dev/shm |
| 2 | Services — disable and remove unnecessary services and packages; disable MOTD news |
| 2.5 | AppArmor — enforce all profiles (Ubuntu 24.04) |
| 2.6 | Ctrl+Alt+Del reboot disabled; debug-shell.service masked |
| 3 | Network hardening — sysctl (IP forwarding, ICMP, SYN cookies, ASLR, fs protections, kernel 6.8 params) |
| 4 | SSH hardening — strong ciphers, port 22, RekeyLimit, login and console banners |
| 5 | User accounts — password policy, account lockout (pam_faillock), umask, inactive lockout, sudo hardening |
| 6 | File permissions — restrict /etc/passwd, /etc/shadow, /etc/gshadow; sticky bits on world-writable dirs |
| 7 | Audit logging — auditd with rules for logins, sudo, identity, cron, SSH, privilege escalation, time changes, kernel modules |
| 8 | Additional — disable core dumps, log rotation, journald persistent logging, AIDE file integrity monitoring |
| 9 | Intentionally skipped — IPv6 disable, TCP wrappers (superseded by UFW), MAC beyond AppArmor |

## Requirements

- Ubuntu 24.04
- Root / sudo access

## License

MIT — see [LICENSE.md](LICENSE.md)
