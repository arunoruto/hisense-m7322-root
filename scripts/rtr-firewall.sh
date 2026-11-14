#!/bin/sh
# Called AFTER each vendor firewall rebuild, including asynchronous subrules.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
exec 9>/tmp/rtr-firewall.lock
flock 9
iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null ||
    iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
iptables -C OUTPUT -p tcp --sport 22 -j ACCEPT 2>/dev/null ||
    iptables -I OUTPUT 1 -p tcp --sport 22 -j ACCEPT
