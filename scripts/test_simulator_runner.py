"""Check the runner without starting an app or a simulator."""

import sys
import time
import unittest
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import Mock, patch

from run_simulator_tests import run, stop


class SimulatorRunnerTests(unittest.TestCase):
    def test_success_returns_zero(self):
        self.assertEqual(run([sys.executable, "-c", "print('Tests pass')"]), 0)

    def test_failure_keeps_its_status(self):
        self.assertEqual(run([sys.executable, "-c", "raise SystemExit(7)"]), 7)

    def test_crash_marker_stops_a_running_process(self):
        code = "import time; print('Restarting after unexpected exit, crash, or test timeout', flush=True); time.sleep(30)"
        started = time.monotonic()
        self.assertEqual(run([sys.executable, "-c", code]), 1)
        self.assertLess(time.monotonic() - started, 10)

    def test_stop_kills_a_child_after_its_parent_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / "ready"
            written = Path(directory) / "written"
            child = ("import signal, time; from pathlib import Path; "
                     "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                     f"Path({str(ready)!r}).touch(); time.sleep(0.5); Path({str(written)!r}).touch()")
            parent = f"import subprocess, sys; subprocess.Popen([sys.executable, '-c', {child!r}])"
            process = subprocess.Popen([sys.executable, "-c", parent], start_new_session=True)
            try:
                process.wait(timeout=3)
                deadline = time.monotonic() + 3
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(ready.exists())
                stop(process, timeout=0.1)
                time.sleep(0.5)
                self.assertFalse(written.exists())
            finally:
                stop(process, timeout=0.1)

    def test_stop_accepts_an_already_exited_process(self):
        process = subprocess.Popen([sys.executable, "-c", "pass"], start_new_session=True)
        process.wait(timeout=3)
        stop(process, timeout=0.1)

    def test_permission_error_allows_only_exited_group_members(self):
        process = Mock(pid=123)
        for rows in ["", "999 S\n123 Z\n"]:
            with patch("run_simulator_tests.os.killpg", side_effect=PermissionError), \
                 patch("run_simulator_tests.subprocess.check_output", return_value=rows):
                stop(process)
        self.assertEqual(process.wait.call_count, 2)

    def test_permission_error_does_not_hide_a_live_group_member(self):
        process = Mock(pid=123)
        with patch("run_simulator_tests.os.killpg", side_effect=PermissionError), \
             patch("run_simulator_tests.subprocess.check_output", return_value="123 Z\n123 S\n999 S\n"):
            with self.assertRaises(PermissionError):
                stop(process)
        process.wait.assert_not_called()


if __name__ == "__main__":
    unittest.main()
