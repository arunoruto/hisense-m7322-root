#!/bin/sh
# Deploy this wrapper under the vendor's original filename. See installer.
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
/usr/local/scripts/rtr-start.sh
rc=0
sh /usr/local/dropbear/vendor-originals/start-firewall.sh "$@" || rc=$?
/usr/local/scripts/rtr-firewall.sh || exit 1
exit "$rc"
