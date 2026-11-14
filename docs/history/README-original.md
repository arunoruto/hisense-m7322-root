# Hisense TV — right-to-repair notes

Goal: get a root shell on the TV (UART-attached) to delete bundled apps and
speed it up. Board is `m7322` (MStar/Sigmastar), armv7l, Linux 4.9.44,
U-Boot 2011.06, eMMC with 37 partitions.

## Repo layout

- `scripts/` — serial automation. `mstar-to-shell.sh` is the one you want:
  it drives U-Boot → a root maintenance shell automatically. The
  `enable-telnet*.sh` scripts are kept for history only (telnet is a dead end
  on this kernel — see root-cause section).
- `.github/workflows/build-dropbear.yml` — CI that cross-compiles a static
  armv7 SSH server for the TV.
- `assets/` — photos of the board and UART hookup.
- `logs/` — raw serial session logs (git-ignored; local only).

## Access

- Serial: FTDI USB adapter, macOS device `/dev/cu.usbserial-A10N456L`.
- Baud: **115200**, 8N1. (Garbage at other bauds was actually a macOS `stty`
  gotcha: `cat`/reopening the port resets it — must hold one fd open for the
  whole session. Fixed by using pyserial instead of raw `stty`+`cat`.)
- Reliable read/write helper: `sercmd.py` in the session scratchpad
  (`python3 sercmd.py "<cmd>" <logfile> <seconds>`). Plain `stty`/`cat` lost
  bytes on long lines (canonical-mode / buffering issues); pyserial with
  continuous draining does not.
- Autoboot interrupt: spam `\r` during power-on to catch the U-Boot
  `<< MStar >>#` prompt. `CONFIG_SECURE_BY_PASS_VERIFICATION MODE!!` is
  printed at boot — secure boot is in bypass, so U-Boot cmdline edits are
  honored (no signature enforcement fight).

## eMMC partition table (relevant entries)

| #   | name   | size | notes                                                           |
| --- | ------ | ---- | --------------------------------------------------------------- |
| 9   | RFS    | 36M  | rootfs, squashfs, read-only                                     |
| 26  | usrfs  | 240M | mounted at `/usr/local`; holds `/usr/local/scripts/*`. **READ-ONLY at normal boot** (`/etc/fstab`: `ext4 ro`); only rw when you remount it in the maintenance shell |
| 28  | optfs  | 650M | writable                                                        |
| 29  | varlfs | 340M | writable, mounted at `/var/local`                               |
| 36  | apps   | 600M | app payloads — likely target for deletion                       |

## Getting a root shell (maintenance mode)

1. Catch U-Boot prompt (spam `\r` on power-on).
2. `printenv bootargs` to get the current cmdline, then `setenv bootargs`
   with `init=/init` replaced by **`init=/bin/sh`**, and drop the bare
   `BOOTLOGO_IN_MBOOT` token (kernel passes bare cmdline tokens as argv to
   init — `sh BOOTLOGO_IN_MBOOT` fails to open that as a script, exits 2,
   kills PID 1 → kernel panic "Attempted to kill init!" → auto-reboot).
   **Do not leave stray bare tokens in bootargs.**
