#!/bin/sh
# Run from an extracted access bundle, either over existing SSH or UART.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
case "$0" in */*) cd "${0%/*}" ;; esac
[ "$(id -u)" = 0 ] || { echo 'Root required' >&2; exit 1; }
[ "$(uname -m)" = armv7l ] || { echo 'This installer targets the documented armv7l TV only' >&2; exit 1; }
for cmd in flock setsid iptables mount awk; do command -v "$cmd" >/dev/null; done
for script in rtr-sshd rtr-supervise rtr-firewall rtr-firewall-wrapper rtr-start rtr-tailscaled; do
    sh -n "$script.sh"
done
for name in start-firewall firewall-init-subrule firewall-eulaon firewall-eulaoff; do
    [ -f "/usr/local/scripts/$name.sh" ]
done
[ -x /usr/local/bin/dropbearmulti ] || [ -s dropbearmulti ] || { echo 'Supply dropbearmulti for first install' >&2; exit 1; }
[ -s /usr/local/dropbear/root-home/.ssh/authorized_keys ] || [ -s authorized_keys ] || { echo 'Supply your SSH public key for first install' >&2; exit 1; }
was_ro=0
awk '$2=="/usr/local" && $4 ~ /(^|,)ro(,|$)/ {found=1} END {exit !found}' /proc/mounts && was_ro=1
mount -o remount,rw /usr/local
finish() { sync; [ "$was_ro" = 0 ] || mount -o remount,ro /usr/local; }
trap finish EXIT
umask 077
base=/usr/local/dropbear
mkdir -p "$base/vendor-originals" "$base/root-home/.ssh"
chmod 700 "$base/root-home" "$base/root-home/.ssh"
# Back up originals ONCE. Handle this repository's earlier injected boot hook.
for name in start-firewall firewall-init-subrule firewall-eulaon firewall-eulaoff; do
    dest="$base/vendor-originals/$name.sh"
    if [ ! -f "$dest" ]; then
        source="/usr/local/scripts/$name.sh"
        if grep -q 'vendor-originals' "$source"; then
            echo "Missing original for already wrapped $source; refusing to overwrite backups" >&2; exit 1
        fi
        if [ "$name" = start-firewall ] && grep -q 'rtr-' "$source"; then
            [ -f "$source.bak" ] || { echo 'Missing stock start-firewall.sh.bak' >&2; exit 1; }
            source="$source.bak"
        fi
        cp -p "$source" "$dest"
    fi
done
put() { cp "$1" "$2.rtr-new"; chmod "$3" "$2.rtr-new"; mv -f "$2.rtr-new" "$2"; }
if [ -s dropbearmulti ]; then
    chmod 755 dropbearmulti
    ./dropbearmulti dropbear -V
    put dropbearmulti /usr/local/bin/dropbearmulti 755
fi
for app in dropbear dropbearkey dbclient scp; do ln -sf dropbearmulti "/usr/local/bin/$app"; done
if [ -s authorized_keys ]; then
    # Add keys; never discard an existing working key during an update.
    touch "$base/root-home/.ssh/authorized_keys"
    while IFS= read -r key || [ -n "$key" ]; do
        [ -n "$key" ] || continue
        grep -qxF "$key" "$base/root-home/.ssh/authorized_keys" || printf '%s\n' "$key" >>"$base/root-home/.ssh/authorized_keys"
    done <authorized_keys
fi
chmod 600 "$base/root-home/.ssh/authorized_keys"
if [ ! -f "$base/passwd" ]; then
    awk 'BEGIN{FS=OFS=":"} $1=="root" {$7="/bin/sh"} {print}' /etc/passwd >"$base/passwd"
    chmod 644 "$base/passwd"
fi
if [ ! -s "$base/dropbear_ed25519_host_key" ]; then
    dropbearkey -t ed25519 -f "$base/dropbear_ed25519_host_key"
fi
chmod 600 "$base/dropbear_ed25519_host_key"
for script in rtr-sshd rtr-supervise rtr-firewall rtr-firewall-wrapper rtr-start rtr-tailscaled; do
    put "$script.sh" "/usr/local/scripts/$script.sh" 755
done
put tailscale-tv.sh /usr/local/bin/tailscale-tv 755
put uninstall-on-tv.sh /usr/local/scripts/rtr-uninstall.sh 755
# Install boot hook last, after all files it needs exist.
for name in firewall-init-subrule firewall-eulaon firewall-eulaoff; do
    put rtr-firewall-wrapper.sh "/usr/local/scripts/$name.sh" 755
done
put start-firewall.sh /usr/local/scripts/start-firewall.sh 755
/usr/local/scripts/rtr-firewall.sh
# Do not replace a running SSH listener during installation. Existing sessions
# stay usable; activate the supervisor separately or on the next cold boot.
if grep -q 'init=/bin/sh' /proc/cmdline; then
    echo 'Maintenance boot: access will start on next normal boot.'
elif [ -s /tmp/dropbear.pid ] && kill -0 "$(cat /tmp/dropbear.pid)" 2>/dev/null; then
    echo 'Installed. Existing SSH listener left running; activate supervision with activate-access.py or next boot.'
else
    /usr/local/scripts/rtr-start.sh
fi
echo 'Access files installed; originals and host key preserved.'
