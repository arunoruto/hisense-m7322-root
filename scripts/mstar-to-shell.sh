#!/usr/bin/env bash
# Drop the TV from U-Boot (<< MStar >>#) into a root Linux maintenance shell,
# fully automated over serial.
#
# Usage:
#   1. Power the TV OFF.
#   2. Run:  ! bash /Users/mirza/Development/hisense/scripts/mstar-to-shell.sh
#   3. When it says so, power the TV ON. The script spams CR to catch U-Boot,
#      sets init=/bin/sh bootargs (session-only, never saveenv'd), boots, and
#      mounts devtmpfs/proc/usrfs. You end at a root `#` shell.
#
# Reversible: bootargs are only setenv'd (not saved), so any reboot/power-cycle
# returns the TV to stock boot automatically.
exec python3 - "$@" <<'PY'
import sys, time, serial

PORT = "/dev/cu.usbserial-A10N456L"
BAUD = 115200
# Known-good maintenance bootargs: init=/bin/sh, with `quiet` and the bare
# BOOTLOGO_IN_MBOOT token removed (a bare token becomes argv to /bin/sh and
# kills PID 1 -> kernel panic). Derived from logs/13-bootargs-fixed.txt.
BOOTARGS = ("cusdata_projectid=1 vmalloc=700M console=ttyS0,115200 "
            "rootfstype=squashfs rw rootwait init=/bin/sh "
            "CORE_DUMP_PATH=/var/crash/core_dump.%e.%p.gz MIRROR=0 "
            "ENV_VAR_OFFSET=0x0 ENV_VAR_SIZE=0x10000 ENV=EMMC FSTR=1 "
            "SECURITY=ON only_onerc_set=0 bootflag=0 root=/dev/mmcblk0p9 "
            "LX_MEM=0x5100000 LX_MEM2=0x4CF00000,0x33000000 EMAC_MEM=0x100000 "
            "PM51_ADDR=0x20010000 PM51_LEN=0x10000 tee_mode=optee SAR5=ON "
            "RTPM_INFO=1,0x20010000 otaflag=85")

def open_port():
    return serial.Serial(PORT, BAUD, bytesize=8, parity='N', stopbits=1,
                         timeout=0.05, rtscts=False, xonxoff=False, dsrdtr=False)

def drain(ser, secs):
    buf = bytearray(); end = time.time() + secs
    while time.time() < end:
        c = ser.read(4096)
        if c: buf += c
    return buf.decode("latin-1")

def send(ser, line, secs=3):
    ser.reset_input_buffer()
    ser.write(line.encode() + b"\r"); ser.flush()
    return drain(ser, secs)

try:
    ser = open_port()
except Exception as e:
    print(f"ERROR: cannot open {PORT}: {e}")
    print("Is a `screen`/`cat` still holding the port? Quit it first (screen: Ctrl-A k).")
    sys.exit(1)

print(">>> Power the TV ON now. Catching U-Boot (spamming CR, up to 40s)...")
end = time.time() + 40
caught = False
while time.time() < end:
    ser.write(b"\r")
    out = ser.read(4096).decode("latin-1")
    if "MStar" in out:
        caught = True
        break
    time.sleep(0.02)
# settle, confirm prompt
time.sleep(0.3)
chk = send(ser, "", 2)
if not caught and "MStar" not in chk:
    print("ERROR: never saw the << MStar >># prompt. Power-cycle and retry.")
    print("Last bytes:", repr(chk[-120:]))
    sys.exit(2)
print(">>> U-Boot caught.")

print(">>> Setting maintenance bootargs (session-only, not saved)...")
send(ser, "setenv bootargs " + BOOTARGS, 2)
ver = send(ser, "printenv bootargs", 2)
if "init=/bin/sh" not in ver:
    print("ERROR: bootargs did not take (no init=/bin/sh). Aborting before boot.")
    print(repr(ver[-200:]))
    sys.exit(3)
print(">>> bootargs OK (init=/bin/sh).")

print(">>> Booting kernel into /bin/sh (up to 60s)...")
ser.reset_input_buffer()
ser.write(b"boot\r"); ser.flush()
boot = ""; end = time.time() + 60; shell = False
while time.time() < end:
    boot += ser.read(4096).decode("latin-1")
    if "can't access tty" in boot or "Initprocess" in boot:
        shell = True
        break
if not shell:
    print("WARNING: didn't see the init-shell banner. It may still be at `#`.")
time.sleep(1.0)

print(">>> Mounting devtmpfs / proc / usrfs(p26, rw)...")
send(ser, "mount -t devtmpfs dev /dev", 2)
send(ser, "mount -t proc proc /proc", 2)
m = send(ser, "mount -t ext4 -o rw /dev/mmcblk0p26 /usr/local; echo MNT_RC=$?", 3)
probe = send(ser, "echo READY=$(id -u)", 2)
ser.close()

ok = "READY=0" in probe
print("=" * 60)
if ok:
    print("SUCCESS: root maintenance shell is live (uid 0), p26 mounted rw.")
    print("Drive it with:  python3 <scratchpad>/sercmd.py \"<cmd>\" out.txt <secs>")
else:
    print("Shell reached but couldn't confirm uid 0 / mounts. Check manually.")
    print("mount line:", repr(m[-160:]))
    print("probe:", repr(probe[-160:]))
print("=" * 60)
PY
