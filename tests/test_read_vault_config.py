"""Read committed configuration from fictional vault refs."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "config_yml": "config.yml",
    "firewall_yml": "firewall.yml",
    "infrastructure_yml": "infrastructure.yml",
    "compute_yml": "compute.yml",
    "operations_yml": "operations.yml",
    "dns_yml": "dns.yml",
    "baseline_dns_yml": "baseline/dns.yml",
    "ssh_keys_yml": "baseline/ssh-keys.yml",
}


class VaultConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "fixture-vault"
        self.repo.mkdir()
        self.env = {
            "PATH": os.defpath,
            "HOME": self.temp.name,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "LANG": "C.UTF-8",
        }
        self.git("init", "--initial-branch=main")
        self.values = {}
        for branch in ("main", "staging"):
            if branch == "staging":
                self.git("switch", "-c", branch)
            expected = {}
            for key, name in FILES.items():
                path = self.repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                value = "---\nfixture: " + branch + "-" + key + "-β\n"
                path.write_text(value)
                expected[key] = value
            self.git("add", ".")
            self.git("-c", "user.name=Fixture Author", "-c", "user.email=fixture@example.invalid",
                     "-c", "commit.gpgsign=false", "commit", "-m", "Fixture configuration")
            self.values[branch] = expected

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.repo, env=self.env,
                              text=True, capture_output=True, check=True)

    def read(self, *arguments):
        return subprocess.run([str(ROOT / "scripts/read-vault-config"), *map(str, arguments)],
                              env=self.env, text=True, capture_output=True)

    def test_selected_refs_ignore_the_working_tree_and_preserve_content(self):
        (self.repo / "config.yml").write_text("uncommitted fixture content\n")
        for branch in ("main", "staging"):
            with self.subTest(branch=branch):
                result = self.read(self.repo, branch)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), self.values[branch])

    def test_invalid_arguments_repositories_refs_and_missing_files_fail(self):
        for arguments in ((), (self.repo,), (self.repo, "main", "extra"),
                          (self.repo / "absent", "main"), (self.repo, ""),
                          (self.repo, "missing-ref")):
            with self.subTest(arguments=arguments):
                self.assertNotEqual(self.read(*arguments).returncode, 0)
        self.git("rm", "compute.yml")
        self.git("-c", "user.name=Fixture Author", "-c", "user.email=fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-m", "Missing fixture file")
        self.assertNotEqual(self.read(self.repo, "staging").returncode, 0)


if __name__ == "__main__":
    unittest.main()
