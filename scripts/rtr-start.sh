#!/bin/sh
# Detach supervision; never wait in the boot path.
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
setsid /usr/local/scripts/rtr-sshd.sh </dev/null >>/tmp/rtr-start.log 2>&1 &
if [ -x /var/local/rtr/tailscale/current/tailscaled ]; then
    setsid /usr/local/scripts/rtr-tailscaled.sh </dev/null >>/tmp/rtr-start.log 2>&1 &
fi
