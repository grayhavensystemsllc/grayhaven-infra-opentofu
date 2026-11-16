"""Exercise bootstrap release handling and notification transport with invented inputs."""

from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from diagnostics import install

install()
spec = importlib.util.spec_from_file_location("bootstrap_host", Path(__file__).resolve().parents[1] / "scripts/bootstrap_host.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


def configuration():
    return {
        "os_release": "12.4", "timezone": "UTC", "hostname": "node.example.invalid",
        "environment": "fictional", "failure_color": 123,
        "repository": "https://example.invalid/repository.git", "ref": "topic",
        "webhook": "https://discord.com/api/webhooks/fixture/fixture",
    }


class ReleaseTests(unittest.TestCase):
    def test_numeric_release_order_and_invalid_inputs(self):
        self.assertLess(bootstrap.release_version("12.9"), bootstrap.release_version("12.10"))
        for value in [None, 12, "12", "12.4.1", " 12.4", "12.4\n", "a.b"]:
            with self.subTest():
                with self.assertRaises(bootstrap.BootstrapError):
                    bootstrap.release_version(value)

    def test_pin_precedes_commands_for_equal_or_older_images(self):
        for installed in ["12.3", "12.4"]:
            with self.subTest(), tempfile.TemporaryDirectory() as folder:
                target = Path(folder) / "vars/releasever"
                config = configuration()
                def run(command, **options):
                    self.assertEqual(target.read_text(), config["os_release"] + "\n")
                    self.assertEqual(target.stat().st_mode & 0o777, 0o644)
                    self.assertTrue(options["check"])
                with patch.object(bootstrap.platform, "freedesktop_os_release", return_value={"VERSION_ID": installed}), \
                     patch.object(bootstrap.subprocess, "run", side_effect=run) as commands:
                    bootstrap.prepare(config, target)
                self.assertEqual(commands.call_count, 2)
                self.assertIn("--releasever=" + config["os_release"], commands.call_args_list[0].args[0])
                self.assertIn(config["repository"], commands.call_args_list[1].args[0])
                self.assertIn(config["ref"], commands.call_args_list[1].args[0])

    def test_newer_image_stops_before_writes_and_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "vars/releasever"
            with patch.object(bootstrap.platform, "freedesktop_os_release", return_value={"VERSION_ID": "12.5"}), \
                 patch.object(bootstrap.subprocess, "run") as commands:
                with self.assertRaises(bootstrap.BootstrapError):
                    bootstrap.prepare(configuration(), target)
            commands.assert_not_called()
            self.assertFalse(target.exists())


class NotificationTests(unittest.TestCase):
    def test_payload_uses_supplied_identity_and_protects_transport(self):
        config = configuration()
        for status in [0, 7]:
            with self.subTest(), patch.object(bootstrap, "datetime") as clock, \
                 patch.object(bootstrap.subprocess, "run", return_value=subprocess.CompletedProcess([], status)) as command:
                clock.now.return_value = datetime(2044, 7, 1, 14, 3, tzinfo=timezone.utc)
                self.assertEqual(bootstrap.notify(config), status == 0)
                self.assertTrue(all(config["webhook"] not in part for part in command.call_args.args[0]))
                self.assertTrue(command.call_args.kwargs["capture_output"])
                lines = command.call_args.kwargs["input"].splitlines()
                self.assertTrue(json.loads(lines[0].removeprefix("url = ")) == config["webhook"])
                payload = json.loads(json.loads(lines[2].removeprefix("data = ")))
                embed = payload["embeds"][0]
                self.assertEqual(embed["color"], config["failure_color"])
                self.assertIn(config["hostname"], embed["description"])
                self.assertIn(config["environment"], embed["description"])
                self.assertIn("2044-07-01 2:03 PM UTC", embed["description"])

    def test_transport_and_configuration_errors_return_failure(self):
        for error in [OSError(), subprocess.TimeoutExpired("fixture", 1)]:
            with self.subTest(), patch.object(bootstrap.subprocess, "run", side_effect=error):
                self.assertFalse(bootstrap.notify(configuration()))
        for config in [{}, {"timezone": "missing/zone"}, {"timezone": 3}]:
            with self.subTest():
                self.assertFalse(bootstrap.notify(config))

    def test_atomic_marker_prevents_duplicate_delivery(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(bootstrap, "notify", return_value=True) as notify:
            marker = Path(folder) / "sent"
            self.assertTrue(bootstrap.notify_once(configuration(), marker))
            self.assertFalse(bootstrap.notify_once(configuration(), marker))
            self.assertEqual(notify.call_count, 1)


class EntryTests(unittest.TestCase):
    def test_success_consumes_config(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(configuration()))
            with patch.object(bootstrap, "prepare") as prepare, patch.object(bootstrap, "notify_once") as notify:
                self.assertEqual(bootstrap.main(path), 0)
            self.assertEqual(prepare.call_count, 1)
            notify.assert_not_called()
            self.assertFalse(path.exists())

    def test_errors_remain_failed_even_if_notification_cannot_be_sent(self):
        errors = [bootstrap.BootstrapError(), OSError(), ValueError(), TypeError(), KeyError(), subprocess.CalledProcessError(1, "fixture")]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            path.write_text(json.dumps(configuration()))
            for error in errors:
                with self.subTest(), patch.object(bootstrap, "prepare", side_effect=error), \
                     patch.object(bootstrap, "notify_once", side_effect=OSError()) as notify, \
                     patch.object(bootstrap.sys, "stderr"):
                    self.assertEqual(bootstrap.main(path), 1)
                    self.assertEqual(notify.call_count, 1)
            path.write_text("[")
            with patch.object(bootstrap, "notify_once"), patch.object(bootstrap.sys, "stderr"):
                self.assertEqual(bootstrap.main(path), 1)


if __name__ == "__main__":
    unittest.main()
