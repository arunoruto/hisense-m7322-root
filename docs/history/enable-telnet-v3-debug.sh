#!/bin/bash
# Right-to-repair v3 (debug step): same as v2's deployed state, but redirect
# rtr-telnet.sh's output to a real logfile on p29 (/var/local) instead of
# /dev/null, so we can see *why* telnetd isn't binding after a normal boot.
# Does NOT change rtr-telnet.sh's logic at all -- only the hook line's redirect.
# Assumes the serial maintenance shell (init=/bin/sh) is active, p26 mounted rw
# at /usr/local. Run with:
#   ! bash /Users/mirza/Development/hisense/scripts/enable-telnet-v3-debug.sh
set -u
PY="/private/tmp/claude-501/-Users-mirza-Development-hisense/ca9b4f9d-3f12-472e-a081-0a2c6b862e9b/scratchpad/sercmd.py"
L="/Users/mirza/Development/hisense/logs"
run(){ python3 "$PY" "$1" "$2" "${3:-5}"; echo; }

echo "[1/2] patch start-firewall.sh hook line: /dev/null -> /var/local/rtr-telnet.log"
run 'cp -p /usr/local/scripts/start-firewall.sh /usr/local/scripts/start-firewall.sh.v2bak 2>/dev/null; sed -i "s#rtr-telnet.sh </dev/null >/dev/null 2>&1 \&#rtr-telnet.sh </dev/null >/var/local/rtr-telnet.log 2>\&1 \&#" /usr/local/scripts/start-firewall.sh; tail -3 /usr/local/scripts/start-firewall.sh; echo ----; md5sum /usr/local/scripts/start-firewall.sh; sync; echo PATCH_DONE' "$L/v3-1-patch.txt" 6

echo "[2/2] sync + unmount + reboot to NORMAL boot (so the hook actually runs and logs)"
run 'sync; umount /usr/local 2>&1; sync; echo REBOOTING_TO_NORMAL; /bin/busybox reboot -f' "$L/v3-2-reboot.txt" 8

echo "=== done. TV is rebooting to NORMAL boot now. Let it fully boot and sit for ~20s"
echo "    (rtr-telnet.sh has a built-in 'sleep 8' before it does anything), then tell"
echo "    Claude so it can catch U-Boot on the *next* power cycle and read the log. ==="
