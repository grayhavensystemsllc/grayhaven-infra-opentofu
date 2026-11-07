"""Exercise configuration reads with fictional inputs and bounded command mocks."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

from diagnostics import install

install()
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("vault_reader", ROOT / "scripts/read_vault_config.py")
reader = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = reader
spec.loader.exec_module(reader)

PUBLIC = "ssh-ed25519 QUJDREVGRw== example@example.invalid"
CIPHER = "$ANSIBLE_VAULT;1.1;AES256\nfictional-encrypted-source\n"


class RequestTests(unittest.TestCase):
    def test_read_modes_accept_explicit_inputs_and_empty_public_request(self):
        self.assertEqual(reader.read_request(""), {})
        self.assertEqual(reader.read_request("{}"), {})
        self.assertEqual(reader.read_request('{"read_control_key":"false"}'), {"read_control_key": "false"})
        supplied = {"read_control_key": "true", "vault_password": "fictional-opaque-value"}
        self.assertEqual(reader.read_request(json.dumps(supplied)), supplied)

    def test_invalid_request_types_syntax_modes_and_passwords_are_refused(self):
        for value in [None, 7, [], "not-json", "null", "[]", '"value"']:
            with self.subTest():
                with self.assertRaises(reader.ReaderError):
                    reader.read_request(value)
        for mode in [True, 1, "enabled", None, {}]:
            with self.subTest():
                with self.assertRaises(reader.ReaderError):
                    reader.read_request(json.dumps({"read_control_key": mode}))
        for value in [None, "", 8, [], {}, "x" * 16385]:
            with self.subTest():
                with self.assertRaises(reader.ReaderError):
                    reader.read_request(json.dumps({"read_control_key": "true", "vault_password": value}))


class RefTests(unittest.TestCase):
    def test_supplied_ref_and_paths_determine_returned_content(self):
        paths = {"first": "policy/alpha.yml", "second": "folder/beta.yml"}
        for ref in ["fictional-branch", "fictional/tag", "a" * 40]:
            with self.subTest():
                def run(command, **options):
                    self.assertTrue(options["capture_output"])
                    self.assertTrue(options["text"])
                    return subprocess.CompletedProcess(command, 0, command[-1] + "\n", "")
                with patch.object(reader.subprocess, "run", side_effect=run):
                    result = reader.read_configuration(Path("/fictional/repository"), ref, {}, paths)
                self.assertEqual(result, {
                    **{key: ref + ":" + name + "\n" for key, name in paths.items()},
                    "control_public_key": "",
                })

    def test_git_failures_never_return_command_output(self):
        diagnostic = "fictional-sensitive-diagnostic"
        cases = [
            subprocess.CompletedProcess([], 1, diagnostic, diagnostic),
            subprocess.CompletedProcess([], 0, None, ""),
            OSError(diagnostic),
            subprocess.TimeoutExpired(["git"], 1, output=diagnostic),
        ]
        for response in cases:
            with self.subTest():
                options = {"side_effect": response} if isinstance(response, Exception) else {"return_value": response}
                with patch.object(reader.subprocess, "run", **options):
                    with self.assertRaises(reader.ReaderError) as error:
                        reader.read_ref_file(Path("/fictional/repository"), "fake-ref", "alpha.yml")
                self.assertNotIn(diagnostic, str(error.exception))

    def test_public_only_requests_do_not_decrypt(self):
        with patch.object(reader, "read_ref_file", return_value="fictional content"), \
             patch.object(reader, "public_key_from_encrypted") as decrypt:
            result = reader.read_configuration(Path("/fictional/repository"), "fake-ref", {}, {"entry": "alpha.yml"})
        decrypt.assert_not_called()
        self.assertEqual(result, {"entry": "fictional content", "control_public_key": ""})

    def test_selected_public_key_is_added_without_other_secret_fields(self):
        supplied = {"read_control_key": "true", "vault_password": "fictional-opaque-value"}
        def read(checkout, ref, name):
            self.assertEqual(checkout, Path("/fictional/repository"))
            self.assertEqual(ref, "chosen-ref")
            return CIPHER if name == "vault/bastion.yml" else "fictional policy"
        with patch.object(reader, "read_ref_file", side_effect=read), \
             patch.object(reader, "public_key_from_encrypted", return_value=PUBLIC) as decrypt:
            result = reader.read_configuration(Path("/fictional/repository"), "chosen-ref", supplied, {"policy": "alpha.yml"})
        decrypt.assert_called_once_with(CIPHER, supplied["vault_password"])
        self.assertEqual(result, {"policy": "fictional policy", "control_public_key": PUBLIC})
        self.assertNotIn("vault_password", result)
        self.assertNotIn("private_key", result)


class EncryptedKeyTests(unittest.TestCase):
    def decrypt(self, plaintext, public_key=PUBLIC, password="fictional-opaque-value"):
        captured = {}
        def command(arguments, **options):
            self.assertEqual(arguments[:2], ["ansible-vault", "view"])
            self.assertNotIn(password, arguments)
            self.assertNotIn("env", options)
            descriptor = options["pass_fds"][0]
            self.assertEqual(arguments[3], f"/proc/self/fd/{descriptor}")
            self.assertEqual(os.read(descriptor, 32768), (password + "\n").encode())
            path = Path(arguments[-1])
            self.assertEqual(path.read_text(), CIPHER)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            captured["path"] = path
            return subprocess.CompletedProcess(arguments, 0, plaintext, "")
        with patch.object(reader.subprocess, "run", side_effect=command):
            result = reader.public_key_from_encrypted(CIPHER, password)
        self.assertFalse(captured["path"].exists())
        self.assertEqual(result, public_key)
        return result

    def test_only_the_selected_public_key_is_returned(self):
        for key in [
            PUBLIC,
            "ssh-rsa QUJDREVGRw== example@example.invalid",
            "ecdsa-sha2-nistp256 QUJDREVGRw== example@example.invalid",
        ]:
            with self.subTest():
                text = json.dumps({
                    "ansible_control": {"public_key": "  " + key + "\n", "private_key": "fictional-private-value"},
                    "other": {"value": "fictional-unrelated-value"},
                })
                result = self.decrypt(text, public_key=key)
                self.assertNotIn("fictional-private-value", result)
                self.assertNotIn("fictional-unrelated-value", result)

    def test_unicode_and_space_password_delivery_is_preserved(self):
        self.decrypt(json.dumps({"ansible_control": {"public_key": PUBLIC}}), password="fictional å value")

    def test_plaintext_source_is_refused_without_running_decryption(self):
        with patch.object(reader.subprocess, "run") as command:
            with self.assertRaises(reader.ReaderError):
                reader.public_key_from_encrypted("fictional plaintext", "fictional-opaque-value")
        command.assert_not_called()

    def test_failed_decryption_and_command_errors_do_not_leak_diagnostics(self):
        diagnostic = "fictional-sensitive-diagnostic"
        cases = [
            subprocess.CompletedProcess([], 1, diagnostic, diagnostic),
            OSError(diagnostic),
            subprocess.TimeoutExpired(["ansible-vault"], 1, output=diagnostic),
        ]
        for response in cases:
            with self.subTest():
                options = {"side_effect": response} if isinstance(response, Exception) else {"return_value": response}
                with patch.object(reader.subprocess, "run", **options):
                    with self.assertRaises(reader.ReaderError) as error:
                        reader.public_key_from_encrypted(CIPHER, "fictional-opaque-value")
                self.assertNotIn(diagnostic, str(error.exception))

    def test_malformed_documents_missing_fields_and_invalid_key_types_are_refused(self):
        documents = [
            "unclosed: [",
            "!!python/object:fictional {}",
            "null",
            "[]",
            "{}",
            '{"ansible_control":null}',
            '{"ansible_control":[]}',
            '{"ansible_control":{}}',
            '{"ansible_control":{"public_key":null}}',
            '{"ansible_control":{"public_key":42}}',
        ]
        for document in documents:
            with self.subTest():
                with patch.object(reader.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, document, "")):
                    with self.assertRaises(reader.ReaderError):
                        reader.public_key_from_encrypted(CIPHER, "fictional-opaque-value")

    def test_invalid_public_key_forms_are_refused(self):
        for key in ["", "  ", "not-a-key", "PRIVATE MATERIAL", PUBLIC + "\n" + PUBLIC, 'command="example" ' + PUBLIC]:
            with self.subTest():
                document = json.dumps({"ansible_control": {"public_key": key}})
                with patch.object(reader.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, document, "")):
                    with self.assertRaises(reader.ReaderError):
                        reader.public_key_from_encrypted(CIPHER, "fictional-opaque-value")

    def test_descriptor_creation_and_incomplete_writes_fail_safely(self):
        with patch.object(reader.os, "memfd_create", side_effect=OSError("fictional diagnostic")):
            with self.assertRaises(reader.ReaderError):
                reader.public_key_from_encrypted(CIPHER, "fictional-opaque-value")
        with patch.object(reader.os, "write", return_value=0):
            with self.assertRaises(reader.ReaderError):
                reader.public_key_from_encrypted(CIPHER, "fictional-opaque-value")


if __name__ == "__main__":
    unittest.main()
