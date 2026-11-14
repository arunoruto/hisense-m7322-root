"""Behavioral tests of restart limits, singleton locking, and signal cleanup."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from tv_common import make_bundle


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.work = Path(self.temp.name)
        self.bin = self.work / 'bin'
        self.bin.mkdir()
        # macOS lacks the flock utility. Use the same inherited-descriptor lock
        # behavior for these tests; on the TV the native BusyBox applet is used.
        self.executable('flock', '#!' + sys.executable + '''
import fcntl, sys
try:
    fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | (fcntl.LOCK_NB if '-n' in sys.argv else 0))
except BlockingIOError:
    sys.exit(1)
''')
        source = (ROOT / 'scripts/rtr-supervise.sh').read_text()
        source = source.replace('PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                                'PATH=' + str(self.bin) + ':/usr/bin:/bin:/usr/sbin:/sbin')
        self.script = self.work / 'supervise.sh'
        self.script.write_text(source)
        self.env = dict(os.environ, RTR_RUN_DIR=str(self.work))
        self.processes = []

    def executable(self, name, text):
        path = self.bin / name
        path.write_text(text)
        path.chmod(0o755)
        return str(path)

    def start(self, *cmd):
        proc = subprocess.Popen(['sh', str(self.script), 'test', *cmd], env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.processes.append(proc)
        return proc

    def wait_file(self, name):
        file = self.work / name
        end = time.monotonic() + 5
        while time.monotonic() < end:
            if file.exists() and file.read_text().strip():
                return file.read_text().strip()
            time.sleep(.02)
        self.fail('Timed out waiting for ' + name)

    def tearDown(self):
        for proc in self.processes:
            if proc.poll() is None:
                proc.terminate()
            try:
                proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
        self.temp.cleanup()

    def test_five_retries_then_stop_even_for_clean_exits(self):
        self.executable('sleep', '#!/bin/sh\necho "$1" >>"$RTR_RUN_DIR/delays"\n')
        daemon = self.executable('daemon', '#!/bin/sh\necho attempt >>"$RTR_RUN_DIR/attempts"\nexit 0\n')
        proc = self.start(daemon)
        self.assertEqual(proc.wait(timeout=5), 1)
        self.assertEqual((self.work / 'attempts').read_text().splitlines(), ['attempt'] * 6)
        self.assertEqual((self.work / 'delays').read_text().splitlines(), ['2', '4', '6', '8', '10'])
        self.assertFalse((self.work / 'rtr-test.supervisor.pid').exists())
        self.assertIn('Retry limit reached', (self.work / 'rtr-test.log').read_text())

    def test_singleton_and_term_stop_the_child(self):
        first = self.start('/bin/sleep', '60')
        child = int(self.wait_file('rtr-test.child.pid'))
        duplicate = self.start('/bin/sleep', '60')
        self.assertEqual(duplicate.wait(timeout=3), 0)
        self.assertEqual(int((self.work / 'rtr-test.child.pid').read_text()), child)
        first.terminate()
        self.assertEqual(first.wait(timeout=3), 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)
        self.assertFalse((self.work / 'rtr-test.child.pid').exists())


class BundleTests(unittest.TestCase):
    def test_failed_validation_preserves_existing_bundle(self):
        with tempfile.TemporaryDirectory() as d:
            archive = Path(d) / 'access.tar'
            archive.write_bytes(b'previous working bundle')
            key = Path(d) / 'key'
            key.write_text('-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n')
            with self.assertRaises(ValueError):
                make_bundle(archive, pubkey=key)
            self.assertEqual(archive.read_bytes(), b'previous working bundle')

    def test_bundle_cannot_overwrite_its_input(self):
        with tempfile.TemporaryDirectory() as d:
            binary = Path(d) / 'dropbearmulti'
            binary.write_bytes(b'working binary')
            with self.assertRaises(ValueError):
                make_bundle(binary, binary=binary)
            self.assertEqual(binary.read_bytes(), b'working binary')

    def test_public_key_line_endings_are_normalized(self):
        import tarfile
        with tempfile.TemporaryDirectory() as d:
            key = Path(d) / 'key.pub'
            key.write_bytes(b'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest fixture\r\n')
            archive = Path(d) / 'access.tar'
            make_bundle(archive, pubkey=key)
            with tarfile.open(archive) as bundle:
                data = bundle.extractfile('authorized_keys').read()
                self.assertEqual(data, key.read_bytes().replace(b'\r\n', b'\n'))
                self.assertEqual(bundle.getmember('authorized_keys').mode, 0o600)

    def test_private_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            key = Path(d) / 'key'
            key.write_text('-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n')
            with self.assertRaises(ValueError):
                make_bundle(Path(d) / 'access.tar', pubkey=key)

    def test_bundle_contains_every_required_script(self):
        import tarfile
        with tempfile.TemporaryDirectory() as d:
            archive = Path(d) / 'access.tar'
            make_bundle(archive)
            with tarfile.open(archive) as bundle:
                names = bundle.getnames()
                self.assertIn('rtr-supervise.sh', names)
                self.assertIn('install-on-tv.sh', names)
                self.assertIn('start-firewall.sh', names)
                self.assertTrue(all('/' not in name for name in names))



class SerialBootTests(unittest.TestCase):
    def helper(self, stock):
        import importlib.util
        import re
        spec = importlib.util.spec_from_file_location('serial_console', ROOT / 'scripts/serial-console.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        class FakeLink:
            def __init__(self):
                self.sent = []
                self.commands = []
                self.responses = [
                    'printenv bootargs\r\nbootargs=' + stock + '\r\n<< MStar >># ',
                    '\r\n<< MStar >># ',
                ]

            def read(self):
                return '\r\n<< MStar >># '

            def send(self, text):
                self.sent.append(text)
                if text.startswith('setenv bootargs '):
                    args = text[len('setenv bootargs '):]
                    self.responses.extend(['bootargs=' + args + '\r\n<< MStar >># ',
                                           "sh: can't access tty; job control turned off\r\n# "])

            def until(self, pattern, timeout):
                response = self.responses.pop(0)
                if not re.search(pattern, response):
                    raise AssertionError('Protocol mismatch: ' + repr(response))
                return response

            def command(self, command, timeout):
                self.commands.append(command)

        return module, FakeLink()

    def test_bootargs_come_from_the_current_device(self):
        module, link = self.helper('root=/dev/custom init=/init quiet BOOTLOGO_IN_MBOOT LX_MEM=custom console=ttyS0,115200')
        module.maintenance(link, 1)
        self.assertIn('setenv bootargs root=/dev/custom init=/bin/sh LX_MEM=custom console=ttyS0,115200', link.sent)
        self.assertIn('boot', link.sent)
        self.assertFalse(any('saveenv' in command for command in link.sent))
        self.assertIn('mount -t ext4', link.commands[0])

    def test_unexpected_uboot_characters_do_not_reach_boot(self):
        module, link = self.helper('init=/init unsafe=hello;reset')
        with self.assertRaises(RuntimeError):
            module.maintenance(link, 1)
        self.assertNotIn('boot', link.sent)

if __name__ == '__main__':
    unittest.main()
