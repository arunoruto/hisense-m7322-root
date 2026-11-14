#!/bin/sh
exec /var/local/rtr/tailscale/current/tailscale \
    --socket=/tmp/tailscale/tailscaled.sock "$@"
