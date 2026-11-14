#!/usr/bin/env python3
"""UART maintenance entry and command runner; requires pyserial (see requirements.txt)."""
import argparse
from pathlib import Path
import re
import secrets
import sys
import time


class Link:
    def __init__(self, port, baud, log):
        import serial
        self.serial = serial.Serial(port, baud, timeout=0.05, rtscts=False,
                                    xonxoff=False, dsrdtr=False)
        self.log = open(log, 'ab') if log else None

    def close(self):
        self.serial.close()
        if self.log:
            self.log.close()

    def send(self, text):
        self.serial.write(text.encode() + b'\r')
        self.serial.flush()

    def read(self):
        data = self.serial.read(4096)
        if self.log:
            self.log.write(data)
            self.log.flush()
        return data.decode('latin-1')

    def until(self, pattern, timeout, initial=''):
        output = initial
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            output += self.read()
            if re.search(pattern, output):
                return output
        raise RuntimeError('Serial timeout; last output: ' + repr(output[-1200:]))

    def command(self, command, timeout):
        marker = '__RTR_DONE_' + secrets.token_hex(8)
        # Require a standalone output line, never the echoed command text.
        self.send(command + "; printf '\\n" + marker + ":%s\\n' \"$?\"")
        pattern = r'(?:^|[\r\n])' + marker + r':([0-9]+)[\r\n]'
        out = self.until(pattern, timeout)
        print(out, end='')
        rc = int(re.search(pattern, out).group(1))
        if rc:
            raise RuntimeError('TV command failed with status ' + str(rc))
        return out


def maintenance(link, timeout):
    print('Power the TV on now. Waiting for the actual U-Boot prompt...', flush=True)
    output = ''
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        link.send('')
        output += link.read()
        if re.search(r'<< MStar >>#', output):
            break
        time.sleep(0.02)
    else:
        raise RuntimeError('U-Boot prompt not found; no bootargs changed')
    link.send('printenv bootargs')
    out = link.until(r'(?:^|[\r\n])bootargs=[^\r\n]+[\r\n][\s\S]*?<< MStar >>#', 10)
    match = re.search(r'(?:^|[\r\n])bootargs=([^\r\n]+)', out)
    stock = match.group(1)
    # Derive from THIS device, preserving its memory/partition/board settings.
    tokens = stock.split()
    if sum(t.startswith('init=') for t in tokens) != 1:
        raise RuntimeError('Expected exactly one init= argument; inspect bootargs manually')
    tokens = ['init=/bin/sh' if t.startswith('init=') else t for t in tokens
              if t not in ('BOOTLOGO_IN_MBOOT', 'quiet')]
    args = ' '.join(tokens)
    if re.search(r"[^A-Za-z0-9_.,:/=%+@ -]", args):
        raise RuntimeError('Unexpected U-Boot argument characters; inspect manually')
    print('Stock bootargs:', stock)
    print('Temporary bootargs:', args)
    link.send('setenv bootargs ' + args)
    link.until(r'<< MStar >>#', 10)
    link.send('printenv bootargs')
    check = link.until(r'(?:^|[\r\n])bootargs=[^\r\n]+[\r\n][\s\S]*?<< MStar >>#', 10)
    if re.search(r'(?:^|[\r\n])bootargs=([^\r\n]+)', check).group(1).strip() != args:
        raise RuntimeError('Bootargs verification failed; refusing to boot')
    link.send('boot')
    link.until(r"can't access tty|(?:^|[\r\n])# ", 90)
    link.command('mount -t devtmpfs dev /dev && mount -t proc proc /proc && '
                 'mount -t ext4 -o rw /dev/mmcblk0p26 /usr/local', 15)
    link.command('[ "$(id -u)" = 0 ] && '
                 "awk '$2==\"/usr/local\" && $4 ~ /(^|,)rw(,|$)/ {ok=1} END{exit !ok}' /proc/mounts", 10)
    print('\nRoot maintenance shell ready; p26 verified writable. No saveenv performed.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True, help='/dev/cu.usbserial-... or /dev/ttyUSB0')
    p.add_argument('--baud', type=int, default=115200)
    p.add_argument('--log', type=Path)
    p.add_argument('--timeout', type=float, default=45)
    group = p.add_mutually_exclusive_group(required=True)
    group.add_argument('--maintenance', action='store_true')
    group.add_argument('--command', help='Run in an already-active maintenance shell')
    a = p.parse_args()
    link = Link(a.port, a.baud, a.log)
    try:
        if a.maintenance:
            maintenance(link, a.timeout)
        else:
            link.command(a.command, a.timeout)
    finally:
        link.close()


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError) as error:
        sys.exit(str(error))
