variable "state_encryption_passphrase_baseline" {
  description = "Passphrase used for local OpenTofu state encryption in the baseline workspace."
  type        = string
  sensitive   = true
}

variable "state_encryption_passphrase_staging" {
  description = "Passphrase used for local OpenTofu state encryption in the staging workspace."
  type        = string
  sensitive   = true
}

variable "state_encryption_passphrase_prod" {
  description = "Passphrase used for local OpenTofu state encryption in the prod workspace."
  type        = string
  sensitive   = true
}

variable "state_encryption_previous_passphrase_baseline" {
  description = "Previous baseline workspace state encryption passphrase used only during OpenTofu state passphrase rotation."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "state_encryption_previous_passphrase_staging" {
  description = "Previous staging workspace state encryption passphrase used only during OpenTofu state passphrase rotation."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "state_encryption_previous_passphrase_prod" {
  description = "Previous prod workspace state encryption passphrase used only during OpenTofu state passphrase rotation."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "grayhaven_config_repo_ref" {
  description = "Git ref used by environment cloud-init and the bastion runner when checking out grayhaven-config-ansible. Production uses main unless allow_prod_config_repo_ref_override is true."
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[A-Za-z0-9._/-]+$", var.grayhaven_config_repo_ref)) && !strcontains(var.grayhaven_config_repo_ref, "..")
    error_message = "grayhaven_config_repo_ref must be a simple Git ref containing only letters, numbers, dots, underscores, hyphens, and slashes."
  }
}

variable "allow_prod_config_repo_ref_override" {
  description = "Allow the prod workspace to use grayhaven_config_repo_ref instead of main for explicit disposable production-shape testing."
  type        = bool
  default     = false
}

variable "grayhaven_test_infrastructure_policy_path" {
  description = "Optional infrastructure policy file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_test_compute_policy_path" {
  description = "Optional compute policy file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_test_server_configuration_path" {
  description = "Optional server configuration fixture for offline plan tests."
  type        = string
  default     = null
}

variable "grayhaven_test_ansible_configuration_path" {
  description = "Optional Ansible configuration fixture for offline plan tests."
  type        = string
  default     = null
}

variable "grayhaven_test_observability_configuration_path" {
  description = "Optional observability configuration fixture for offline plan tests."
  type        = string
  default     = null
}

variable "grayhaven_test_dns_policy_path" {
  description = "Optional DNS policy file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_test_ssh_keys_policy_path" {
  description = "Optional admin SSH keys policy file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_test_firewall_policy_path" {
  description = "Optional firewall policy file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_test_vault_config_path" {
  description = "Optional vault config.yml file path override for offline plan tests. Leave unset for operational deployments."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_vault_checkout_path" {
  description = "Local checkout path for grayhaven-vault. OpenTofu reads committed configuration and the encrypted control public key from the selected Git ref."
  type        = string
  default     = null
  nullable    = true
}

variable "grayhaven_vault_password_staging" {
  description = "Ansible Vault password used by staging bastion hosts to decrypt grayhaven-vault files."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "grayhaven_vault_password_prod" {
  description = "Ansible Vault password used by production bastion hosts to decrypt grayhaven-vault files."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true
}

variable "grayhaven_ansible_deploy_public_key" {
  description = "Public half of the bootstrap deployment key used for first-boot automation and GitHub deploy access."
  type        = string
  sensitive   = true
}

variable "grayhaven_ansible_deploy_private_key" {
  description = "Private half of the bootstrap deployment key used for first-boot automation and GitHub deploy access, installed only on bastion hosts."
  type        = string
  sensitive   = true
}
