#!/bin/sh
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
base=/var/local/rtr/tailscale
umask 077
mkdir -p "$base/state" /tmp/tailscale
# No TUN driver here. Incoming tailnet TCP is proxied to localhost:22.
# Keep Dropbear authentication; Tailscale SSH is not enabled.
exec /usr/local/scripts/rtr-supervise.sh tailscaled \
    "$base/current/tailscaled" --tun=userspace-networking \
    --statedir="$base/state" --state="$base/state/tailscaled.state" \
    --socket=/tmp/tailscale/tailscaled.sock
