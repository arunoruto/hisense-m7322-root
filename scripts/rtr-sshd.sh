#!/bin/sh
# /usr/local is read-only at runtime; all transient state lives in /tmp.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
DBDIR=/usr/local/dropbear
for file in "$DBDIR/passwd" "$DBDIR/dropbear_ed25519_host_key" "$DBDIR/root-home/.ssh/authorized_keys"; do
    [ -s "$file" ] || { echo "Missing $file" >&2; exit 1; }
done
grep -q ' /etc/passwd ' /proc/mounts || mount -o bind "$DBDIR/passwd" /etc/passwd
grep -q ' /root ' /proc/mounts || mount -o bind "$DBDIR/root-home" /root
exec /usr/local/scripts/rtr-supervise.sh sshd /usr/local/bin/dropbear \
    -F -E -r "$DBDIR/dropbear_ed25519_host_key" -p 22 -P /tmp/dropbear.pid
