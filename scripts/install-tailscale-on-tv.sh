#!/bin/sh
# Invoked by install-tailscale.py; works without package manager, TLS, or TUN.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
case "$0" in */*) cd "${0%/*}" ;; esac
[ "$(id -u)" = 0 ]
[ "$(uname -m)" = armv7l ]
[ -x /usr/local/scripts/rtr-tailscaled.sh ] || { echo 'Install access scripts first' >&2; exit 1; }
version=$(cat version)
case "$version" in ''|*[!0-9.]*) exit 2 ;; esac
base=/var/local/rtr/tailscale
umask 077
mkdir -p "$base/releases" "$base/state"
chmod 700 /var/local/rtr "$base" "$base/state"
# Avoid simultaneous updates. Same filesystem as persistent releases.
exec 8>"$base/install.lock"
flock -n 8 || { echo 'Another Tailscale update is running' >&2; exit 1; }
chmod 755 tailscale tailscaled
# Old kernel / CPU compatibility is checked BEFORE replacing a working version.
./tailscale version
./tailscaled --version
previous=
if [ -s "$base/current/version" ]; then previous="releases/$(cat "$base/current/version")"; fi
target="releases/$version"
check_api() {
    i=0
    while [ "$i" -lt 15 ]; do
        /usr/local/bin/tailscale-tv status --json >/dev/null 2>&1 && return 0
        sleep 1
        i=$((i+1))
    done
    return 1
}
if [ "$previous" = "$target" ] && [ -x "$base/current/tailscaled" ]; then
    echo "Tailscale $version already installed; starting if stopped."
    setsid /usr/local/scripts/rtr-tailscaled.sh </dev/null >>/tmp/rtr-start.log 2>&1 8>&- &
    check_api || { echo 'Installed daemon is not responding; inspect /tmp/rtr-tailscaled.log' >&2; exit 1; }
    exit 0
fi
need=$(du -k tailscale tailscaled | awk '{sum+=$1} END{print sum+8192}')
avail=$(df -k "$base" | awk 'END{print $4}')
[ "$avail" -ge "$need" ] || { echo "Need $need KiB, have $avail KiB in /var/local; old install untouched" >&2; exit 1; }
# A unique staging directory keeps an interrupted transfer out of current.
stage="$base/releases/.staging-$$"
mkdir "$stage"
trap 'rm -rf "$stage"' EXIT
cp tailscale tailscaled SHA256 version "$stage/"
chmod 755 "$stage/tailscale" "$stage/tailscaled"
[ ! -e "$base/$target" ] || { echo "Release directory already exists: $target; inspect it before retrying" >&2; exit 1; }
mv "$stage" "$base/$target"
stop() {
    if [ -s /tmp/rtr-tailscaled.supervisor.pid ]; then
        pid=$(cat /tmp/rtr-tailscaled.supervisor.pid)
        case "$pid" in ''|*[!0-9]*) return 1 ;; esac
        if kill -0 "$pid" 2>/dev/null; then
            grep -q 'rtr-supervise.sh' "/proc/$pid/cmdline" || return 1
            kill "$pid"
            i=0
            while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 1; i=$((i+1)); done
            if kill -0 "$pid" 2>/dev/null; then echo 'Supervisor did not stop' >&2; return 1; fi
        fi
    fi
}
switch() {
    # BusyBox 1.22 has no mv -T. Switch only while the daemon is stopped.
    ln -sfn "$1" "$base/current"
    sync
}
stop
switch "$target"
setsid /usr/local/scripts/rtr-tailscaled.sh </dev/null >>/tmp/rtr-start.log 2>&1 8>&- &
if check_api; then
    echo "Installed Tailscale $version; state preserved in $base/state"
    exit 0
fi
echo 'New daemon failed its local API check; rolling back the binary selection.' >&2
stop
if [ -n "$previous" ]; then
    switch "$previous"
    setsid /usr/local/scripts/rtr-tailscaled.sh </dev/null >>/tmp/rtr-start.log 2>&1 8>&- &
else
    rm -f "$base/current"
fi
exit 1
