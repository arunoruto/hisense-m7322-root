#!/usr/bin/env python3
"""Move the existing listener under supervision without rebooting the TV."""
import argparse
from tv_common import ssh

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('host')
a = p.parse_args()
# The current authenticated child survives termination of the listener parent.
# Validate /proc before signalling; never trust a stale PID file alone.
ssh(a.host, r'''
set -eu
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ -s /tmp/rtr-sshd.supervisor.pid ] && kill -0 "$(cat /tmp/rtr-sshd.supervisor.pid)" 2>/dev/null; then
    echo 'Supervisor already running'; exit 0
fi
if [ -s /tmp/dropbear.pid ]; then
    pid=$(cat /tmp/dropbear.pid)
    case "$pid" in ''|*[!0-9]*) exit 1 ;; esac
    if kill -0 "$pid" 2>/dev/null; then
        [ /proc/$pid/exe -ef /usr/local/bin/dropbearmulti ] || exit 1
        kill "$pid"
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 5 ]; do sleep 1; i=$((i+1)); done
        if kill -0 "$pid" 2>/dev/null; then echo 'Old listener did not exit' >&2; exit 1; fi
    fi
fi
/usr/local/scripts/rtr-start.sh
sleep 1
cat /tmp/rtr-sshd.log
''')
ssh(a.host, 'id; cat /tmp/rtr-sshd.supervisor.pid; cat /tmp/rtr-sshd.child.pid')
