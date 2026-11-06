# Operations

This document describes routine OpenTofu operations for Grayhaven Systems LLC
infrastructure.

## Table of Contents

- [List Available Workspaces](#list-available-workspaces)
- [Switch Active Workspace](#switch-active-workspace)
- [Provisioning or Updating Infrastructure](#provisioning-or-updating-infrastructure)
- [Backup & Restoration Operations](#backup--restoration-operations)
- [Deploying an Environment with an Ansible Testing Branch](#deploying-an-environment-with-an-ansible-testing-branch)
- [Destroy the Staging Workspace Environment](#destroy-the-staging-workspace-environment)
- [DigitalOcean API Token Rotation](#digitalocean-api-token-rotation)
- [OpenTofu State Encryption Passphrase Rotation](#opentofu-state-encryption-passphrase-rotation)
- [Ansible Vault Passphrase Rotation](#ansible-vault-passphrase-rotation)
- [Bootstrap Deployment SSH Keypair Rotation](#bootstrap-deployment-ssh-keypair-rotation)
- [Bastion Failover](#bastion-failover)
- [Updating Workspace Environment TLS Mode](#updating-workspace-environment-tls-mode)

## List Available Workspaces

To list all available workspaces, from the repository root run:

```bash
tofu workspace list
```

The [Workspaces](workspaces.md) documentation details each supported workspace.

[Back to top](#operations)

## Switch Active Workspace

To change the active workspace, from the repository root run:

```bash
tofu workspace select <workspace>
```

[Back to top](#operations)

## Provisioning or Updating Infrastructure

To provision or update infrastructure:

1. Change to the desired workspace environment.

   ```bash
   tofu workspace select <workspace>
   ```

2. Make changes to this repository and/or adjust configuration. Make any
   relevant adjustments to
   [`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
   and `grayhaven-vault` as
   well. Refer to
   [`grayhaven-vault-example`](https://github.com/grayhavensystemsllc/grayhaven-vault-example)
   for additional information as needed.

3. Run `tofu plan` and review planned changes carefully.

   ```bash
   tofu plan
   ```

4. Run `tofu apply`.

   ```bash
   tofu apply
   ```

5. If you are moving an existing environment deployment from one web host to two
   or more web hosts, from two or more web hosts to one web host, or explicitly
   changing `tls_mode`, manually start the runner from the active control node
   using the
   [manual runner invocation instructions](https://github.com/grayhavensystemsllc/grayhaven-config-ansible/blob/main/docs/operations.md#manual-runner-invocation)
   in the `grayhaven-config-ansible` repository.

It is recommended that all changes to this repository be tested in a `staging`
workspace environment deployment before updating the `prod` workspace
environment.

[Back to top](#operations)

## Backup & Restoration Operations

OpenTofu provisions the servers that run backups, but backup execution,
snapshot inspection, restoration, and stale remote bucket cleanup are managed by
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible).

Use the `grayhaven-backupctl` operations guide for:

- [listing backups](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#listing-backups);
- [creating backups](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#creating-backups);
- [listing backup contents](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#listing-backup-contents);
- [finding backups containing paths](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#finding-backups-containing-paths);
- [restoring to a target directory](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#restoring-to-a-target-directory);
- [restoring in place](https://github.com/grayhavensystemsllc/grayhaven-backupctl/blob/main/docs/operations.md#restoring-in-place).

If remote backups are configured, use the
[`grayhaven-config-ansible` GCS restic bucket cleanup](https://github.com/grayhavensystemsllc/grayhaven-config-ansible/blob/main/docs/operations.md#gcs-restic-bucket-cleanup)
procedure to remove stale remote buckets for decommissioned servers.

[Back to top](#operations)

## Deploying an Environment with an Ansible Testing Branch

To run bootstrap and convergence from a
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
branch other than `main` in `staging`, from the repository root run:

```bash
tofu workspace select staging
tofu plan -var 'grayhaven_config_repo_ref=<branch-name>'
```

Review planned changes carefully, then run this command to update the live
`staging` workspace environment:

```bash
tofu apply -var 'grayhaven_config_repo_ref=<branch-name>'
```

The `grayhaven_config_repo_ref` override is intended to be used with a fresh
`staging` workspace deployment only. If you need to change this value, you must
first destroy the `staging` workspace environment.

Set `grayhaven_config_repo_ref` to a mutable branch name. Do not use a commit
SHA or tag. The bastion's Ansible poller watches the same deployed branch and
starts convergence when that branch advances; immutable refs cannot provide
that behavior.

Production uses the `main` branch of `grayhaven-config-ansible` by default.
For disposable production-shape testing before a config branch is merged, use
the explicit production override:

```bash
tofu workspace select prod
tofu plan \
  -var 'grayhaven_config_repo_ref=<branch-name>' \
  -var 'allow_prod_config_repo_ref_override=true'
```

Review planned changes carefully, then run this command to create the temporary
production-shape environment:

```bash
tofu apply \
  -var 'grayhaven_config_repo_ref=<branch-name>' \
  -var 'allow_prod_config_repo_ref_override=true'
```

Do not use the production override for ordinary production operation. Destroy
the temporary `prod` workspace environment before switching refs or returning
to the default `main` behavior.

[Back to top](#operations)

## Destroy the Staging Workspace Environment

The `staging` workspace environment is meant to be destroyed when not in use.
To destroy the `staging` workspace environment safely, run these commands from
the repository root:

```bash
tofu workspace select staging
tofu plan -destroy
tofu destroy
```

[Back to top](#operations)

## DigitalOcean API Token Rotation

DigitalOcean API token scopes cannot be changed after token creation. If a
token is compromised, expired, or missing a required permission, create a new
token with the
[full documented scope set](setup.md#create-a-digitalocean-api-token) and
rotate the local OpenTofu environment to use the new value.

To rotate the OpenTofu DigitalOcean API token:

1. Create a new DigitalOcean API token using the permissions documented in
   [Setup](setup.md#create-a-digitalocean-api-token), adding or removing any
   desired permissions if applicable.
2. Update `$HOME/.bashrc.d/grayhaven.env`, replacing `TF_VAR_do_token` with
   your new DigitalOcean API token.
3. Reload `grayhaven.env`:

   ```bash
   source "$HOME/.bashrc.d/grayhaven.env"
   ```

4. Confirm the variable is present without printing its value:

   ```bash
   if [ -n "${TF_VAR_do_token:-}" ]; then
     printf '\033[32mTF_VAR_do_token=defined\033[0m\n'
   else
     printf '\033[31mTF_VAR_do_token=missing\033[0m\n'
   fi
   ```

5. Select the `baseline` workspace and run a plan to verify the new
   DigitalOcean API token:

   ```bash
   tofu workspace select baseline
   tofu plan
   ```

   Confirm the plan completes successfully.

6. Delete your old DigitalOcean API token.

If you have added or removed a permission from your DigitalOcean API token,
please update the documented
[DigitalOcean API token scope table](setup.md#create-a-digitalocean-api-token).

[Back to top](#operations)

## OpenTofu State Encryption Passphrase Rotation

To rotate the OpenTofu state encryption passphrase for a given workspace
environment, follow each section in order.

OpenTofu requires state encryption metadata aliases to be literal values in
`state.tf`. State passphrase rotation therefore includes a small reviewed
`state.tf` alias rollover before passphrase variables are changed.

### Prepare Metadata Alias Rollover

Before each rotation, update `state.tf` so the current metadata alias is
incremented and the previous-key fallback points at the alias currently in use.
For example, when rotating from `grayhaven_state_v1` to
`grayhaven_state_v2`, use this shape:

```hcl
key_provider "pbkdf2" "local" {
  passphrase               = local.state_encryption_passphrase
  encrypted_metadata_alias = "grayhaven_state_v2"
}

key_provider "pbkdf2" "previous" {
  passphrase               = local.state_encryption_previous_passphrase
  encrypted_metadata_alias = "grayhaven_state_v1"
}
```

Use the same pattern for later rotations, such as `grayhaven_state_v2` to
`grayhaven_state_v3`. Commit, review, and merge the `state.tf` alias update
before starting the passphrase rotation. Do not reuse an alias for both key
providers in the same configuration. Do not advance the alias generation until
every workspace environment that needs to remain readable has been rewritten to
the current alias.

### Back Up State

Temporarily back up the target workspace environment state and keep the backup
private.

From the repository root, replace `<workspace>` appropriately and run:

```bash
workspace="<workspace>"
backup_dir="$HOME/backups"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$backup_dir"
chmod 0700 "$backup_dir"
tar -czf \
  "$backup_dir/grayhaven-infra-opentofu-${workspace}-state-${timestamp}.tar.gz" \
  "terraform.tfstate.d/${workspace}"
chmod 0600 \
  "$backup_dir/grayhaven-infra-opentofu-${workspace}-state-${timestamp}.tar.gz"
```

### Configure Passphrase Variables

Update `$HOME/.bashrc.d/grayhaven.env`, renaming
`TF_VAR_state_encryption_passphrase_<workspace>` to
`TF_VAR_state_encryption_previous_passphrase_<workspace>`.

Add `TF_VAR_state_encryption_passphrase_<workspace>` with the new encryption
passphrase, then reload `grayhaven.env`:

```bash
source "$HOME/.bashrc.d/grayhaven.env"
```

Validate both variables are present by replacing `<workspace>` appropriately and
running this command:

```bash
workspace="<workspace>"
current_var="TF_VAR_state_encryption_passphrase_${workspace}"
previous_var="TF_VAR_state_encryption_previous_passphrase_${workspace}"

for var_name in "$current_var" "$previous_var"; do
  if [ -n "${!var_name:-}" ]; then
    printf '\033[32m%s=defined\033[0m\n' "$var_name"
  else
    printf '\033[31m%s=missing\033[0m\n' "$var_name"
  fi
done
```

### Rotate State

Select the target workspace:

```bash
tofu workspace select <workspace>
```

Run `tofu plan` to confirm that OpenTofu can read the workspace environment
state with the previous passphrase, then run `tofu apply` to rotate the state
encryption passphrase. Run `tofu apply` even if the plan reports no
infrastructure changes; OpenTofu rewrites the local state with the current
encryption method during apply.

### Remove the Previous Passphrase

Update `$HOME/.bashrc.d/grayhaven.env`, removing
`TF_VAR_state_encryption_previous_passphrase_<workspace>`.

Unset `TF_VAR_state_encryption_previous_passphrase_<workspace>` in your local
shell environment:

```bash
workspace="<workspace>"
unset "TF_VAR_state_encryption_previous_passphrase_${workspace}"
```

Run `tofu plan` again to confirm that OpenTofu can read the workspace
environment state with the new passphrase.

### Rollback

If anything goes wrong with the above steps, rollback by first ensuring that
`TF_VAR_state_encryption_passphrase_<workspace>` in
`$HOME/.bashrc.d/grayhaven.env` is set to the original encryption passphrase,
then restore state by executing the following from the repository root:

```bash
workspace="<workspace>"
backup_file="$HOME/backups/grayhaven-infra-opentofu-${workspace}-state-<timestamp>.tar.gz"

source "$HOME/.bashrc.d/grayhaven.env"
tar -tzf "$backup_file"
tar -xzf "$backup_file"
tofu workspace select "$workspace"
tofu plan
```

### Cleanup

Once the state encryption passphrase has been successfully rotated, the
temporary state backup can be safely removed.

[Back to top](#operations)

## Ansible Vault Passphrase Rotation

To rotate the Ansible Vault encryption passphrase for a given workspace
environment:

1. Update `$HOME/.bashrc.d/grayhaven.env`, updating
   `TF_VAR_grayhaven_vault_password_<workspace>` with the new encryption
   passphrase.
2. Rotate the configuration Ansible Vault passphrase for the correct workspace
   environment by following the
   [vault password rotation documentation](https://github.com/grayhavensystemsllc/grayhaven-vault-example/blob/main/docs/operations.md#vault-password-rotation)
   in the
   [`grayhaven-vault-example`](https://github.com/grayhavensystemsllc/grayhaven-vault-example)
   repository.
3. Rotate the Ansible Vault passphrase for existing resources by following the
   [vault password rotation documentation](https://github.com/grayhavensystemsllc/grayhaven-config-ansible/blob/main/docs/operations.md#vault-password-rotation)
   in the
   [`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
   repository.

Do not discard your original Ansible Vault passphrase until you have
successfully completed the passphrase rotation procedure.

[Back to top](#operations)

## Bootstrap Deployment SSH Keypair Rotation

To rotate the bootstrap deployment SSH keypair:

The bootstrap deployment SSH keypair is shared by all workspace environments.
When rotating it, update the OpenTofu environment variables once, then rotate
the retained vault deployment SSH keypair on every deployed environment that has
existing bastions.

1. Temporarily back up your existing bootstrap deployment SSH keypair and keep
   the backup private.

   Replace the key paths appropriately and run:

   ```bash
   public_key_path="/path/to/ansible-deploy.key.pub"
   private_key_path="/path/to/ansible-deploy.key"
   backup_dir="$HOME/backups"
   timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

   mkdir -p "$backup_dir"
   chmod 0700 "$backup_dir"
   tar -czf \
     "$backup_dir/grayhaven-vault-deployment-ssh-keypair-${timestamp}.tar.gz" \
     "$public_key_path" \
     "$private_key_path"
   chmod 0600 \
     "$backup_dir/grayhaven-vault-deployment-ssh-keypair-${timestamp}.tar.gz"
   ```

2. [Generate a new keypair](setup.md#generate-a-bootstrap-deployment-ssh-keypair-for-vault-repository-access).
3. Add the new deploy public key generated in step 2 as a read-only deploy key
   on the `grayhaven-vault`
   repository through GitHub's website.
4. Update `$HOME/.bashrc.d/grayhaven.env`, ensuring that
   `TF_VAR_grayhaven_ansible_deploy_public_key` and
   `TF_VAR_grayhaven_ansible_deploy_private_key` point to the new keypair.
5. Reload `grayhaven.env`:

   ```bash
   source "$HOME/.bashrc.d/grayhaven.env"
   ```

6. Rotate the retained vault deployment SSH keypair on existing bastions in
   every deployed workspace environment by following the
   [deploy key rotation documentation](https://github.com/grayhavensystemsllc/grayhaven-config-ansible/blob/main/docs/operations.md#deploy-key-rotation)
   in the
   [`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
   repository.

Once the new bootstrap deployment SSH keypair is verified as operational, the
temporary key backup taken in step 1 above and the original keypair can be
safely removed.

[Back to top](#operations)

## Bastion Failover

The active control bastion is selected with `bastions.control_node` in
`grayhaven-vault`'s environment-specific `compute.yml`. Only that bastion
receives the `control-node` tag and runs the scheduled Ansible runner and
poller.

To switch the active control bastion:

1. Ensure the target bastion exists in the vault branch's `compute.yml`.
2. Change `bastions.control_node` to the target bastion key and commit it.
3. Select the target workspace and run `tofu plan`.
4. Confirm the plan only changes the expected DNS/tag relationships.
5. Run `tofu apply`.
6. SSH to the new `bastion.*` target and start a manual configuration run:

```bash
sudo systemctl start grayhaven-ansible-runner.service
```

After convergence, verify the runner and poller timers are enabled only on the
new control bastion by running the following commands on each remaining
bastion:

```bash
systemctl is-enabled grayhaven-ansible-runner.timer
systemctl is-active grayhaven-ansible-runner.timer
systemctl is-enabled grayhaven-ansible-poller.timer
systemctl is-active grayhaven-ansible-poller.timer
```

Remaining bastions still operate as SSH jump points.

Automatic bastion failover is not supported at this time. You must manually
switch the active control bastion.

[Back to top](#operations)

## Updating Workspace Environment TLS Mode

To change the currently active TLS mode for a given workspace environment,
first modify `web.tls_mode` in the vault branch's `compute.yml` and commit it.
Then run the following commands from the infrastructure repository root:

```bash
tofu workspace select <workspace>
tofu plan
```

Review planned changes carefully, then run this command to update the live
workspace environment:

```bash
tofu apply
```

After applying a TLS mode change, manually start the runner from the active
control node so `grayhaven-config-ansible` converges Nginx and firewalld.

Policy documentation details [supported TLS modes](policy.md#compute-policy).

[Back to top](#operations)
