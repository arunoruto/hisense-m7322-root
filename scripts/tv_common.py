"""Workstation helpers: authenticated SSH, tar streaming, verified HTTPS downloads."""
from pathlib import Path
import io
import os
import re
import secrets
import subprocess
import tarfile
import tempfile

SCRIPTS = Path(__file__).resolve().parent


def ssh(host, command, **kwargs):
    if not host or host.startswith('-') or not re.fullmatch(r'[A-Za-z0-9_.@:\[\]-]+', host):
        raise ValueError('Invalid SSH destination')
    return subprocess.run(['ssh', '-T', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=10',
                           '-o', 'ServerAliveCountMax=3', host, command], check=True, **kwargs)


def upload(host, archive, command):
    remote = '/tmp/rtr-install-' + secrets.token_hex(8)
    # Directory is private and unpredictable; payload contains only known members.
    cmd = (f'umask 077; mkdir {remote} && tar xf - -C {remote} && '
           f'(cd {remote} && {command}); rc=$?; rm -rf {remote}; exit $rc')
    with open(archive, 'rb') as source:
        ssh(host, cmd, stdin=source)


def download(url, destination):
    # curl uses the workstation CA store; no dependence on the TV's old TLS tools.
    subprocess.run(['curl', '--fail', '--location', '--proto', '=https',
                    '--tlsv1.2', '--retry', '2', '--connect-timeout', '15',
                    '--max-time', '600', '--output', str(destination), url], check=True)


def make_bundle(output, binary=None, pubkey=None):
    names = ['install-on-tv.sh', 'uninstall-on-tv.sh', 'start-firewall.sh',
             'tailscale-tv.sh', 'rtr-sshd.sh', 'rtr-supervise.sh', 'rtr-start.sh',
             'rtr-firewall.sh', 'rtr-firewall-wrapper.sh', 'rtr-tailscaled.sh']
    output = Path(output)
    sources = [SCRIPTS / name for name in names]
    sources.extend(Path(path) for path in (binary, pubkey) if path is not None)
    for source in sources:
        if output.resolve() == source.resolve():
            raise ValueError('Bundle output must not overwrite an input file')
        if not source.is_file():
            raise ValueError('Missing bundle input: ' + str(source))
    key_data = None
    if pubkey:
        key = Path(pubkey).read_text().strip()
        if '\n' in key or not re.match(r'^(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+) [A-Za-z0-9+/=]+(?: |$)', key):
            raise ValueError('Supply one OpenSSH public key, never a private key')
        # Normalize Windows line endings before the TV appends authorized_keys.
        key_data = (key + '\n').encode()
    # Build alongside the destination and replace only on success. Invalid input
    # or a failed archive write must not destroy a previous working bundle.
    with tempfile.NamedTemporaryFile(dir=output.parent, prefix='.access-', delete=False) as staging:
        temporary = Path(staging.name)
    try:
        with tarfile.open(temporary, 'w') as tar:
            for name in names:
                tar.add(SCRIPTS / name, arcname=name)
            if binary:
                tar.add(binary, arcname='dropbearmulti')
            if key_data is not None:
                member = tarfile.TarInfo('authorized_keys')
                member.mode = 0o600
                member.size = len(key_data)
                tar.addfile(member, io.BytesIO(key_data))
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
