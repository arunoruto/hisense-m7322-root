<a id="readme-top"></a>

[![Dropbear build][build-shield]][build-url]
[![Access tests][tests-shield]][tests-url]
[![Issues][issues-shield]][issues-url]
[![Stars][stars-shield]][stars-url]

<div align="center">
  <h1>Hisense m7322 Root Access</h1>
  <p>
    Reproducible root SSH access and Tailscale networking for an owned Hisense TV.
    <br />
    Built for right-to-repair and remote maintenance.
    <br /><br />
    <a href="docs/validation.md"><strong>Explore the validation notes »</strong></a>
    <br /><br />
    <a href="#getting-started">Get Started</a>
    &middot;
    <a href="https://github.com/arunoruto/hisense-m7322-root/issues/new">Report Bug</a>
    &middot;
    <a href="https://github.com/arunoruto/hisense-m7322-root/issues/new">Request Feature</a>
  </p>
</div>

<details>
  <summary>Table of Contents</summary>

  - [About the Project](#about-the-project)
    - [Verified Findings](#verified-findings)
    - [Built With](#built-with)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Installation](#installation)
    - [First Installation Using UART](#first-installation-using-uart)
    - [Install or Update Tailscale](#install-or-update-tailscale)
  - [Usage](#usage)
    - [SSH and File Transfer](#ssh-and-file-transfer)
    - [Startup and Recovery](#startup-and-recovery)
    - [Restore Vendor Startup](#restore-vendor-startup)
  - [Project Structure](#project-structure)
  - [Validation](#validation)
  - [Roadmap](#roadmap)
  - [Contributing](#contributing)
  - [License](#license)
  - [Contact](#contact)
  - [Acknowledgments](#acknowledgments)

</details>

## About the Project

This project gives an owned Hisense TV a persistent root command channel for
remote maintenance. It uses a small, static Dropbear SSH server and optional
Tailscale networking so the TV can be managed after it moves to another home.
The current scope is device access; app removal and debloating are future work.

The work started with UART access through U-Boot. Telnet was abandoned after
serial evidence showed that this kernel has no PTY driver. Dropbear can execute
commands through pipes, so it works without rebuilding the vendor kernel.
Tailscale's userspace mode also avoids the missing TUN driver and forwards
incoming tailnet TCP connections to local services, including Dropbear on port 22.
No router port forwarding is needed.

### Verified Findings

Tested on the documented unit on **2026-11-14**; compatibility with other models
or firmware versions has not been established.

| Component | Finding |
| --- | --- |
| Board / CPU | MStar/Sigmastar `m7322`, ARMv7 (`armv7l`) |
| Firmware | Linux `4.9.44+`, BusyBox `1.22.1`, U-Boot `2011.06` |
| Root filesystem | Read-only SquashFS; vendor partitions provide customization hooks |
| SSH | Dropbear `2022.83`; public-key root access, without a PTY |
| VPN | Tailscale `1.104.7` verified in userspace mode; existing SSH keys still authenticate sessions |
| Service recovery | Initial start plus five retries, then stop; no blocking boot loop |
| Cold boot | SSH, Tailscale identity, and firewall rules survived a full power cycle |
| Standby | Observed to make the TV unreachable; automatic wake-up is not implemented |

Read the [validation record](docs/validation.md) for tested behavior and remaining
limits. No saved U-Boot environment or bundled TV apps were changed during these
access tests.

### Built With

- [Dropbear](https://github.com/mkj/dropbear) — lightweight SSH server and tools.
- [Tailscale](https://tailscale.com/) — optional remote connectivity in userspace.
- [Python](https://www.python.org/) and [pySerial](https://pyserial.readthedocs.io/) — workstation installers and UART automation.
- [BusyBox](https://busybox.net/) — the TV's existing shell and runtime tools.
- [Zig](https://ziglang.org/), musl, QEMU, and GitHub Actions — static ARM builds and smoke tests.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

### Prerequisites

For a TV with working SSH, the workstation needs **Python 3.9+**, OpenSSH, and a
working SSH key. Tailscale installation additionally uses `curl` on the workstation
and a Tailscale account. The SSH installers use Python's standard library.

For a first installation, also provide a suitable 3.3 V logic UART adapter,
Ethernet, a static ARM Dropbear artifact, and pySerial. Confirm the documented
board and partition layout before using the UART installation procedure.

Clone the repository:

```sh
git clone https://github.com/arunoruto/hisense-m7322-root.git
cd hisense-m7322-root
```

Examples use `10.42.42.239` as the TV's LAN address. Substitute your device's
address; bootstrap HTTP examples also need your workstation's LAN address.

### Installation

If SSH already works, install or update the access scripts:

```sh
python3 scripts/install-access.py root@10.42.42.239
python3 scripts/activate-access.py root@10.42.42.239
```

The first command backs up vendor scripts once, installs the access scripts,
restores SSH firewall rules, and leaves an existing listener running. The second
moves the listener under supervision without rebooting; it verifies a fresh SSH
connection afterward. An already-running supervisor is left alone.

To add a public key, pass `--pubkey ~/.ssh/id_ed25519.pub`. Existing authorized
keys and the host key are preserved. `--binary /path/to/dropbearmulti` explicitly
replaces the server binary; omitting it keeps the installed version. Dropbear
**2022.83 remains the default** for compatibility with the deployed build.

Reinstalling updates files for the next supervisor start; it does not restart an
already supervised service. To deliberately restart supervision:

```sh
ssh -T root@10.42.42.239 'kill "$(cat /tmp/rtr-sshd.supervisor.pid)"'
python3 scripts/activate-access.py root@10.42.42.239
```

Keep a UART recovery connection available when changing access software. The
restart creates a brief gap for new connections; existing authenticated sessions
normally survive stopping the listener.

### First Installation Using UART

These instructions target the documented board/partition layout. Confirm yours
before mounting or writing partitions. UART requires a suitable **3.3 V logic**
USB serial adapter, GND/TX/RX, 115200 baud, 8N1. Do not connect adapter power to
the TV. Board photographs are in [assets](assets/).

1. Build Dropbear using the manually dispatched
   [GitHub Actions workflow](.github/workflows/build-dropbear.yml). Its artifact
   `dropbearmulti-armv7-static` contains a Zig/musl static soft-float ARM binary.
   CI checks its ELF format and runs key-generation/usage smoke tests in QEMU.
   These do not emulate the TV's kernel or test SSH authentication. No local
   cross-compiler is needed. Keep the downloaded binary with your deployment
   record; the workflow records source revision and SHA256 alongside it.
2. Build a bundle using the unpacked artifact and your **public** key:

   ```sh
   python3 scripts/install-access.py --bundle /tmp/access.tar \
     --binary /path/to/dropbearmulti --pubkey ~/.ssh/id_ed25519.pub
   ```

3. Install the UART dependency and open maintenance mode with the TV off:

   ```sh
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   .venv/bin/python scripts/serial-console.py --port /dev/cu.usbserial-YOUR_ADAPTER \
     --maintenance --log /tmp/tv-maintenance.log
   ```

   Power on when prompted. The helper catches the actual U-Boot prompt, reads
   **this TV's** bootargs, changes `init=` to `/bin/sh`, removes the bare
   `BOOTLOGO_IN_MBOOT` token and `quiet`, verifies the result, boots, and checks
   root access plus p26 mounted writable. It never executes `saveenv` and never
   power-cycles the TV. A subsequent cold boot restores saved stock bootargs.
   `scripts/mstar-to-shell.sh --port ...` is a compatibility entry point.
4. Connect Ethernet. From the maintenance shell, set an unused LAN address and
   fetch the bundle from a workstation HTTP server. Example addresses below must
   be adapted to your LAN:

   ```sh
   # Workstation, in another terminal:
   python3 -m http.server 8000 --bind 10.42.42.1 --directory /tmp
   # UART command runner:
   .venv/bin/python scripts/serial-console.py --port /dev/cu.usbserial-YOUR_ADAPTER \
     --command 'ifconfig eth0 10.42.42.239 netmask 255.255.255.0 up'
   .venv/bin/python scripts/serial-console.py --port /dev/cu.usbserial-YOUR_ADAPTER \
     --timeout 120 --command 'mkdir -p /tmp/access && wget -O /tmp/access.tar http://10.42.42.1:8000/access.tar && tar xf /tmp/access.tar -C /tmp/access && sh /tmp/access/install-on-tv.sh'
   ```

   HTTP is only the local bootstrap transport; use a trusted direct/LAN link.
   Stop the HTTP server afterward. The helper holds a serial FD open for each
   operation and verifies command exit status using a random output marker.
5. In maintenance mode, finish writes before returning to normal boot:

   ```sh
   .venv/bin/python scripts/serial-console.py --port /dev/cu.usbserial-YOUR_ADAPTER \
     --command 'sync && umount /usr/local'
   ```

   Power-cycle the TV yourself. Do not exit the PID-1 maintenance shell: doing
   so panics the kernel. Once normal boot finishes, verify SSH using `id` and
   check the supervisor log. Install Tailscale separately afterward.

### Install or Update Tailscale

Install the access scripts above first. Then, from your workstation:

```sh
python3 scripts/install-tailscale.py root@10.42.42.239
# Optional exact version, for a repeatable deployment:
python3 scripts/install-tailscale.py root@10.42.42.239 --version 1.104.7
```

The same command installs or updates. It downloads official stable ARM binaries
using the workstation's HTTPS certificate store, verifies the publisher's SHA256,
and streams only the required files over SSH. The TV needs no TLS downloader,
package manager, systemd, kernel module, or compiler. The verified archive digest
is stored with the release. Use the **LAN address** for updates because Tailscale
is restarted during an update.

Binaries and identity live under `/var/local/rtr/tailscale`, on writable p29;
logs and the local API socket live under `/tmp`. The installer checks free space
and executes both new binaries before selecting them. Previous release files and
persistent identity are retained. An update stops the supervised daemon, switches
the version symlink, and restarts it. If the local API does not respond, it selects
the previous binary version again. Daemon state is not downgraded or restored;
upstream state-format changes can therefore limit rollback. Old releases are not
automatically deleted: inspect available space before subsequent updates.

Authenticate once by opening the URL printed by:

```sh
ssh -T root@10.42.42.239 '/usr/local/bin/tailscale-tv up --accept-dns=false --hostname=hisense-tv'
```

Allow the TV in your tailnet policy, then check its address:

```sh
ssh -T root@10.42.42.239 '/usr/local/bin/tailscale-tv ip -4'
ssh -T root@10.42.42.239 '/usr/local/bin/tailscale-tv status'
ssh -T root@100.x.y.z 'id'
```

This uses **ordinary Dropbear SSH over Tailscale**, with your existing SSH key.
Tailscale SSH is not enabled. DNS configuration is left to the vendor firmware.
Userspace mode supports incoming TCP forwarding; it does not give every TV
application a normal VPN interface. No exit-node or subnet-router setup is
performed. If the vendor EULA-off policy blocks Tailscale's outgoing control or
relay traffic, LAN SSH remains available; these scripts do not override that
internet policy. Check node key expiry in the Tailscale admin console before
relying on unattended access.

Tailscale uses the same five-retry supervisor. Inspect
`/tmp/rtr-tailscaled.log` and `/tmp/rtr-start.log` for startup failures.

Official references: [static Linux installation](https://tailscale.com/docs/install/linux),
[userspace mode](https://tailscale.com/docs/concepts/userspace-networking),
[incoming userspace forwarding](https://tailscale.com/docs/reference/faq/other-vpns),
[stable packages](https://pkgs.tailscale.com/stable/).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Usage

### SSH and File Transfer

```sh
ssh -T root@10.42.42.239 'id'
ssh -T root@10.42.42.239 'sh'
```

Use your own IP or hostname. Reserve the TV's address in DHCP. The second command
is a simple shell without terminal editing, job control, or terminal applications.
Always use `-T` to suppress PTY requests. Supplying `sh` also avoids the heavy
vendor login profile. Do not run an unqualified login shell.

Modern OpenSSH `scp` uses SFTP, which this TV does not provide. For file transfer:

```sh
scp -O ./file root@10.42.42.239:/tmp/file
# Or stream a file without either SCP or SFTP:
ssh -T root@10.42.42.239 'cat >/tmp/file' < ./file
```

**Standby currently makes the TV unreachable.** Tailscale cannot keep a suspended
CPU/network interface awake. Cold-boot startup has been verified; automatic
wake-up remains future work.

### Startup and Recovery

- Vendor `rcS` invokes `start-firewall.sh`. Its installed wrapper starts detached
  supervision, then runs the saved vendor script and reapplies SSH rules.
- Wrappers for `firewall-init-subrule.sh`, `firewall-eulaon.sh`, and
  `firewall-eulaoff.sh` also restore SSH rules after the vendor script finishes.
  This covers asynchronous initialization and later EULA changes, without a
  timed polling loop or changes to the vendor EULA setting.
- `rtr-firewall.sh` adds missing INPUT/dport-22 and OUTPUT/sport-22 ACCEPT rules.
  A lock prevents concurrent helper calls from adding duplicates. This preserves
  the existing policy of allowing SSH from any reachable source; restrict access
  at your router/tailnet policy. There is no perpetual firewall watcher.
- Dropbear runs foreground under `rtr-supervise.sh`. There is **one initial
  launch plus five retries**, delayed 2, 4, 6, 8, and 10 seconds. Exits with any
  status count, including zero. The counter never resets during that supervisor
  lifetime. After exhaustion, start it manually or cold-boot the TV.
- A nonblocking `flock` prevents duplicate supervisors. Boot does not wait for
  the retry loop. PID files and logs live in `/tmp` and disappear on cold boot.
- The launcher checks the host key, public keys, and passwd overlay before
  launching. Bind mounts supply root's valid `/bin/sh` and its SSH home; p26
  remains read-only during normal operation.

All four vendor originals are saved under
`/usr/local/dropbear/vendor-originals/`. The installer understands the previous
repository version's `start-firewall.sh.bak` and uses that stock backup when
migrating the old injected hook. It refuses an already-wrapped file with no
saved original. Updates do not overwrite originals.

Inspect status:

```sh
ssh -T root@10.42.42.239 'cat /tmp/rtr-sshd.log; cat /tmp/rtr-sshd.supervisor.pid; cat /tmp/rtr-sshd.child.pid'
ssh -T root@10.42.42.239 '/usr/local/bin/iptables -L INPUT -n --line-numbers'
```

The SSH shell's default PATH omits `/usr/local/bin`; use absolute paths for
vendor utilities such as iptables and the Tailscale wrapper.

### Restore Vendor Startup

```sh
ssh -T root@10.42.42.239 'sh /usr/local/scripts/rtr-uninstall.sh'
```

This restores all four vendor firewall scripts. It leaves the current SSH and
Tailscale processes running so you can finish your session, and does not reboot.
On the next cold boot neither service starts. Binaries, keys, identity, and
backups are retained for reinstall/recovery. Restoring vendor files and rebooting
does not restore deleted apps or unrelated changes. If SSH is unavailable, use
UART maintenance mode and run the same script.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Project Structure

| Path | Purpose |
| --- | --- |
| [scripts/install-access.py](scripts/install-access.py) | Bundle or deploy SSH access files |
| [scripts/activate-access.py](scripts/activate-access.py) | Move a running listener under supervision |
| [scripts/install-tailscale.py](scripts/install-tailscale.py) | Install or update verified official ARM Tailscale binaries |
| [scripts/serial-console.py](scripts/serial-console.py) | Enter maintenance mode and run UART commands |
| [scripts/rtr-supervise.sh](scripts/rtr-supervise.sh) | Shared bounded-retry service supervisor |
| [scripts/rtr-firewall.sh](scripts/rtr-firewall.sh) | Restore SSH rules after vendor firewall rebuilds |
| [.github/workflows](.github/workflows/) | CI workflows |
| [tests](tests/) | Automated access-tool tests |
| [assets](assets/) | Board and UART photographs |
| [logs](logs/) | Tracked historical serial evidence, including the absent PTY driver |
| [docs/validation.md](docs/validation.md) | Live validation results and testing limits |
| [docs/history](docs/history/) | Original investigation and abandoned telnet scripts; scratchpad paths are obsolete |

Known partitions on this firmware:

| Partition | Mount / role | Normal boot access |
| --- | --- | --- |
| p9 | SquashFS root | Read-only |
| p26 | `/usr/local`; access scripts, Dropbear, host key, public keys | Read-only |
| p28 | `/usr/local/opt`; bundled software | Read-only |
| p29 | `/var/local`, shown as `/dev/shm/local` in mounts; persistent Tailscale files | Writable |
| p36 | `/APPS` | Writable |

`/applications` points into `/tvservice`; most bundled services are not stored
under `/APPS`. Keep new raw session captures outside git and redact credentials
and device identifiers before sharing evidence.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Validation

The access-test workflow runs shell syntax, Python syntax, and the hardware-free
regression suite on pushes and pull requests that change the access tools.
The current suite has **nine passing local tests**.

The [live validation record](docs/validation.md) covers LAN and tailnet SSH,
automatic recovery after terminating both daemons, the native retry cutoff,
firewall restoration, repeated installation, and startup after a full power cycle.
The vendor EULA-off path, a fresh installation using the revised UART helper,
and a future-version Tailscale update/rollback have not been tested on this unit.

Run the automated tests on the workstation:

```sh
python3 -m unittest discover -s tests -v
```

The Dropbear workflow separately checks ELF format and performs key-generation
and usage smoke tests in QEMU. Those checks do not emulate the TV's kernel or
verify authentication on the hardware.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Roadmap

- [x] Reversible UART maintenance access without `saveenv`.
- [x] Persistent public-key SSH without a PTY.
- [x] Bounded service recovery and firewall rebuild hooks.
- [x] Tailscale userspace installation and same-version reruns.
- [x] Verify SSH and Tailscale after a cold boot.
- [ ] Investigate reliable wake-up from standby.
- [ ] Exercise future-version Tailscale upgrades and failure rollback on hardware.
- [ ] Validate the revised UART bootstrap on a fresh installation.
- [ ] Add reversible, individually tested debloating options.
- [ ] Document compatibility with additional boards and firmware versions.

See [open issues][issues-url] for discussion and reported problems.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contributing

Bug reports, portability fixes, and evidence from other firmware versions are
welcome. Include the TV model, board, kernel version, the command that failed,
and redacted output. Distinguish hardware observations from hypotheses.

1. Fork the repository and create a branch for your change.
2. Keep changes compatible with the documented BusyBox tools and read-only mounts.
3. Add focused regression tests for behavior changes and run the test suite.
4. Describe any hardware validation and rollback procedure in your pull request.

Never submit private SSH keys, Tailscale state/auth keys, or unredacted account
information. Keep abandoned experiments in the historical notes rather than the
main installation path.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## License

A project license file has not been added. Third-party components retain their
upstream licenses.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contact

Maintainer: [@arunoruto](https://github.com/arunoruto).

Use [GitHub issues][issues-url] for support, bug reports, and feature discussions.
Project: [arunoruto/hisense-m7322-root][repo-url].

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Acknowledgments

- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) by
  othneildrew, adapted for this README's layout.
- Dropbear, Tailscale, BusyBox, pySerial, Zig, musl, and QEMU contributors.
- Right-to-repair and embedded Linux communities sharing tools and findings.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[repo-url]: https://github.com/arunoruto/hisense-m7322-root
[build-shield]: https://github.com/arunoruto/hisense-m7322-root/actions/workflows/build-dropbear.yml/badge.svg
[build-url]: https://github.com/arunoruto/hisense-m7322-root/actions/workflows/build-dropbear.yml
[tests-shield]: https://github.com/arunoruto/hisense-m7322-root/actions/workflows/test-access.yml/badge.svg
[tests-url]: https://github.com/arunoruto/hisense-m7322-root/actions/workflows/test-access.yml
[issues-shield]: https://img.shields.io/github/issues/arunoruto/hisense-m7322-root.svg?style=flat-square
[issues-url]: https://github.com/arunoruto/hisense-m7322-root/issues
[stars-shield]: https://img.shields.io/github/stars/arunoruto/hisense-m7322-root.svg?style=flat-square
[stars-url]: https://github.com/arunoruto/hisense-m7322-root/stargazers
