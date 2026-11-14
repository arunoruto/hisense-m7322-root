#!/bin/bash
# Right-to-repair: enable a persistent root telnet shell on the user's own Hisense TV.
# Drives the ALREADY-OPEN serial maintenance shell (init=/bin/sh, p26 mounted at /usr/local).
# Every device command is shown; run with:  ! bash /Users/mirza/Development/hisense/scripts/enable-telnet.sh
set -u
PY="/private/tmp/claude-501/-Users-mirza-Development-hisense/dee88ad7-9ca2-48b1-aea0-df37e3deda2d/scratchpad/sercmd.py"
L="/Users/mirza/Development/hisense/logs"
run(){ python3 "$PY" "$1" "$2" "${3:-5}"; echo; }

echo "[1/5] Ensure /dev + usrfs(p26) mounted rw"
run 'mount -t devtmpfs dev /dev 2>/dev/null; mount -t ext4 -o rw /dev/mmcblk0p26 /usr/local 2>/dev/null; ls /usr/local/scripts/start-firewall.sh && echo MOUNT_OK' "$L/e1.txt" 5

echo "[2/5] Back up start-firewall.sh on device"
run 'cp -p /usr/local/scripts/start-firewall.sh /usr/local/scripts/start-firewall.sh.bak && echo SFW_BACKED_UP; ls -l /usr/local/scripts/start-firewall.sh*' "$L/e2.txt" 4

echo "[3/5] Create /usr/local/scripts/rtr-telnet.sh (opens 23 in/out, serves root sh, auto-restart)"
run 'printf "%s\n" "#!/bin/sh" "# right-to-repair: open + serve root telnet on port 23" "sleep 8" "iptables -D INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null" "iptables -I INPUT 1 -p tcp --dport 23 -j ACCEPT" "iptables -D OUTPUT -p tcp --sport 23 -j ACCEPT 2>/dev/null" "iptables -I OUTPUT 1 -p tcp --sport 23 -j ACCEPT" "while :; do" "  /bin/busybox telnetd -F -l /bin/sh -p 23" "  sleep 3" "done" > /usr/local/scripts/rtr-telnet.sh; chmod 755 /usr/local/scripts/rtr-telnet.sh; echo ----; cat /usr/local/scripts/rtr-telnet.sh; echo ----; md5sum /usr/local/scripts/rtr-telnet.sh; echo RTR_DONE' "$L/e3.txt" 6

echo "[4/5] Hook it into start-firewall.sh (idempotent) + restore the dead stage1 to stock"
run 'chmod u+w /usr/local/scripts/start-firewall.sh; grep -q rtr-telnet /usr/local/scripts/start-firewall.sh || printf "%s\n" "/usr/local/scripts/rtr-telnet.sh </dev/null >/dev/null 2>&1 &" >> /usr/local/scripts/start-firewall.sh; chmod 555 /usr/local/scripts/start-firewall.sh; cp -p /usr/local/scripts/hisense_stage1.sh.bak /usr/local/scripts/hisense_stage1.sh; echo ---TAIL_OF_FIREWALL---; tail -3 /usr/local/scripts/start-firewall.sh; echo ---STAGE1_RESTORED---; cat /usr/local/scripts/hisense_stage1.sh; sync; echo HOOK_DONE' "$L/e4.txt" 5

echo "[5/5] Sync, unmount, reboot to normal"
run 'sync; umount /usr/local 2>&1; sync; echo REBOOTING; /bin/busybox reboot -f' "$L/e5.txt" 8

echo "=== applied. TV is rebooting to normal mode. ==="
echo "When it is back up, connect with:   nc 10.42.42.114 23"
