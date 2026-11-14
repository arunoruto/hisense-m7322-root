# Access validation — 2026-11-14

Tested against the documented m7322 TV, ARMv7, Linux 4.9.44+, BusyBox 1.22.1.
Dropbear remains 2022.83. Official static ARM Tailscale 1.104.7 runs in userspace
mode. No apps were removed and no saved U-Boot environment was changed.

## Passed on the TV

- Migrated the earlier injected boot hook, preserving the stock start-firewall
  backup and saving the other three vendor firewall scripts once.
- Activated foreground Dropbear supervision without rebooting; opened a fresh
  root SSH connection afterward.
- Ran the vendor EULA-on and asynchronous-subrule rebuild paths through their
  new wrappers. Both SSH ACCEPT rules were restored, with one copy of each.
  EULA-off has the same wrapper, but was not invoked during this test to avoid
  changing the running TV's outbound internet policy.
- Installed Tailscale from the verified official ARM archive; its local API,
  authenticated tailnet connection, and SSH forwarding all worked.
- Terminated the Dropbear listener and Tailscale daemon. Both restarted on retry
  1/5. Tailscale retained its login and address after initialization completed.
- Started an isolated failing service under the native BusyBox supervisor. It
  ran exactly six times, with five delays totaling 30 seconds, then stopped and
  removed its supervisor PID file.
- Reran the Tailscale installer for the installed version. It retained the
  release, identity, and existing supervisor.
- User performed a full power cycle. Boot ID changed; both supervisors started
  with retry 0/5, SSH worked over LAN, and Tailscale retained its address.
  `/usr/local` remained read-only and both SSH firewall rules were present.

Tailscale archive SHA256:
`1c753fef45d497491081db37552b7a2a42c7932292743bf6936cb1a42b6bceb0`.
This is a release checksum, not a device identity or authentication credential.

## Workstation checks

`python3 -m unittest discover -s tests -v`: nine passing tests covering bounded
retries/backoff, singleton locking, signal cleanup, bundle completeness, private
key rejection, preserving existing bundles and input files on failure, normalizing
public-key line endings, and deriving/validating current-device U-Boot arguments. Shell
syntax checks, Python compilation, and `git diff --check` also passed.

## Remaining limits

- Standby was observed to make LAN SSH unavailable. Automatic wake-up and
  Tailscale access while suspended are not implemented.
- The revised UART bootstrap protocol has simulated tests; a fresh UART install
  was not performed during this validation. The hardware maintenance method is
  supported by the historical logs.
- Tailscale installation and same-version rerun were tested. Switching to a
  future release and its failure/rollback path have not been exercised on this
  TV. Saved daemon state is retained across rollback, so upstream state-format
  changes can limit backward compatibility.
- The new GitHub Actions build-provenance step was reviewed but CI was not run.
  Runtime Dropbear was intentionally retained rather than rebuilt.

## Documentation and workstation follow-up

The README now follows Best-README-Template and includes the verified hardware
findings, installation paths, usage, recovery, roadmap, and project links.
Bundle creation now validates inputs before writing, stages the archive beside
the destination, and replaces it only on success. It refuses to overwrite its
own input files and normalizes public-key line endings. Three regression tests
cover these changes.

A hardware-free access-test workflow was added; it has not yet run on GitHub.
These follow-up changes are confined to the workstation tools, CI, and
documentation. They do not require another TV deployment or reboot.
