#!/bin/bash
# =============================================================================
# install_hardening.sh
# Ubuntu 24.04 System Hardening
# Version 1.0.1
#
# Copyright (c) 2026 Matt Smith
# MIT License — see LICENSE.md for full license text
# =============================================================================
# Usage:
#   sudo ./install_hardening.sh
# =============================================================================

set -eo pipefail

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Must run as root.${NC}" >&2
    echo "Usage: sudo ./install_hardening.sh" >&2
    exit 1
fi

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $*"
}

echo ""
echo -e "${GREEN}Ubuntu System Hardening${NC}"
echo ""

# =============================================================================
# 0. SYSTEM UPDATE
# =============================================================================
log "0. System update..."

# Wait for apt locks to be released (cloud-init may be using apt)
log "  Waiting for apt locks..."
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    sleep 5
done
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    sleep 5
done

export DEBIAN_FRONTEND=noninteractive

log "  Running apt-get update..."
apt-get update

log "  Running apt-get upgrade..."
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

log "  Running apt-get dist-upgrade..."
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

log "  Running apt-get autoclean..."
apt-get -y autoclean

log "  Running apt-get autoremove..."
apt-get -y autoremove

log "  Installing essential packages..."
apt-get -y install \
    curl \
    wget \
    git \
    htop \
    iotop \
    net-tools \
    jq \
    unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    unattended-upgrades \
    apt-listchanges

log "  Enabling unattended upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

log_success "System update complete"

# =============================================================================
# 0.5. UFW FIREWALL
# =============================================================================
log "0.5. Configuring UFW firewall..."

apt-get -y install ufw

log "  Resetting UFW to defaults..."
ufw --force reset

log "  Setting default policies (deny incoming, allow outgoing)..."
ufw default deny incoming
ufw default allow outgoing

log "  Allowing SSH on port 22..."
ufw allow "22/tcp" comment 'SSH'

log "  Enabling UFW..."
ufw --force enable

log "  UFW Status:"
ufw status verbose

log_success "UFW firewall configured"

# =============================================================================
# 1. FILESYSTEM CONFIGURATION
# =============================================================================
log "1. Filesystem hardening..."

# 1.1 Disable unused filesystems
log "  Disabling unused filesystems..."
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/hardening-filesystems.conf << 'EOF'
# Disable unused filesystems
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true

# Disable unused network protocols
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF

# 1.2 Configure /tmp
log "  Configuring /tmp mount options..."
if ! grep -q "^tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=2G 0 0" >> /etc/fstab
fi

# 1.3 Configure /var/tmp
log "  Configuring /var/tmp..."
if ! grep -q "/var/tmp" /etc/fstab; then
    echo "tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=1G 0 0" >> /etc/fstab
fi

# 1.4 Configure /dev/shm
log "  Configuring /dev/shm..."
if ! grep -q "/dev/shm" /etc/fstab; then
    echo "tmpfs /dev/shm tmpfs defaults,rw,nosuid,nodev,noexec,relatime 0 0" >> /etc/fstab
fi

# =============================================================================
# 2. SERVICES
# =============================================================================
log "2. Removing/disabling unnecessary services..."

