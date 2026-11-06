resource "terraform_data" "workspace_guard" {
  input = terraform.workspace

  lifecycle {
    precondition {
      condition     = contains(local.supported_workspaces, terraform.workspace)
      error_message = "Supported workspaces are baseline, staging, and prod."
    }
  }
}

resource "terraform_data" "environment_policy_guard" {
  count = local.is_environment ? 1 : 0

  input = {
    control_bastion_key = local.control_bastion_key
    tls_mode            = local.web_tls_setting
  }

  lifecycle {
    precondition {
      condition     = local.is_environment ? contains(keys(local.bastion_instances), local.control_bastion_key) : true
      error_message = "The compute policy bastions.control_node value must match a bastion instance key."
    }

    precondition {
      condition     = local.is_environment ? contains(["auto", "load_balancer"], local.web_tls_setting) : true
      error_message = "The compute policy web.tls_mode value must be auto or load_balancer."
    }

    precondition {
      condition     = local.is_environment ? length(local.web_instances) <= 1 || local.use_load_balancer : true
      error_message = "Environments with two or more web hosts must use load-balancer TLS."
    }

    precondition {
      condition     = local.is_environment ? contains(["staging", "production"], local.certificate_environment) : true
      error_message = "certificate.environment must be staging or production."
    }

    precondition {
      condition     = local.is_environment ? local.environment_vpc_cidr != null && can(cidrnetmask(local.environment_vpc_cidr)) : true
      error_message = "network.vpc_cidr must be a valid CIDR block for staging and prod workspaces."
    }

    precondition {
      condition     = length(local.bastion_instances) > 0
      error_message = "The compute policy must define at least one bastion host."
    }

    precondition {
      condition     = length(local.mcp_instances) <= 1
      error_message = "The compute policy permits at most one MCP server per environment."
    }

    precondition {
      condition = length(local.mcp_instances) == 0 || (
        contains(keys(try(local.firewall_policy.firewalls, {})), "mcp") &&
        alltrue([for rule in try(local.firewall_policy.firewalls.mcp.inbound, []) : rule.protocol == "tcp" && contains(["22", "443"], rule.port_range)]) &&
        anytrue([for rule in try(local.firewall_policy.firewalls.mcp.inbound, []) : rule.protocol == "tcp" && rule.port_range == "443"]) &&
        anytrue([for rule in try(local.firewall_policy.firewalls.mcp.inbound, []) : rule.protocol == "tcp" && rule.port_range == "22" && jsonencode(try(rule.source_tags, [])) == jsonencode(["bastion"]) && length(try(rule.source_addresses, [])) == 0]) &&
        alltrue([for rule in try(local.firewall_policy.firewalls.mcp.inbound, []) : !(rule.protocol == "tcp" && rule.port_range == "22") || (jsonencode(try(rule.source_tags, [])) == jsonencode(["bastion"]) && length(try(rule.source_addresses, [])) == 0)])
      )
      error_message = "MCP requires a Vault firewall policy with HTTPS and SSH restricted to the bastion tag."
    }

    precondition {
      condition     = local.vault_checkout_path != null && trimspace(local.vault_checkout_path) != ""
      error_message = "grayhaven_vault_checkout_path is required for staging and prod workspaces."
    }

    precondition {
      condition     = local.vault_password != null && local.vault_password != ""
      error_message = "A vault password is required for staging and prod workspaces."
    }

    precondition {
      condition     = length(local.web_instances) == 0 || (contains(local.firewall_policy_web_tcp_ports, "80") && contains(local.firewall_policy_web_tcp_ports, "443"))
      error_message = "The web inbound firewall policy must include tcp port_range \"80\" and tcp port_range \"443\"."
    }

    precondition {
      condition     = !local.grafana_cloud_enabled || local.is_prod
      error_message = "Grafana Cloud observability is supported only in the prod workspace."
    }

    precondition {
      condition     = !local.grafana_cloud_logs_requested || local.grafana_cloud_enabled
      error_message = "Grafana Cloud log shipping requires observability.grafana_cloud.enabled to be true."
    }
  }
}

data "digitalocean_project" "grayhaven" {
  count = local.is_environment ? 1 : 0

  name = local.infrastructure_policy.project.name
}

data "external" "vault_config" {
  count = 1

  program = [
    "${path.module}/scripts/read-vault-config",
    local.vault_checkout_path,
    local.vault_repo_ref,
  ]
}

resource "digitalocean_vpc" "baseline" {
  count = local.is_baseline ? 1 : 0

  name        = "${local.client_name}-core-baseline-vpc"
  region      = local.default_region
  ip_range    = local.baseline_vpc_cidr
  description = "Baseline default VPC for ${local.organization}"

  lifecycle {
    prevent_destroy = true
  }
}

module "vpc" {
  count  = local.is_environment ? 1 : 0
  source = "./modules/vpc"

  name        = "${local.client_name}-core-${local.environment}-vpc"
  region      = local.default_region
  vpc_cidr    = local.environment_vpc_cidr
  description = "${title(local.environment)} VPC for ${local.organization}"
}

module "bastion" {
  for_each = local.bastion_hosts
  source   = "./modules/droplet"

  name                 = each.value.hostname
  region               = local.default_region
  vpc_id               = module.vpc[0].id
  ssh_key_fingerprints = local.admin_ssh_key_fingerprints
  size                 = each.value.size
  image                = each.value.image
  tags                 = each.value.tags
  user_data            = local.bastion_user_data[each.key]
}

module "web" {
  for_each = local.web_hosts
  source   = "./modules/droplet"

  name                 = each.value.hostname
  region               = local.default_region
  vpc_id               = module.vpc[0].id
  ssh_key_fingerprints = local.admin_ssh_key_fingerprints
  size                 = each.value.size
  image                = each.value.image
  tags                 = each.value.tags
  user_data            = local.web_user_data[each.key]
}

module "mcp" {
  for_each = local.mcp_hosts
  source   = "./modules/droplet"

  name                 = each.value.hostname
  region               = local.default_region
  vpc_id               = module.vpc[0].id
  ssh_key_fingerprints = local.admin_ssh_key_fingerprints
  size                 = each.value.size
  image                = each.value.image
  tags                 = each.value.tags
  user_data            = local.mcp_user_data[each.key]
}

module "bastion_firewall" {
  count  = local.is_environment ? 1 : 0
  source = "./modules/firewall"

  name        = "${local.client_name}-sec-${local.environment}-bastion-fw"
  target_tags = [digitalocean_tag.bastion_scope[0].name]

  inbound_rules  = try(local.firewall_rules.bastion.inbound, [])
  outbound_rules = try(local.firewall_rules.bastion.outbound, [])
}

module "web_firewall" {
  count  = length(local.web_instances) > 0 ? 1 : 0
  source = "./modules/firewall"

  name        = "${local.client_name}-core-${local.environment}-web-fw"
  target_tags = [digitalocean_tag.web_scope[0].name]

  inbound_rules  = try(local.firewall_rules.web.inbound, [])
  outbound_rules = try(local.firewall_rules.web.outbound, [])
}

module "mcp_firewall" {
  count          = length(local.mcp_instances) > 0 ? 1 : 0
  source         = "./modules/firewall"
  name           = "${local.client_name}-core-${local.environment}-mcp-fw"
  target_tags    = [digitalocean_tag.mcp_scope[0].name]
  inbound_rules  = try(local.firewall_rules.mcp.inbound, [])
  outbound_rules = try(local.firewall_rules.mcp.outbound, [])
}