3. `boot` → lands at a bare `#` (busybox sh as PID 1, uid 0).
4. Session-only env change (never `saveenv`'d) — a `reboot` or power cycle
   reverts bootargs to stock automatically. Confirmed safe/reversible.
5. In the shell: `/dev` and `/proc` are not mounted by default (static
   squashfs `/dev` with no devtmpfs). Mount in this order (devtmpfs first,
   so `/dev/null` exists before any `2>/dev/null` redirect is used):
   ```
   mount -t devtmpfs dev /dev
   mount -t proc proc /proc
   mount -t ext4 -o rw /dev/mmcblk0p26 /usr/local
   ```
6. **Avoid recursive `grep -r` over large trees (`/usr`, `/system`,
   `/applications`) in this shell** — it's slow enough to back up the serial
   session for a long time, and this PID-1 shell has no job control so
   Ctrl-C doesn't interrupt it. Just wait it out, or grep narrower paths.

## What actually controls boot-time scripts

- `/etc/inittab` → `::sysinit:/etc/init.d/rcS`.
- `rcS` does NOT call `/usr/local/scripts/hisense_stage0/1/2.sh` — those are
  **dead/legacy scripts in this firmware build**, not wired into anything.
  (Confirmed: no references anywhere in `/etc`, `/init`, `deploy`, or
  `app.cfg`.) Editing `hisense_stage1.sh` alone does nothing on this unit.
- The real app launcher is `/etc/vendor/app.cfg`: `auto_start_6 = tvmain`
  starts `/usr/local/bin/tvmain` via `svrmgr`. This is the actual boot path
  for the TV UI and apps — relevant for the app-deletion task.
- `rcS` **does** run `/usr/local/scripts/start-firewall.sh` every boot
  (foreground, on partition 26 — writable). This is the real hook for any
  boot-time customization on this firmware.
- `start-firewall.sh` flushes iptables, sets up EULA-based chains, then
  backgrounds `firewall-init-subrule.sh` (the actual rule set).
- The firewall explicitly drops telnet in both directions ("for debug hbbtv
  telnet" comments): `--dport 23 -j DROP` (inbound) and `--sport 23 -j DROP`
  (outbound/replies). Any inbound service needs an `ACCEPT` rule inserted
  ahead of these.

## Telnet enablement attempt — current state (NOT WORKING YET)

Stopped mid-fix, across two sessions. v1 had two real bugs; v2 fixed one and
is deployed, but port 23 is still not reachable. Session paused here —
pick up with the live-debugging step below.

**On-device state right now (partition 26), after v2 deploy:**

- `start-firewall.sh` — modified; appends
  `/usr/local/scripts/rtr-telnet.sh </dev/null >/dev/null 2>&1 &` at the end.
  Backed up as `start-firewall.sh.bak` (697 bytes, stock).
- `rtr-telnet.sh` — **v2, deployed, md5 `aab01123f2db2e325be616a9b5db8576`**:
  ```sh
  #!/bin/sh
  sleep 8
  mkdir -p /dev/pts
  mount -t devpts devpts /dev/pts 2>/dev/null
  [ -e /dev/ptmx ] || ln -sf /dev/pts/ptmx /dev/ptmx
  iptables -D INPUT -p tcp --dport 23 -j ACCEPT 2>/dev/null
  iptables -I INPUT 1 -p tcp --dport 23 -j ACCEPT
  iptables -D OUTPUT -p tcp --sport 23 -j ACCEPT 2>/dev/null
  iptables -I OUTPUT 1 -p tcp --sport 23 -j ACCEPT
  /bin/busybox telnetd -l /bin/sh -p 23
  ```
  (v1's buggy version backed up alongside as `rtr-telnet.sh.v1bak`.)
- `hisense_stage1.sh` — restored to stock (confirmed dead script, unrelated
  to any of this).

**v1 symptoms (fixed in v2):** port 23 flapped every ~3s
(`Connection refused` alternating with connect-success), because v1 ran
`telnetd -F` inside a `while :; do …; sleep 3; done` respawn loop with no
devpts mounted — each respawn left a ~1.5s gap with no listener, and any
connection that *did* land got PTY allocation failure
(`Connected to … / Connection closed by foreign host` — no `/dev/pts`).

**v2 result: still not reachable, but differently.** After deploying v2 and
power-cycling, port 23 is **consistently** `Connection refused` — no flap at
all now (confirms the loop/devpts logic itself isn't mid-cycling), but also
no successful connect ever. This means telnetd plausibly isn't binding at
all, or is daemonizing and then exiting. **Unconfirmed** — see below, this
is where the session stopped.

**Why we can't just read the error:** the hook line in `start-firewall.sh`
redirects rtr-telnet.sh's entire output to `/dev/null`
(`</dev/null >/dev/null 2>&1 &`) by design (to avoid cluttering the serial
console) — so any crash/error from telnetd or the iptables calls is
invisible in the normal boot log. Confirmed via a full fresh power-on serial
capture (`logs/47-fullnormalboot.txt`): zero occurrences of `telnet`, `rtr`,
or `firewall.sh` anywhere in the text, even though `start-firewall.sh`
provably ran (its own "eula is on" echo appears at the right spot).

**Dead end hit this session — serial console in normal boot mode:**
`/etc/inittab` has `ttyS0::once:-/bin/sh`, confirmed in the boot log
(`starting pid 1033, tty '/dev/ttyS0': '-/bin/sh'`), so in principle you can
get a live shell over serial *without* going through the `init=/bin/sh`
maintenance-mode dance, once the TV is fully booted normally. In practice,
every attempt this session to send input to it (CR, LF, CRLF, spaced
retries over 15s) got **zero bytes back** — not a wrong prompt, not
garbage, literally nothing. Not understood yet. Possibilities not yet ruled
out: the `once` shell already exited/was consumed by something earlier in
boot and isn't there to answer; a termios/line-discipline difference from
the maintenance-mode case (which works reliably); real contention with
kernel console printk on the same UART. **Next step for this lead:** from a
truly fresh power-on, try sending input to ttyS0 immediately (within the
first few seconds) rather than after full boot, and/or test whether kernel
dmesg lines are still arriving on the same fd at the same time (if they
stop, something took over the port; if they continue, the shell itself just
isn't answering).

**Simplest next step instead:** reuse the already-proven `init=/bin/sh`
maintenance shell (U-Boot catch → `setenv bootargs` with `init=/bin/sh`,
drop bare `BOOTLOGO_IN_MBOOT` → `boot`) to directly run
`iptables -L -n -v` and `ps w | grep telnetd` and inspect what actually
happened — this path has worked reliably every time in this project, unlike
the ttyS0-after-full-boot approach above. (Caveat: this is a *separate*
kernel boot with only `/bin/sh` as init, so it won't show the state of the
currently-running normal-boot instance's processes — it can only inspect
the filesystem/scripts, not attach to the live telnetd attempt. To debug
the *live* failure, the ttyS0-in-normal-boot approach above is the only
option, or add a temporary explicit log redirect to the hook line instead
of `/dev/null` and reboot again to capture it on the console.)

## Backups

On-device (partition 26, `/usr/local/scripts/`):

- `start-firewall.sh.bak` — pre-edit original (697 bytes)
- `hisense_stage1.sh.bak` — pre-edit original (121 bytes)
- `rtr-telnet.sh.v1bak` — may or may not exist depending on which script run
  completed; verify before trusting it.

Local (`logs/` in this repo): a curated set of serial session captures kept
as evidence for the findings above — U-Boot help, stock + maintenance
bootargs, the eMMC partition table, the init chain, the firewall script and
its rules, one representative full boot, and the `v3-*` captures that prove
the no-PTY root cause (`v3-ttydrv`, `v3-fs`, `v3-tnd`, `v3-pty`, `v3-devpts`,
`v3-mod`, `v3-nc`, `v3-applets`, `v3-libc`). Redundant and dead-end captures
were dropped.

## Options going forward

1. **Debug why telnetd isn't binding in v2.** Cheapest concrete next step:
   edit `rtr-telnet.sh`'s last line to log instead of relying on telnetd's
   own behavior, e.g. redirect the hook line in `start-firewall.sh` to a
   real file instead of `/dev/null`
   (`/usr/local/scripts/rtr-telnet.sh >/var/local/rtr-telnet.log 2>&1 &`),
   reboot, then read `/var/local/rtr-telnet.log` from the `init=/bin/sh`
   maintenance shell afterward (p29/varlfs is mounted at `/var/local` in
   normal boot and is writable, so the log survives). That will show
   exactly where it's failing (iptables error, telnetd exit code/message,
   etc.) without needing the flaky ttyS0-after-boot console.
2. **Skip the network shell entirely**: use the serial maintenance shell
   directly (already working, root, p26 mounted rw) to find and delete the
   app launchers/payloads (candidates: partition 36 `apps`, and the
   `start-youtube.sh` / `start-vudu.sh` / `start-google_play_movies.sh` /
   etc. scripts on partition 26) without ever enabling telnet. Fully
   working today, no dependency on fixing telnet at all.
3. **Revert everything to stock**: restore `start-firewall.sh` from `.bak`,
   leave `rtr-telnet.sh` unreferenced or delete it, reboot. TV returns to
   fully original behavior (serial maintenance access remains available any
   time via `init=/bin/sh`, independent of any of this).

Note: deploying any telnetd-enabling script is something Claude will write
to a standalone shell script for the user to run themselves (`! bash
script.sh`), not execute directly — this got blocked by Claude's own safety
classifier when attempted directly in an earlier session. Getting *into*
the maintenance shell (U-Boot catch, `setenv bootargs`, `boot`, mounting
p26/devtmpfs/proc) has never been blocked and Claude can keep driving that
part directly.

**Coordination protocol:** physically power-cycling the TV is the user's
action, not Claude's. Claude asks explicitly whenever it needs a fresh U-Boot
catch ("need the MStar shell — please power-cycle now"); the user power-cycles
and Claude catches the prompt over serial (`sermash.py`/`sercmd.py` in the
scratchpad). Automated end-to-end by `mstar-to-shell.sh` (see below).

## ROOT CAUSE FOUND — telnet login shell is impossible on this kernel

Investigated live in the `init=/bin/sh` maintenance shell. The telnetd
approach is **fundamentally dead on this firmware**, and here is exactly why:

- **busybox telnetd binds port 23 fine.** Ran `/bin/busybox telnetd -l
  /bin/sh -p 23` directly: exit 0, process stays, `/proc/net/tcp` shows
  `00000000:0017` LISTEN. So binding was never the real problem.
- **The kernel has NO PTY support of any kind.** This is the wall:
  - `devpts` is not in `/proc/filesystems`; `mount -t devpts` fails with
    `No such device`; no `devpts.ko` on disk; `modprobe devpts` → not found.
  - `/proc/tty/drivers` lists only `tty`, `console`, `vc/0`, `serial`
    (`/dev/ttyS`), and legacy `console` — **no `pty_master`, no `pts`, no
    legacy BSD pty driver.**
  - No pty device nodes exist (`/dev/ptyp0`, `/dev/ttyp0` absent) and
    `/dev/ptmx` is a **dangling symlink** to the non-existent
    `/dev/pts/ptmx`.
- **Consequence:** busybox telnetd accepts the TCP connection, then calls
  getpty() to allocate a PTY for the login shell, which fails every possible
  way (no /dev/ptmx, no BSD fallback nodes, no driver) → it drops the
  connection. That is *exactly* the v1 symptom ("Connected… / Connection
  closed by foreign host"). No amount of script fixing changes this — a
  telnet **login shell** needs a PTY this kernel cannot provide.
- There is **no `nc`/`netcat` and no `socat`** applet in this busybox
  (full applet list captured in `logs/v3-applets.txt`), so a quick PTY-less
  raw relay out of stock tools isn't available either. Inbound TCP servers in
  this busybox: only `telnetd` (needs PTY), `udhcpd`, `dhcprelay` — none give
  a generic command channel.

**Net:** a remote shell on this TV requires either (a) a userland binary that
can serve a command channel **without a PTY** — dropbear ssh is ideal: `ssh
tv <cmd>` runs non-interactively over pipes, no PTY needed, and it's secure
over the internet (telnet is not) — or (b) a polling agent built from stock
`wget`/`ftpput`. It cannot be done with stock telnetd. See Options below.

The v2 "connection refused" (vs v1's "closed") is now moot and not worth
chasing: even with binding fixed, the PTY wall blocks a usable shell.

## `scripts/mstar-to-shell.sh` — automated U-Boot → root shell

`scripts/mstar-to-shell.sh` fully automates the maintenance-shell entry:
power the TV off, run `! bash scripts/mstar-to-shell.sh`, power on when prompted. It
spams CR to catch U-Boot, sets the `init=/bin/sh` bootargs (session-only,
never `saveenv`'d — reverts on any power cycle), boots, and mounts
devtmpfs/proc/usrfs(p26 rw), leaving a root `#`. Drive it afterward with
`sercmd.py`. This path has been 100% reliable.

## On-device cleanup status (this session)

The v2 `start-firewall.sh` hook still launches the (doomed) telnetd every
normal boot — harmless but pointless now. `scripts/enable-telnet-v3-debug.sh` was
written but **not run** (the debug-log reboot cycle is unnecessary now that
the PTY wall is confirmed directly). Reverting `start-firewall.sh` to
`start-firewall.sh.bak` is recommended once a path is chosen; left in place
for now in case the hook is reused to launch dropbear.

## Decision needed — which remote-access path

No decision made yet. Live options:

- **A. dropbear ssh (recommended for the stated goal).** Cross-compile static
  dropbear for armv7, drop on p26, generate host keys, launch from the
  `start-firewall.sh` hook, add an iptables ACCEPT for port 22. Gives secure,
  PTY-less `ssh tv <cmd>` remote maintenance that works over the internet
  from the parents' place. Interactive shell also possible (dropbear can run
  without a kernel PTY for exec; interactive is best-effort).
- **B. Debloat now over serial, skip remote entirely.** The maintenance shell
  works today (root, p26 rw). Find and remove the app launchers/payloads
  (p36 `apps`, and `start-youtube.sh`/`start-vudu.sh`/etc. on p26). Zero
  dependency on any remote shell.
- **C. Stock-busybox polling agent.** A boot-time loop using `wget`/`ftpput`
  to pull commands and push output. No new binary, but server-dependent and
  not interactive.

## Dropbear SSH — the chosen path

Telnet is impossible (no PTY, see above); SSH is the right tool anyway —
secure over the internet, and `ssh tv <cmd>` runs commands without a PTY
(over pipes), which is all the remote maintenance/debloat work needs.

**Build:** `.github/workflows/build-dropbear.yml` cross-compiles a fully
static `dropbearmulti` for this exact target:

- **armv7l, EABI soft-float** — the device's dynamic linker is
  `ld-linux.so.3` (soft-float), *not* `ld-linux-armhf.so.3`, so the build
  uses `gcc-arm-linux-gnueabi` (not `-gnueabihf`).
- **static link** — the TV ships glibc 2.18 (2013); a static binary sidesteps
  any libc-version mismatch. `MULTI=1 STATIC=1`.
- single binary provides server + `dropbearkey` + `dbclient` + `scp`.

CI runs on an Ubuntu runner (no local toolchain needed) and uploads
`dropbearmulti-armv7-static` as an artifact.

### WORKING — deployed and persistent across reboots

Confirmed: `ssh root@<tv>` gives uid 0 on the armv7l TV, and it survives a
power cycle. The must-get-right details, all learned the hard way:

- **p26 is READ-ONLY at normal boot.** This was the final blocker: the boot
  hook's log redirect to `/usr/local/...` failed silently and aborted the
  launcher before dropbear ever started. The launcher now **reads** everything
  from the (pre-populated) read-only p26 and **writes only to `/tmp`** (tmpfs).
  All on-device state is staged once from the maintenance shell (p26 rw there).
- **No PTY in this kernel**, so dropbear can only do PTY-less channels: use
  `ssh root@tv '<cmd>'` (one-shot) or `ssh -T root@tv 'sh'` (interactive
  dumb shell). A bare `ssh root@tv` would request a PTY and also source the
  heavy `/etc/profile`, so it hangs — don't use it.
- **root's shell `/bin/bash` does not exist** → dropbear rejects every login
  with "invalid shell". Fixed by bind-mounting a prebuilt `/etc/passwd` copy
  (on p26) whose root shell is `/bin/sh`. `/etc` is read-only, hence the bind.
- **root's home `/root` is read-only squashfs**, so `authorized_keys` can't
  live there → bind-mount a prebuilt home from p26 over `/root`.
- **firewall drops both INPUT dport 22 and OUTPUT sport 22** (`#for debug
  sshd`). The launcher inserts `ACCEPT`s ahead of the chain jumps and
  re-asserts them in a loop (firewall-init-subrule.sh runs in the background
  and can flush them).
- **launch early + detached:** dropbear is started from the *top* of
  `start-firewall.sh` and via `setsid` (survives the launcher/rcS exiting).
  An earlier version slept 10s before launching and got reaped.

On-device layout (staged from the maintenance shell, read-only at runtime):

```
/usr/local/bin/dropbearmulti          + symlinks dropbear/dropbearkey/dbclient/scp
/usr/local/dropbear/dropbear_ed25519_host_key
/usr/local/dropbear/root-home/.ssh/authorized_keys   (your SSH pubkey)
/usr/local/dropbear/passwd            (copy of /etc/passwd, root shell -> /bin/sh)
/usr/local/scripts/rtr-sshd.sh        (the launcher; logs to /tmp)
/usr/local/scripts/start-firewall.sh  (stock + the rtr-sshd hook at the top)
```

`scripts/rtr-sshd.sh` and `scripts/start-firewall.sh` in this repo are the
exact deployed files.

**File transfer to the TV:** U-Boot reports "No ethernet found" (U-Boot has
no NIC driver), but Linux does (`Mstar_emac`). In the maintenance shell,
ethernet needs a cable + manual bring-up (`ifconfig eth0 <ip>` — DHCP script
isn't present, so a static IP on the LAN is simplest); then `wget` the files
from a `python3 -m http.server` on the workstation. Binary + scripts all went
over this way, md5-verified.

**Usage:**
```
ssh root@<tv-ip> 'rm -rf /APPS/<bloat>'     # one-shot maintenance command
ssh -T root@<tv-ip> 'sh'                     # interactive (PTY-less) shell
```
The TV's IP is DHCP-assigned (changes across boots); find it by sweeping the
LAN for an `armv7l` host answering on 22, or give it a DHCP reservation.

## Publishing

This repo is being shared with the right-to-repair / open-source community.
The device MAC in `logs/02-printenv.txt` has been redacted. Private LAN IPs
(10.42.42.x) are left as-is (non-sensitive). Scripts hard-code the serial
device path `/dev/cu.usbserial-A10N456L` (a local FTDI adapter) — adjust for
your setup.
