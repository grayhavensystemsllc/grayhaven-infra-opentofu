#!/usr/bin/env python3
"""Read committed Vault configuration and an explicitly selected public key."""

from __future__ import annotations

from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import yaml

FILES = {
    "config_yml": "config.yml",
    "server_configuration_yml": "server_configuration.yml",
    "ansible_yml": "ansible.yml",
    "observability_yml": "grafana/observability.yml",
    "firewall_yml": "policy/firewall.yml",
    "infrastructure_yml": "policy/infrastructure.yml",
    "compute_yml": "policy/compute.yml",
    "dns_yml": "policy/dns.yml",
    "baseline_dns_yml": "policy/baseline/dns.yml",
    "ssh_keys_yml": "policy/baseline/ssh-keys.yml",
}


class ReaderError(Exception):
    """A configuration read failed without disclosing supplied values."""


def read_request(text: str) -> dict:
    if not isinstance(text, str):
        raise ReaderError("Invalid configuration-reader request.")
    try:
        request = json.loads(text or "{}")
    except (ValueError, TypeError):
        raise ReaderError("Invalid configuration-reader request.") from None
    if not isinstance(request, dict):
        raise ReaderError("Configuration-reader request must be an object.")
    if request.get("read_control_key", "false") not in ("true", "false"):
        raise ReaderError("Invalid public-key selection.")
    if request.get("read_control_key") == "true":
        password = request.get("vault_password")
        if not isinstance(password, str) or not password or len(password) > 16384:
            raise ReaderError("A Vault password is required for the public-key read.")
    return request


def read_ref_file(checkout: Path, ref: str, name: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(checkout), "show", f"{ref}:{name}"],
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        raise ReaderError("Unable to read committed Vault configuration.") from None
    if result.returncode or not isinstance(result.stdout, str):
        raise ReaderError("Unable to read committed Vault configuration.")
    return result.stdout


@contextmanager
def password_descriptor(password: str):
    descriptor = os.memfd_create("vault-reader-password", os.MFD_CLOEXEC)
    try:
        os.fchmod(descriptor, 0o600)
        value = (password + "\n").encode()
        if os.write(descriptor, value) != len(value):
            raise ReaderError("Unable to prepare the Vault password descriptor.")
        os.lseek(descriptor, 0, os.SEEK_SET)
        yield descriptor
    finally:
        os.close(descriptor)


def configuration_from_encrypted(ciphertext: str, password: str) -> dict:
    if not ciphertext.startswith("$ANSIBLE_VAULT;"):
        raise ReaderError("The bootstrap source must be encrypted.")
    try:
        with tempfile.TemporaryDirectory(prefix="vault-reader-") as directory:
            cipher_path = Path(directory) / "bastion.enc"
            descriptor = os.open(cipher_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as destination:
                destination.write(ciphertext)
            with password_descriptor(password) as secret_fd:
                result = subprocess.run(
                    ["ansible-vault", "view", "--vault-password-file",
                     f"/proc/self/fd/{secret_fd}", str(cipher_path)],
                    pass_fds=(secret_fd,), capture_output=True, text=True,
                    timeout=30, check=False,
                )
            if result.returncode:
                raise ReaderError("Unable to decrypt the bootstrap source.")
            values = yaml.safe_load(result.stdout)
            if not isinstance(values, dict):
                raise ReaderError("Invalid bootstrap configuration.")
            return values
    except ReaderError:
        raise
    except (OSError, ValueError, TypeError, yaml.YAMLError, subprocess.SubprocessError):
        raise ReaderError("Unable to read bootstrap configuration.") from None


def public_key_from_configuration(values: dict) -> str:
    try:
        public_key = values["ansible_control"]["public_key"]
        if not isinstance(public_key, str):
            raise ReaderError("The control public key must be a string.")
        public_key = public_key.strip()
        if not re.fullmatch(
            r"(ssh-ed25519|ssh-rsa|ecdsa-sha2-[A-Za-z0-9-]+) [A-Za-z0-9+/=]+(?: [^\r\n]+)?",
            public_key,
        ):
            raise ReaderError("The control public key is invalid.")
        return public_key
    except (KeyError, TypeError):
        raise ReaderError("Unable to read the bootstrap public key.") from None


def public_key_from_encrypted(ciphertext: str, password: str) -> str:
    return public_key_from_configuration(configuration_from_encrypted(ciphertext, password))


def notification_from_configuration(values: dict, automation_text: str) -> str:
    try:
        selector = yaml.safe_load(automation_text)["ansible"]["notifications"]["environment"]
        webhook = values["discord_webhooks"][selector]
        if not isinstance(webhook, str) or not re.fullmatch(
            r"https://(?:discord.com|discordapp.com)/api/webhooks/[^\s\"\r\n]+", webhook,
        ):
            raise ReaderError("Invalid bootstrap notification configuration.")
        return webhook
    except (KeyError, TypeError, yaml.YAMLError):
        raise ReaderError("Unable to read bootstrap notification configuration.") from None


def read_configuration(checkout: Path, ref: str, request: dict, paths=None) -> dict[str, str]:
    result = {
        key: read_ref_file(checkout, ref, name)
        for key, name in (FILES if paths is None else paths).items()
    }
    result["control_public_key"] = ""
    result["bootstrap_discord_webhook"] = ""
    if request.get("read_control_key") == "true":
        encrypted = read_ref_file(checkout, ref, "vault/bastion.yml")
        values = configuration_from_encrypted(encrypted, request["vault_password"])
        result["control_public_key"] = public_key_from_configuration(values)
        result["bootstrap_discord_webhook"] = notification_from_configuration(values, result["ansible_yml"])
    return result


def main() -> int:  # pragma: no cover - command entry point
    try:
        request_text = sys.stdin.read(65537)
        if len(request_text) > 65536:
            raise ReaderError("Configuration-reader request is too large.")
        request = read_request(request_text)
        values = read_configuration(Path(sys.argv[1]), sys.argv[2], request)
        print(json.dumps(values))
        return 0
    except (ReaderError, IndexError):
        print("Vault configuration could not be read.", file=sys.stderr)
        return 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
