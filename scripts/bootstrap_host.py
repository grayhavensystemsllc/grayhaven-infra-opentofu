#!/usr/bin/env python3
"""Prepare an approved operating system release before Ansible bootstrap."""

from datetime import datetime
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
from zoneinfo import ZoneInfo


class BootstrapError(Exception):
    """Bootstrap stopped without disclosing configuration values."""


def release_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]+\.[0-9]+", value):
        raise BootstrapError("An approved major and minor release is required.")
    return tuple(int(part) for part in value.split("."))


def prepare(config, release_file=Path("/etc/dnf/vars/releasever")):
    approved = config["os_release"]
    if release_version(platform.freedesktop_os_release()["VERSION_ID"]) > release_version(approved):
        raise BootstrapError("The base image is newer than the approved release.")
    release_file.parent.mkdir(parents=True, exist_ok=True)
    release_file.write_text(approved + "\n")
    release_file.chmod(0o644)
    subprocess.run(
        ["dnf", "--assumeyes", "--releasever=" + approved, "--disablerepo=epel*",
         "install", "ansible-core", "git"], check=True,
    )
    subprocess.run(
        ["ansible-pull", "--url", config["repository"], "--checkout", config["ref"],
         "--inventory", "localhost,", "--connection", "local", "--extra-vars",
         "@/etc/grayhaven/bootstrap/bootstrap-vars.yml", "playbooks/bootstrap.yml"],
        check=True,
    )


def notify(config):
    try:
        stamp = datetime.now(ZoneInfo(config["timezone"])).strftime("%Y-%m-%d %-I:%M %p %Z")
        payload = {"embeds": [{
            "title": "Ansible Configuration Failed - Please Investigate",
            "description": config["hostname"] + "\n\nEnvironment: " + config["environment"] + "\n" + stamp,
            "color": config["failure_color"],
        }]}
        # Keep the webhook and payload off the command line and captured output.
        curl_config = "url = " + json.dumps(config["webhook"]) + "\n"
        curl_config += "header = \"Content-Type: application/json\"\n"
        curl_config += "data = " + json.dumps(json.dumps(payload)) + "\n"
        result = subprocess.run(
            ["curl", "--fail", "--silent", "--show-error", "--retry", "2",
             "--max-time", "15", "--config", "-"],
            input=curl_config, capture_output=True, text=True, timeout=60, check=False,
        )
        return result.returncode == 0
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        return False


def notify_once(config, marker=Path("/run/grayhaven-bootstrap-failure-notified")):
    try:
        with marker.open("x"):
            pass
    except FileExistsError:
        return False
    return notify(config)


def main(path=Path("/etc/grayhaven/bootstrap/config.json")):
    config = {}
    try:
        config = json.loads(path.read_text())
        prepare(config)
        path.unlink()
        return 0
    except (BootstrapError, OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        print("Bootstrap failed.", file=sys.stderr)
        try:
            notify_once(config)
        except OSError:
            pass
        return 1


if __name__ == "__main__":  # pragma: no cover - command entry point
    raise SystemExit(main())
