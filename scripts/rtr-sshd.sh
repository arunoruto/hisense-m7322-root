#!/bin/sh
# Right-to-repair: start a pubkey-only root SSH server (dropbear) on the TV at
# every boot. Launched (backgrounded) from the top of
# /usr/local/scripts/start-firewall.sh.
#
# IMPORTANT: p26 (/usr/local) is mounted READ-ONLY at normal boot
# (see /etc/fstab: "/dev/mmcblk0p26 /usr/local ext4 ro"). So this script must
# only READ from /usr/local and write nothing there — all logs/pidfile go to
# /tmp (tmpfs). Everything it needs on p26 (binary, host key, authorized_keys,
# passwd overlay) was placed there once from the maintenance shell, where p26
# is mounted rw.
#
# Why each step is needed on this firmware (MStar m7322, Linux 4.9.44):
#   - /etc/passwd gives root the shell /bin/bash, which does NOT exist here, so
#     dropbear rejects every login with "invalid shell". We bind-mount a copy
#     of /etc/passwd (prebuilt on p26) whose root shell is /bin/sh. /etc is ro.
#   - root's home /root is read-only squashfs, so authorized_keys can't live
#     there. We bind-mount a prebuilt writable-looking home from p26 over /root.
#   - the stock firewall DROPs inbound dport 22 and outbound sport 22
#     (#for debug sshd). We insert ACCEPTs ahead of the chain jumps and
#     re-assert them, since firewall-init-subrule.sh runs in the background too.
# Note: this kernel has no PTY, so use `ssh root@tv '<cmd>'` or
# `ssh -T root@tv 'sh'`; a bare interactive login would source /etc/profile.
DBDIR=/usr/local/dropbear
LOG=/tmp/rtr-sshd.log
{
echo "=== rtr-sshd start, uptime $(cut -d' ' -f1 /proc/uptime) ==="

# Overlay /etc/passwd (prebuilt copy on p26 with root shell = /bin/sh).
grep -q " /etc/passwd " /proc/mounts || { mount -o bind "$DBDIR/passwd" /etc/passwd && echo "passwd overlay mounted"; }

# Writable-looking root home so dropbear can read ~/.ssh/authorized_keys.
grep -q " /root " /proc/mounts || { mount -o bind "$DBDIR/root-home" /root && echo "root home mounted"; }

# Launch the server (binding needs neither the firewall nor an IP). setsid so
# it survives the launcher/rcS exiting; pidfile on tmpfs since p26 is ro.
setsid /usr/local/bin/dropbear -r "$DBDIR/dropbear_ed25519_host_key" -p 22 -P /tmp/dropbear.pid
echo "dropbear launched rc=$?, uptime $(cut -d' ' -f1 /proc/uptime)"

# Open ssh past the firewall's debug drops, ahead of the chain jumps, and keep
# re-asserting (~2 min) in case the backgrounded firewall subrule flushes them.
i=0
while [ "$i" -lt 24 ]; do
  iptables -D INPUT  -p tcp --dport 22 -j ACCEPT 2>/dev/null
  iptables -I INPUT  1 -p tcp --dport 22 -j ACCEPT
  iptables -D OUTPUT -p tcp --sport 22 -j ACCEPT 2>/dev/null
  iptables -I OUTPUT 1 -p tcp --sport 22 -j ACCEPT
  i=$((i + 1))
  sleep 5
done
echo "=== rtr-sshd done, uptime $(cut -d' ' -f1 /proc/uptime) ==="
} >>"$LOG" 2>&1
