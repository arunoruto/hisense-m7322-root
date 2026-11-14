#!/bin/sh
# One initial launch plus FIVE retries per lifetime. No retry reset.
set -eu
PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
name=$1
shift
case "$name" in sshd|tailscaled|test) ;; *) exit 2 ;; esac
run=${RTR_RUN_DIR:-/tmp}
mkdir -p "$run"
umask 077
exec 9>"$run/rtr-$name.lock"
flock -n 9 || exit 0
echo $$ >"$run/rtr-$name.supervisor.pid"
log="$run/rtr-$name.log"
[ ! -f "$log" ] || mv -f "$log" "$log.previous"
exec >>"$log" 2>&1
child=
cleanup() {
    trap - EXIT HUP INT TERM
    if [ -n "$child" ]; then
        kill "$child" 2>/dev/null || :
        wait "$child" 2>/dev/null || :
    fi
    rm -f "$run/rtr-$name.supervisor.pid" "$run/rtr-$name.child.pid"
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
retry=0
while :; do
    echo "Starting $name (retry $retry/5)"
    "$@" 9>&- &
    child=$!
    echo "$child" >"$run/rtr-$name.child.pid"
    rc=0
    wait "$child" || rc=$?
    child=
    rm -f "$run/rtr-$name.child.pid"
    echo "$name exited: $rc"
    [ "$retry" -lt 5 ] || { echo 'Retry limit reached; stopped until manually started or next boot.'; exit 1; }
    retry=$((retry + 1))
    # 2, 4, 6, 8, 10 seconds; boot itself never waits for these retries.
    sleep "$((retry * 2))"
done
