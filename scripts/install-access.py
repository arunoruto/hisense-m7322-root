#!/usr/bin/env python3
"""Build a first-install bundle, or deploy to a TV with working SSH."""
import argparse
from pathlib import Path
import tempfile
from tv_common import make_bundle, upload


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('host', nargs='?', help='SSH destination, e.g. root@10.42.42.239')
    p.add_argument('--binary', type=Path, help='Static ARM dropbearmulti; omitted to retain installed binary')
    p.add_argument('--pubkey', type=Path, help='Public key to add; omitted to retain installed keys')
    p.add_argument('--bundle', type=Path, help='Write a tar bundle for UART/HTTP bootstrap instead of SSH')
    a = p.parse_args()
    if bool(a.host) == bool(a.bundle):
        p.error('Choose an SSH host OR --bundle')
    if a.bundle:
        make_bundle(a.bundle, a.binary, a.pubkey)
        print('Bundle:', a.bundle)
    else:
        with tempfile.TemporaryDirectory(prefix='hisense-') as work:
            bundle = Path(work) / 'access.tar'
            make_bundle(bundle, a.binary, a.pubkey)
            upload(a.host, bundle, 'sh install-on-tv.sh')


if __name__ == '__main__':
    main()
