import contextlib
import io
import subprocess
import unittest
from unittest.mock import MagicMock, call, patch

from tools.package_lan_android import run_flutter_build


def build_process(output, returncode):
    process = MagicMock()
    process.__enter__.return_value = process
    process.stdout = io.StringIO(output)
    process.wait.return_value = returncode
    return process


class AndroidBuildRetryTest(unittest.TestCase):
    command = ["flutter", "build", "apk", "--debug"]

    def test_transient_download_failure_recovers_after_backoff(self):
        for error in (
            "Received status code 429 from server: Too Many Requests",
            "Received status code 503 from server: Service Unavailable",
            "Could not GET dependency: Read timed out",
        ):
            with self.subTest(error=error):
                with patch("tools.package_lan_android.subprocess.Popen") as run:
                    run.side_effect = [build_process(error, 1), build_process("APK built\n", 0)]
                    with patch("tools.package_lan_android.time.sleep") as sleep:
                        with contextlib.redirect_stdout(io.StringIO()) as log:
                            run_flutter_build(self.command, network_retries=2)
                        sleep.assert_called_once_with(30)
                        self.assertEqual(run.call_count, 2)
                        self.assertIn(error, log.getvalue())
                        self.assertIn("APK built", log.getvalue())

    def test_compilation_and_authentication_errors_fail_without_retry(self):
        for error in ("Compilation error: unresolved reference", "Received status code 401"):
            with self.subTest(error=error):
                with patch("tools.package_lan_android.subprocess.Popen") as run:
                    run.return_value = build_process(error, 1)
                    with patch("tools.package_lan_android.time.sleep") as sleep:
                        with contextlib.redirect_stdout(io.StringIO()):
                            with self.assertRaises(subprocess.CalledProcessError):
                                run_flutter_build(self.command, network_retries=2)
                        self.assertEqual(run.call_count, 1)
                        sleep.assert_not_called()

    def test_persistent_rate_limit_stops_at_retry_budget(self):
        with patch("tools.package_lan_android.subprocess.Popen") as run:
            run.side_effect = [build_process("Received status code 429", 1) for _ in range(3)]
            with patch("tools.package_lan_android.time.sleep") as sleep:
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(subprocess.CalledProcessError) as failure:
                        run_flutter_build(self.command, network_retries=2)
                self.assertEqual(failure.exception.returncode, 1)
                self.assertEqual(run.call_count, 3)
                self.assertEqual(sleep.call_args_list, [call(30), call(60)])

    def test_new_compilation_error_does_not_reuse_previous_network_error(self):
        with patch("tools.package_lan_android.subprocess.Popen") as run:
            run.side_effect = [
                build_process("Received status code 429", 1),
                build_process("Compilation failed", 2),
            ]
            with patch("tools.package_lan_android.time.sleep") as sleep:
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(subprocess.CalledProcessError) as failure:
                        run_flutter_build(self.command, network_retries=2)
                self.assertEqual(failure.exception.returncode, 2)
                self.assertEqual(run.call_count, 2)
                sleep.assert_called_once_with(30)

    def test_default_local_build_does_not_retry(self):
        with patch("tools.package_lan_android.subprocess.Popen") as run:
            run.return_value = build_process("Received status code 429", 1)
            with patch("tools.package_lan_android.time.sleep") as sleep:
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaises(subprocess.CalledProcessError):
                        run_flutter_build(self.command)
                sleep.assert_not_called()


if __name__ == "__main__":
    unittest.main()
