#!/bin/sh
# Installed under each vendor firewall script's ORIGINAL name.
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
name=${0##*/}
case "$name" in
    start-firewall.sh) /usr/local/scripts/rtr-start.sh ;;
    firewall-init-subrule.sh|firewall-eulaon.sh|firewall-eulaoff.sh) ;;
    *) echo "Unexpected firewall wrapper name: $name" >&2; exit 2 ;;
esac
rc=0
sh "/usr/local/dropbear/vendor-originals/$name" "$@" || rc=$?
/usr/local/scripts/rtr-firewall.sh || { logger -t rtr 'Failed to restore SSH firewall rules'; exit 1; }
exit "$rc"
