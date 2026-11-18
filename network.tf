resource "terraform_data" "network_policy_guard" {
  input = {
    vpcs     = local.vpc_networks
    peerings = local.vpc_peerings
  }

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
      condition     = length(local.vpc_peerings) == sum([for peerings in values(local.vpc_peerings_by_environment) : length(peerings)])
      error_message = "Peering names must be unique across environment branches."
    }

    precondition {
      condition = alltrue(flatten([
        for environment, peerings in local.vpc_peerings_by_environment : [
          for peering in values(peerings) :
          length(peering) == 2 &&
          alltrue([for key in peering : try(local.vpc_networks[key].environment == environment, false)]) &&
          length(distinct([for key in peering : try(local.vpc_networks[key].region, "")])) == 2
        ]
      ]))
      error_message = "Each peering must identify two configured VPCs in different regions of its own environment."
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
  for_each = local.vpc_peerings

  name    = "${local.client_name}-core-${each.key}-peering"
  vpc_ids = [for key in each.value : digitalocean_vpc.managed[key].id]
}

data "digitalocean_vpc" "environment" {
  count = local.is_environment ? 1 : 0

  name = "${local.client_name}-core-${local.environment}-vpc-${local.default_region}"
}