# Disable unnecessary services
SERVICES_TO_DISABLE=(
    "avahi-daemon"
    "cups"
    "isc-dhcp-server"
    "slapd"
    "nfs-server"
    "rpcbind"
    "rsync"
    "snmpd"
    "squid"
    "vsftpd"
    "apache2"
    "nginx"
    "dovecot"
    "smbd"
    "nmbd"
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
        log "  Disabling $svc..."
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    fi
done

# Remove unnecessary packages
log "  Removing unnecessary packages..."
PACKAGES_TO_REMOVE=(
    "nis"
    "rsh-client"
    "rsh-server"
    "talk"
    "telnet"
    "ldap-utils"
    "xinetd"
)

for pkg in "${PACKAGES_TO_REMOVE[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        apt-get -y remove "$pkg" >/dev/null 2>&1 || true
    fi
done

log "  Disabling Ubuntu MOTD news..."
chmod -x /etc/update-motd.d/10-help-text 2>/dev/null || true
chmod -x /etc/update-motd.d/50-motd-news 2>/dev/null || true

# =============================================================================
# 2.6. DISABLE CTRL+ALT+DEL
# =============================================================================
log "2.6. Disabling Ctrl+Alt+Del reboot..."

systemctl mask ctrl-alt-del.target >/dev/null 2>&1 || true
systemctl mask debug-shell.service >/dev/null 2>&1 || true
systemctl daemon-reload >/dev/null 2>&1 || true

log_success "Ctrl+Alt+Del reboot disabled"

# =============================================================================
# 2.5. APPARMOR
# =============================================================================
log "2.5. AppArmor enforcement..."

apt-get -y install apparmor-utils >/dev/null 2>&1 || true
aa-enforce /etc/apparmor.d/* 2>/dev/null || true

log_success "AppArmor profiles set to enforce mode"

# =============================================================================
# 3. NETWORK CONFIGURATION
# =============================================================================
log "3. Network hardening (sysctl)..."

mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# Network Hardening

# 3.1 Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 3.2 Packet redirect sending
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# 3.3 Source routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 3.4 ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 3.5 Secure ICMP redirects
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 3.6 Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 3.7 Ignore broadcast ICMP requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 3.8 Ignore bogus ICMP responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 3.9 Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 3.10 Enable TCP SYN cookies
net.ipv4.tcp_syncookies = 1

# 3.11 IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Additional hardening
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
fs.suid_dumpable = 0
net.ipv4.tcp_rfc1337 = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
kernel.sysrq = 0

# Ubuntu 24.04 / kernel 6.8 hardening
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.kexec_load_disabled = 1
kernel.perf_event_paranoid = 3
vm.unprivileged_userfaultfd = 0
dev.tty.ldisc_autoload = 0
kernel.io_uring_disabled = 1

EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/99-hardening.conf || true

# =============================================================================
# 4. SSH HARDENING
# =============================================================================
log "4. SSH hardening..."

if [ -f /etc/ssh/sshd_config ]; then
# Backup original config
[ -f /etc/ssh/sshd_config.bak ] || cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-hardening.conf << EOF
# SSH Hardening

# Protocol and port
Port 22

# Logging
LogLevel VERBOSE

# Authentication
LoginGraceTime 60
PermitRootLogin yes
PasswordAuthentication yes
StrictModes yes
MaxAuthTries 4
MaxSessions 10

# Disable unused auth methods
HostbasedAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no

# PAM
UsePAM yes

# Disable tunneling and forwarding
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no

# Banner
Banner /etc/issue.net

# Environment
PermitUserEnvironment no

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 3
RekeyLimit 512M 1h

# Ciphers and MACs (strong only)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256
EOF

# Create warning banners (SSH and local console)
cat > /etc/issue.net << 'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY
This system is for authorized use only. Unauthorized access is prohibited.
All activities may be monitored and recorded.
***************************************************************************
EOF
cat > /etc/issue << 'EOF'
***************************************************************************
                            AUTHORIZED ACCESS ONLY
This system is for authorized use only. Unauthorized access is prohibited.
All activities may be monitored and recorded.
***************************************************************************
EOF

# Validate config before restarting to avoid lockout
log "  Testing SSH config..."
if sshd -t >/dev/null 2>&1; then
    log "  Restarting SSH..."
    systemctl restart sshd >/dev/null 2>&1 || systemctl restart ssh >/dev/null 2>&1 || true
else
    log "  WARNING: sshd config test failed — skipping restart, review /etc/ssh/sshd_config.d/99-hardening.conf"
fi

fi  # end: if [ -f /etc/ssh/sshd_config ]

# =============================================================================
# 5. USER ACCOUNTS AND ENVIRONMENT
# =============================================================================
log "5. User account hardening..."

# 5.1 Password policies
log "  Configuring password policies..."

# Install libpam-pwquality
apt-get -y install libpam-pwquality >/dev/null 2>&1 || true

# Configure password quality
cat > /etc/security/pwquality.conf << 'EOF'
# Password quality requirements
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 3
maxclassrepeat = 4
gecoscheck = 1
EOF

# 5.2 Configure account lockout (pam_faillock — Ubuntu 24.04)
log "  Configuring account lockout (pam_faillock)..."
cat > /etc/security/faillock.conf << 'EOF'
# Lock account after 5 failed attempts within 15 minutes; unlock after 15 minutes
deny = 5
fail_interval = 900
unlock_time = 900
EOF

# 5.3 Configure login.defs
log "  Configuring login.defs..."
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   365/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

# 5.4 Set default umask
log "  Setting default umask..."
echo "umask 027" > /etc/profile.d/hardening-umask.sh
chmod +x /etc/profile.d/hardening-umask.sh

# 5.5 Lock inactive accounts
log "  Configuring inactive account lockout..."
useradd -D -f 30

# 5.6 Sudo hardening
log "  Hardening sudo configuration..."
cat > /etc/sudoers.d/hardening << 'EOF'
# Require a PTY for sudo (prevents cron/script abuse)
Defaults use_pty
# Log all sudo commands
Defaults logfile=/var/log/sudo.log
# Never echo password
Defaults !visiblepw
# Reset environment
Defaults env_reset
# Secure PATH
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
chmod 440 /etc/sudoers.d/hardening

# =============================================================================
# 6. FILE PERMISSIONS
# =============================================================================
log "6. File permission hardening..."

# Critical files
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 600 /etc/shadow
chmod 600 /etc/gshadow
if [ -f /etc/ssh/sshd_config ]; then chmod 600 /etc/ssh/sshd_config; fi

# Remove world-writable files from /etc
find /etc -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null || true

# Set sticky bit on world-writable directories
find / -xdev -type d -perm -0002 ! -perm -1000 -exec chmod +t {} \; 2>/dev/null || true

# =============================================================================
# 7. AUDIT CONFIGURATION
# =============================================================================
log "7. Configuring audit daemon..."

apt-get -y install auditd audispd-plugins
mkdir -p /etc/audit/rules.d

cat > /etc/audit/rules.d/hardening.rules << 'EOF'
# Audit Rules

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Monitor login/logout events
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Monitor session initiation
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# Monitor sudo usage
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d -p wa -k scope

# Monitor changes to system files
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor network configuration changes
-w /etc/hosts -p wa -k network
-w /etc/network -p wa -k network

# Monitor cron
-w /etc/crontab -p wa -k cron
-w /etc/cron.d -p wa -k cron
-w /etc/cron.daily -p wa -k cron
-w /etc/cron.hourly -p wa -k cron
-w /etc/cron.monthly -p wa -k cron
-w /etc/cron.weekly -p wa -k cron

# Monitor SSH config
-w /etc/ssh/sshd_config -p wa -k sshd

# Monitor privilege escalation
-a always,exit -F arch=b64 -S setuid -F auid>=1000 -F auid!=-1 -k privilege_escalation
-a always,exit -F arch=b64 -S setgid -F auid>=1000 -F auid!=-1 -k privilege_escalation

# Monitor time/date changes
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-w /etc/localtime -p wa -k time_change

# Monitor kernel module loading/unloading
-a always,exit -F arch=b64 -S init_module -S delete_module -S finit_module -k modules

# Make the configuration immutable
-e 2
EOF

# Enable and start auditd
systemctl enable auditd >/dev/null 2>&1 || true
systemctl restart auditd >/dev/null 2>&1 || true

# =============================================================================
# 8. ADDITIONAL HARDENING
# =============================================================================
log "8. Additional hardening..."

# 8.1 Disable core dumps
log "  Disabling core dumps..."
grep -q "^\* hard core 0" /etc/security/limits.conf || echo "* hard core 0" >> /etc/security/limits.conf

# 8.2 Configure systemd coredump
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/disable.conf << 'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

# 8.3 Disable USB storage (optional - uncomment to disable USB storage)
# echo "install usb-storage /bin/true" >> /etc/modprobe.d/hardening-filesystems.conf

# 8.4 Configure log rotation
mkdir -p /etc/logrotate.d
cat > /etc/logrotate.d/syslog << 'EOF'
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
{
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

# 8.5 Configure systemd-journald
log "  Configuring systemd-journald..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/hardening.conf << 'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
SystemKeepFree=100M
ForwardToSyslog=yes
EOF
systemctl restart systemd-journald >/dev/null 2>&1 || true

# 8.6 AIDE file integrity monitoring
log "8.6. Installing AIDE file integrity monitoring..."
apt-get -y install aide aide-common >/dev/null 2>&1 || true
log "  Initializing AIDE database (this may take a few minutes)..."
aideinit 2>/dev/null || true
if [ -f /var/lib/aide/aide.db.new ]; then
    mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
fi
cat > /etc/cron.d/aide << 'EOF'
# Run AIDE integrity check daily at 5am
0 5 * * * root /usr/bin/aide --check 2>&1 | /usr/bin/logger -t aide-check
EOF
chmod 644 /etc/cron.d/aide
log_success "AIDE installed and database initialized"

# =============================================================================
# 9. INTENTIONALLY SKIPPED CONTROLS
# =============================================================================
log "9. Noting intentionally skipped controls..."
log "  The following controls are intentionally omitted:"
log "    - IPv6 disable: Many environments require IPv6; disable manually if not needed"
log "    - TCP wrappers (/etc/hosts.deny): Superseded by UFW on Ubuntu 24.04"
log "    - Mandatory access control beyond AppArmor: Application-dependent"

log_success "System hardening applied"
log "Note: Some settings require reboot to take full effect"

echo ""
echo -e "${GREEN}Hardening complete.${NC}"
echo "A reboot is recommended to ensure all settings take full effect."
echo ""
