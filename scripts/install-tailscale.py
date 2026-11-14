#!/usr/bin/env python3
"""Install or update official ARM Tailscale binaries on this TV over LAN SSH."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile
import tempfile
from tv_common import SCRIPTS, download, ssh, upload


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('host', help='Use the LAN SSH address; updates restart Tailscale')
    p.add_argument('--version', help='Exact stable version; default: latest official stable')
    a = p.parse_args()
    with tempfile.TemporaryDirectory(prefix='hisense-tailscale-') as work:
        work = Path(work)
        version = a.version
        if version is None:
            download('https://pkgs.tailscale.com/stable/?mode=json', work / 'metadata.json')
            version = json.loads((work / 'metadata.json').read_text())['TarballsVersion']
        if not re.fullmatch(r'\d+\.\d+\.\d+', version):
            p.error('Version must be digits.digits.digits')
        filename = f'tailscale_{version}_arm.tgz'
        url = 'https://pkgs.tailscale.com/stable/' + filename
        download(url + '.sha256', work / 'checksum')
        expected = (work / 'checksum').read_text().split()[0]
        if not re.fullmatch(r'[0-9a-fA-F]{64}', expected):
            raise ValueError('Invalid upstream SHA256')
        download(url, work / filename)
        digest = hashlib.sha256((work / filename).read_bytes()).hexdigest()
        if digest != expected.lower():
            raise ValueError('Tailscale SHA256 mismatch; nothing uploaded')
        # Extract only two regular files with exact names. Never unpack arbitrary
        # upstream paths, links, permissions, or ownership into the workstation.
        with tarfile.open(work / filename, 'r:gz') as source:
            for name in ['tailscale', 'tailscaled']:
                member = source.getmember(f'tailscale_{version}_arm/{name}')
                if not member.isfile():
                    raise ValueError('Expected a regular binary')
                (work / name).write_bytes(source.extractfile(member).read())
        (work / 'version').write_text(version + '\n')
        (work / 'SHA256').write_text(digest + '\n')
        with tarfile.open(work / 'install.tar', 'w') as bundle:
            for name in ['tailscale', 'tailscaled', 'version', 'SHA256']:
                bundle.add(work / name, arcname=name)
            bundle.add(SCRIPTS / 'install-tailscale-on-tv.sh', arcname='install.sh')
        print('Verified official ARM release', version, digest, flush=True)
        upload(a.host, work / 'install.tar', 'sh install.sh')
        print('If not already authenticated, run this and open the URL it prints:')
        print(f"ssh -T {a.host} '/usr/local/bin/tailscale-tv up --accept-dns=false --hostname=hisense-tv'")
        print('Updates preserve identity and do not require another login unless the node key has expired.')


if __name__ == '__main__':
    main()
