resource "terraform_data" "network_policy_guard" {
  input = local.infrastructure_policy.network

  lifecycle {
    precondition {
      condition = alltrue([
        for network in values(local.vpc_networks) :
        contains(local.supported_workspaces, network.environment) &&
        trimspace(network.region) != "" && can(cidrnetmask(network.cidr))
      ])
      error_message = "Network policy entries require an environment, region, and IPv4 CIDR."
    }

    precondition {
      condition = alltrue([
        for peering in values(local.infrastructure_policy.network.peerings) :
        length(distinct(peering)) == 2 &&
        alltrue([for key in peering : contains(keys(local.vpc_networks), key)])
      ])
      error_message = "Each peering must identify two distinct configured VPCs."
    }
  }
}

resource "digitalocean_vpc" "managed" {
  for_each = local.is_baseline ? local.vpc_networks : {}

  name        = "${local.client_name}-core-${each.value.environment}-vpc-${each.value.region}"
  region      = each.value.region
  ip_range    = each.value.cidr
  description = "${title(each.value.environment)} VPC for ${local.organization}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_vpc_peering" "managed" {
  for_each = local.is_baseline ? local.infrastructure_policy.network.peerings : {}

  name    = "${local.client_name}-core-${each.key}-peering"
  vpc_ids = [for key in each.value : digitalocean_vpc.managed[key].id]
}

data "digitalocean_vpc" "environment" {
  count = local.is_environment ? 1 : 0

  name = "${local.client_name}-core-${local.environment}-vpc-${local.default_region}"
}
