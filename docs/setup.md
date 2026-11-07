# Setup

This document describes the initialization and configuration that must be
completed before operating within this repository.

## Table of Contents

- [Install Dependencies](#install-dependencies)
- [Generate Passphrases](#generate-passphrases)
- [Create a DigitalOcean API Token](#create-a-digitalocean-api-token)
- [Generate an Admin SSH Keypair for First-Boot SSH Access](#generate-an-admin-ssh-keypair-for-first-boot-ssh-access)
- [Generate a Bootstrap Deployment SSH Keypair for Vault Repository Access](#generate-a-bootstrap-deployment-ssh-keypair-for-vault-repository-access)
- [Set Up the Vault Repository](#set-up-the-vault-repository)
- [Set Up the Environment](#set-up-the-environment)
- [Edit Policy Files](#edit-policy-files)
- [Validate Initialization & Configuration](#validate-initialization--configuration)
- [Deploy Initial Environments](#deploy-initial-environments)

## Install Dependencies

Install OpenTofu from the official OpenTofu DNF repository:

```bash
cat <<EOF | sudo tee /etc/yum.repos.d/opentofu.repo
[opentofu]
name=opentofu
baseurl=https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/\$basearch
repo_gpgcheck=0
gpgcheck=1
enabled=1
gpgkey=https://get.opentofu.org/opentofu.gpg https://packages.opentofu.org/opentofu/tofu/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF
sudo rpm --import https://get.opentofu.org/opentofu.gpg
sudo rpm --import https://packages.opentofu.org/opentofu/tofu/gpgkey
sudo dnf install -y tofu
```

Install Ansible, OpenSSL, and local validation tools on the workstation:

```bash
sudo dnf install epel-release
sudo dnf install ansible-core openssl python3-pip
python3 -m pip install --user --upgrade pip
python3 -m pip install --user yamllint
```

Confirm the required commands are available:

```bash
command -v tofu
command -v ansible-vault
command -v openssl
command -v yamllint
```

[Back to top](#setup)

## Generate Passphrases

Generate strong passphrases for OpenTofu state encryption and Ansible Vault.
Use unique values for each workspace or environment.

```bash
openssl rand -hex 48
```

[Back to top](#setup)

## Create a DigitalOcean API Token

Create a DigitalOcean API token for OpenTofu with the narrowest practical
scope for this automation.

| Resource Type | Permissions                         |
| ------------- | ----------------------------------- |
| actions       | read                                |
| certificate   | create, read, delete                |
| domain        | create, read, update, delete        |
| droplet       | create, read, update, delete        |
| firewall      | create, read, update, delete        |
| image         | read                                |
| load_balancer | create, read, update, delete        |
| project       | create, read, update                |
| regions       | read                                |
| sizes         | read                                |
| snapshot      | read                                |
| ssh_key       | create, read, update, delete        |
| tag           | create, read, delete                |
| vpc           | create, read, update, delete        |

[Back to top](#setup)

## Generate an Admin SSH Keypair for First-Boot SSH Access

Generate an admin SSH keypair that will be used for first-boot access and
configuration for new Grayhaven Systems LLC servers. This keypair is temporary
and will be removed from each server during Ansible convergence.

```bash
mkdir -p "$HOME/.ssh"
chmod 0700 "$HOME/.ssh"
ssh-keygen -t ed25519 -C "grayhaven-admin" -f "$HOME/.ssh/id_ed25519"
chmod 0600 "$HOME/.ssh/id_ed25519"
chmod 0644 "$HOME/.ssh/id_ed25519.pub"
```

Do not commit or print the private key.

[Back to top](#setup)

## Generate a Bootstrap Deployment SSH Keypair for Vault Repository Access

Generate a new deployment SSH keypair for bootstrap automation and read-only
access to `grayhaven-vault`. Store the private key in a safe
location under `$HOME` with restrictive ownership and permissions.

OpenTofu passes this keypair to first-boot bootstrap so the active control
bastion can fetch
`grayhaven-vault` and start
initial Ansible convergence. Full convergence then replaces the temporary
first-boot control key with the vault-sourced Ansible control key.

```bash
mkdir -p "$HOME/<safe-key-directory>"
chmod 0700 "$HOME/<safe-key-directory>"
ssh-keygen -t ed25519 -C "grayhaven-vault-deploy" \
  -f "$HOME/<safe-key-directory>/ansible-deploy.key"
chmod 0600 "$HOME/<safe-key-directory>/ansible-deploy.key"
chmod 0644 "$HOME/<safe-key-directory>/ansible-deploy.key.pub"
```

Do not commit or print the private key.

[Back to top](#setup)

## Set Up the Vault Repository

Follow the
[setup instructions](https://github.com/grayhavensystemsllc/grayhaven-vault-example/blob/main/docs/setup.md)
in the
[`grayhaven-vault-example`](https://github.com/grayhavensystemsllc/grayhaven-vault-example)
repository
using the values generated above as applicable for each environment.

[Back to top](#setup)

## Set Up the Environment

Copy the provided sample environment file into your local shell environment,
then edit it appropriately using the values generated above:

```bash
mkdir -p "$HOME/.bashrc.d"
cp docs/examples/grayhaven.env.example "$HOME/.bashrc.d/grayhaven.env"
chmod 0600 "$HOME/.bashrc.d/grayhaven.env"
```

Ensure `$HOME/.bashrc` loads files from `$HOME/.bashrc.d`. Check for an
existing `.bashrc.d` block:

```bash
grep -n '\.bashrc\.d' "$HOME/.bashrc"
```

If no lines are returned, add this block to `$HOME/.bashrc`:

```bash
# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc
```

Edit `$HOME/.bashrc.d/grayhaven.env` using the generated values from above
where applicable, then source the shell configuration:

```bash
source "$HOME/.bashrc"
```

Validate that required variables are defined without printing their values:

```bash
for var in \
  TF_VAR_state_encryption_passphrase_baseline \
  TF_VAR_state_encryption_passphrase_staging \
  TF_VAR_state_encryption_passphrase_prod \
  TF_VAR_do_token \
  TF_VAR_grayhaven_vault_checkout_path \
  TF_VAR_grayhaven_ansible_deploy_public_key \
  TF_VAR_grayhaven_ansible_deploy_private_key \
  TF_VAR_grayhaven_vault_password_staging \
  TF_VAR_grayhaven_vault_password_prod
do
  if [ -n "${!var:-}" ]; then
    printf '\033[32m%s=defined\033[0m\n' "$var"
  else
    printf '\033[31m%s=missing\033[0m\n' "$var"
  fi
done
```

[Back to top](#setup)

## Edit Policy Files

Configure the files in `grayhaven-vault` using the
[file schemas](https://github.com/grayhavensystemsllc/grayhaven-vault-example/blob/main/docs/schema.md).
Use separate `staging` and `main` branch commits for environment configuration.
Baseline reads the shared files from `main`. Environment plans also read
`ansible_control.public_key` from encrypted `vault/bastion.yml` with the
existing environment Vault password.

Commit the vault changes before running OpenTofu. The loader uses the selected
Git ref rather than uncommitted files in the local checkout.

Set `TF_VAR_grayhaven_vault_checkout_path` to that checkout. See
[Policy Files](policy.md) for the configuration file list and
[Infrastructure Naming & Tagging Conventions](naming-tagging-conventions.md)
for generated resource names.

[Back to top](#setup)

## Validate Initialization & Configuration

Confirm the working tree is clean:

```bash
git status --short
```

No files should be listed. At this point, all intended setup changes should be
staged and committed.

Check OpenTofu formatting in the repository checkout:

```bash
tofu fmt -check -recursive
```

Run Yamllint on YAML files in the repository checkout:

```bash
yamllint .
```

[Back to top](#setup)

## Deploy Initial Environments

Install the configuration-reader dependencies, including `ansible-vault`,
and initialize OpenTofu from the repository root:

```bash
python3 -m pip install --requirement requirements.txt
tofu init
```

Deploy baseline first so shared protected resources exist before environment
runtime resources:

```bash
tofu workspace new baseline
tofu plan
tofu apply
```

Deploy staging next and validate it before production:

```bash
tofu workspace new staging
tofu plan
tofu apply
```

Deploy production after staging review is complete:

```bash
tofu workspace new prod
tofu plan
tofu apply
```

Review [Workspaces](workspaces.md), [Operations](operations.md),
[Safety](safety.md), and [Troubleshooting](troubleshooting.md) documentation
for further information.

[Back to top](#setup)
