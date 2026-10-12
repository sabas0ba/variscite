"""Check command ordering and false-success rejection without running Linux."""

import pathlib
import subprocess
import sys
import unittest


DRIVER = pathlib.Path(__file__).resolve().parents[1] / "scripts/linux_console_test.py"
CONSOLE = r'''
import sys
print("userspace is alive\nveryl$ ", end="", flush=True)
assert input() == "mandel"
print("Mandelbrot set (Q16.16\nveryl$ ", end="", flush=True)
assert input() == "donut"
print("donut: 24 frames rendered\nveryl$ ", end="", flush=True)
assert input() == "poweroff"
print("reboot: Power down\n[tb] SYSCON poweroff", flush=True)
'''


class LinuxConsoleTest(unittest.TestCase):
    def run_console(self, source):
        return subprocess.run(
            [sys.executable, str(DRIVER), sys.executable, "-c", source],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
        )

    def test_command_order_and_complete_run(self):
        result = self.run_console(CONSOLE)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"[linux-console] PASS", result.stdout)

    def test_clean_exit_without_boot_is_failure(self):
        result = self.run_console("print('[tb] SYSCON poweroff')")
        self.assertNotEqual(result.returncode, 0)

    def test_missing_application_completion_is_failure(self):
        source = CONSOLE.split('assert input() == "donut"')[0]
        source += 'print("veryl$ ", end="", flush=True)\n'
        result = self.run_console(source)
        self.assertNotEqual(result.returncode, 0)

    def test_failed_process_after_all_markers_is_failure(self):
        result = self.run_console(CONSOLE + "sys.exit(1)\n")
        self.assertNotEqual(result.returncode, 0)

    def test_prompt_before_application_completion_is_failure(self):
        # Regression for the unavailable RV32 wait4: /init resumed while the
        # child was still rendering. That early prompt is not completion.
        source = CONSOLE.split('print("donut:')[0]
        source += 'print("veryl$ \\ndonut: 24 frames rendered", flush=True)\n'
        result = self.run_console(source)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
