#!/bin/bash
# Right-to-repair v2: fix telnet on the user's own Hisense TV.
#   - mount devpts so telnetd can allocate a PTY (fixes "connection closed by foreign host")
#   - run a plain DAEMONIZED telnetd (no -F, no restart loop) so the listener is stable (fixes the ~3s flap)
# Assumes the serial maintenance shell (init=/bin/sh) is active. Run with:
#   ! bash /Users/mirza/Development/hisense/scripts/enable-telnet-v2.sh
set -u
PY="/private/tmp/claude-501/-Users-mirza-Development-hisense/dee88ad7-9ca2-48b1-aea0-df37e3deda2d/scratchpad/sercmd.py"
L="/Users/mirza/Development/hisense/logs"
run(){ python3 "$PY" "$1" "$2" "${3:-5}"; echo; }

echo "[1/3] ensure /dev + usrfs + devpts, show ptmx"
run 'mount -t devtmpfs dev /dev 2>/dev/null; mount -t ext4 -o rw /dev/mmcblk0p26 /usr/local 2>/dev/null; mkdir -p /dev/pts; mount -t devpts devpts /dev/pts 2>/dev/null; [ -e /dev/ptmx ] || ln -sf /dev/pts/ptmx /dev/ptmx; ls -l /dev/ptmx; mount | grep -i devpts; ls /usr/local/scripts/rtr-telnet.sh && echo MNT_OK' "$L/w1.txt" 5

echo "[2/3] write corrected rtr-telnet.sh (devpts + daemonized telnetd)"
run 'cp -p /usr/local/scripts/rtr-telnet.sh /usr/local/scripts/rtr-telnet.sh.v1bak 2>/dev/null; printf "%s\n" "#!/bin/sh" "# right-to-repair v2: devpts + daemonized root telnet on port 23" "sleep 8" "mkdir -p /dev/pts" "mount -t devpts devpts /dev/pts 2>/dev/null" "[ -e /dev/ptmx ] || ln -sf /dev/pts/ptmx /dev/ptmx" "iptables -D INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null" "iptables -I INPUT 1 -p tcp --dport 23 -j ACCEPT" "iptables -D OUTPUT -p tcp --sport 23 -j ACCEPT 2>/dev/null" "iptables -I OUTPUT 1 -p tcp --sport 23 -j ACCEPT" "/bin/busybox telnetd -l /bin/sh -p 23" > /usr/local/scripts/rtr-telnet.sh; chmod 755 /usr/local/scripts/rtr-telnet.sh; echo ----; cat /usr/local/scripts/rtr-telnet.sh; echo ----; md5sum /usr/local/scripts/rtr-telnet.sh; sync; echo DEPLOY_DONE' "$L/w2.txt" 6

echo "[3/3] sync + unmount + reboot to normal"
run 'sync; umount /usr/local 2>&1; sync; echo REBOOTING; /bin/busybox reboot -f' "$L/w3.txt" 8
echo "=== done. Power the TV on, wait ~15s past the picture, then connect: ==="
echo "    nc 10.42.42.114 23      (mac)   or   telnet 10.42.42.114   (linux busybox)"