output "bastion_public_ipv4_addresses" {
  description = "Public IPv4 addresses of bastion hosts by policy key"
  value       = local.is_environment ? { for key, droplet in module.bastion : key => droplet.public_ipv4_address } : {}
}

output "bastion_private_ipv4_addresses" {
  description = "Private IPv4 addresses of bastion hosts by policy key"
  value       = local.is_environment ? { for key, droplet in module.bastion : key => droplet.private_ipv4_address } : {}
}

output "control_bastion" {
  description = "Policy key and public IPv4 address for the active control bastion"
  value = local.is_environment ? {
    key                 = local.control_bastion_key
    public_ipv4_address = module.bastion[local.control_bastion_key].public_ipv4_address
  } : null
}

output "web_public_ipv4_addresses" {
  description = "Public IPv4 addresses of web hosts by policy key"
  value       = local.is_environment ? { for key, droplet in module.web : key => droplet.public_ipv4_address } : {}
}

output "web_private_ipv4_addresses" {
  description = "Private IPv4 addresses of web hosts by policy key"
  value       = local.is_environment ? { for key, droplet in module.web : key => droplet.private_ipv4_address } : {}
}

output "web_tls_mode" {
  description = "Effective web TLS mode for the active workspace"
  value       = local.is_environment ? local.effective_tls_mode : null
}

output "bastion_tags" {
  description = "DigitalOcean tags assigned to bastion hosts by policy key"
  value       = local.is_environment ? { for key, host in local.bastion_hosts : key => host.tags } : {}
}

output "web_tags" {
  description = "DigitalOcean tags assigned to web hosts by policy key"
  value       = local.is_environment ? { for key, host in local.web_hosts : key => host.tags } : {}
}

output "web_certificate_domain_names" {
  description = "Domain names requested for environment web certificates"
  value       = local.web_domain_names
}

output "web_firewall_inbound_rules" {
  description = "Effective inbound firewall rules for web hosts"
  value       = local.is_environment ? try(module.web_firewall[0].inbound_rules, []) : []
}

output "workspace" {
  description = "Active OpenTofu workspace"
  value       = terraform.workspace
}

output "environment_vpc_cidr" {
  description = "CIDR range of the active environment VPC"
  value       = local.is_environment ? local.environment_vpc_cidr : null
}

output "admin_ssh_key_fingerprints" {
  description = "Admin SSH key fingerprints attached to environment droplets"
  value       = local.admin_ssh_key_fingerprints
}

output "mcp_public_ipv4_addresses" {
  description = "Public IPv4 addresses of MCP hosts by policy key"
  value       = { for key, droplet in module.mcp : key => droplet.public_ipv4_address }
}
output "mcp_private_ipv4_addresses" {
  description = "Private IPv4 addresses of MCP hosts by policy key"
  value       = { for key, droplet in module.mcp : key => droplet.private_ipv4_address }
}
output "mcp_tags" {
  description = "DigitalOcean tags assigned to MCP hosts by policy key"
  value       = { for key, host in local.mcp_hosts : key => host.tags }
}
output "mcp_firewall_inbound_rules" {
  description = "Effective inbound firewall rules for MCP hosts"
  value       = try(module.mcp_firewall[0].inbound_rules, [])
}

output "vpcs" {
  description = "Permanent VPC identifiers by network policy key"
  value       = { for key, network in digitalocean_vpc.managed : key => network.id }
}

output "vpc_peerings" {
  description = "Permanent peering identifiers by network policy key"
  value       = { for key, peering in digitalocean_vpc_peering.managed : key => peering.id }
}
