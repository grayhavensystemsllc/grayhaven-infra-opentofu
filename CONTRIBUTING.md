# Contributing

This document is intended for Grayhaven Systems LLC employees and assumes that
this repository has been [initialized and configured](docs/setup.md)
appropriately.

If you are not a Grayhaven Systems LLC employee, we still welcome your support
and contribution.

## Table of Contents

- [Development Setup](#development-setup)
- [Workflow](#workflow)
- [Local Validation](#local-validation)
- [Pull Requests](#pull-requests)
- [Documentation Guidelines](#documentation-guidelines)

## Development Setup

Install verification dependencies:

```bash
sudo dnf install ShellCheck npm
python3 -m pip install actionlint-py
npm config set prefix "$HOME/.local"
npm install --global markdownlint-cli2
printf '%s\n' "$PATH" | grep -qE "(^|:)$HOME/\\.local/bin(:|$)" || \
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
```

[Back to top](#contributing)

## Workflow

1. Create a GitHub issue.
2. Create a feature branch for the issue.
3. Sign all commits and reference the issue number.
4. Validate changes locally.
5. Push the feature branch and open a ready-for-review pull request targeting
   the `main` branch. Direct pushes to `main` are forbidden.
6. Resolve every review conversation before the pull request is merged.
7. Reference or close the issue number in the pull request as appropriate for
   code review and merge.

[Back to top](#contributing)

## Local Validation

Validate formatting and syntax from the repository root:

```bash
tofu fmt -check -recursive
shellcheck scripts/read-vault-config
python3 tests/test_read_vault_config.py
yamllint .
markdownlint-cli2 "**/*.md" "!.terraform/**"
```

If GitHub Actions are changed, validate with:

```bash
actionlint
```

Run the OpenTofu test suite locally from a temporary state-free copy of this
repository:

```bash
tmpdir="$(mktemp -d /tmp/grayhaven-infra-validate.XXXXXX)"

cleanup() {
  if [ -n "$tmpdir" ] && [ -d "$tmpdir" ]; then
    find "$tmpdir" -type f -delete
    find "$tmpdir" -depth -type d -empty -delete
  fi
}

trap cleanup EXIT

rsync -a \
  --exclude '.git' \
  --exclude '.terraform' \
  --exclude 'terraform.tfstate*' \
  --exclude 'terraform.tfstate.d' \
  --exclude '.state-backups' \
  ./ "$tmpdir"/

cd "$tmpdir"
tofu init -backend=false
tofu validate

export TF_VAR_state_encryption_passphrase_baseline='offline-test-baseline-state-passphrase'
export TF_VAR_state_encryption_passphrase_staging='offline-test-staging-state-passphrase'
export TF_VAR_state_encryption_passphrase_prod='offline-test-prod-state-passphrase'

tofu workspace new baseline
tofu test -filter=tests/baseline.tftest.hcl -no-color

tofu workspace new staging
tofu test -filter=tests/staging.tftest.hcl -no-color

tofu workspace new prod
tofu test -filter=tests/prod.tftest.hcl -no-color
```

The [OpenTofu test suite documentation](docs/opentofu-test-suite.md) details
how the test suite is designed and operates.

Before committing changes, also check the current diff for whitespace errors:

```bash
git diff --check
```

[Back to top](#contributing)

## Pull Requests

Pull requests must meet all of these requirements to be merged:

- Reference or close a GitHub issue as appropriate.
- Contain signed commits.
- Have no open review conversations.
- Be ready for review; do not leave the pull request as a draft.
- Pass exactly these required checks: `Offline Plan Tests` and `Validate`.
- Document all changes appropriately.

The `main` branch forbids direct pushes. Do not bypass required checks or other
branch protections. Merge pull requests with squash only; merge commits and
rebase merges are not allowed. Automatic feature-branch deletion is disabled,
so manually delete the feature branch after the pull request is merged.

[Back to top](#contributing)

## Documentation Guidelines

Keep public documentation factual and operational. This repository demonstrates
how Grayhaven Systems LLC manages its own infrastructure; it is not a generic
deployment template.

Document safety boundaries, workspace assumptions, and non-obvious
implementation decisions. Avoid comments that merely restate straightforward
OpenTofu resources.

[Back to top](#contributing)
