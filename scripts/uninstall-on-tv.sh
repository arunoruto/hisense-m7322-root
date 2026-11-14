#!/bin/sh
# Restore vendor boot/firewall behavior. Leave running access until reboot.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
base=/usr/local/dropbear/vendor-originals
for name in start-firewall firewall-init-subrule firewall-eulaon firewall-eulaoff; do
    [ -f "$base/$name.sh" ] || { echo "Missing $base/$name.sh" >&2; exit 1; }
done
mount -o remount,rw /usr/local
trap 'sync; mount -o remount,ro /usr/local' EXIT
for name in start-firewall firewall-init-subrule firewall-eulaon firewall-eulaoff; do
    cp -p "$base/$name.sh" "/usr/local/scripts/$name.sh.rtr-restore"
    mv -f "/usr/local/scripts/$name.sh.rtr-restore" "/usr/local/scripts/$name.sh"
done
echo 'Vendor scripts restored. SSH/Tailscale remain running until reboot; no reboot performed.'
