import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    'wproxy_telemetry', Path(__file__).resolve().parents[1] / 'cli/wproxyctl.py')
ctl = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ctl)


@unittest.skipIf(os.name == 'nt', 'Linux /proc telemetry')
class CoreTelemetryTests(unittest.TestCase):
    def test_systemd_wrapper_is_not_reported_as_the_active_core(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'uptime').write_text('120.0 0.0')
            for pid, executable, pages in (
                ('100', '/usr/bin/systemd-run', 100),
                ('101', '/usr/local/bin/xray', 9000),
            ):
                process = root / pid
                process.mkdir()
                (process / 'cmdline').write_bytes(
                    executable.encode() + b'\0-c\0/run/NetworkManager/wproxy/xray.json\0')
                (process / 'stat').write_text(
                    pid + ' (engine) ' + ' '.join(['S'] + ['0'] * 18 + ['2000']))
                (process / 'statm').write_text(f'10000 {pages} 0 0 0 0 0')

            def proc_path(value):
                text = str(value)
                if text == '/proc':
                    return root
                if text == '/proc/uptime':
                    return root / 'uptime'
                return Path(value)

            with patch.object(ctl, 'Path', side_effect=proc_path), \
                    patch.object(ctl.os, 'sysconf', side_effect=lambda name: 100 if name == 'SC_CLK_TCK' else 4096):
                telemetry = ctl.linux_core_telemetry()
        self.assertEqual(telemetry['core_memory_bytes'], 9000 * 4096)
        self.assertEqual(telemetry['connected_seconds'], 100)


if __name__ == '__main__':
    unittest.main()
