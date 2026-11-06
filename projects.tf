resource "digitalocean_project" "grayhaven" {
  count = local.is_baseline ? 1 : 0

  name        = local.infrastructure_policy.project.name
  description = local.infrastructure_policy.project.description
  purpose     = local.infrastructure_policy.project.purpose
  environment = local.infrastructure_policy.project.environment
  is_default  = local.infrastructure_policy.project.is_default

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_project_resources" "environment" {
  count = local.is_environment ? 1 : 0

  project = data.digitalocean_project.grayhaven[0].id

  resources = concat(
    [for droplet in module.bastion : droplet.urn],
    [for droplet in module.web : droplet.urn],
    [for droplet in module.mcp : droplet.urn],
    local.use_load_balancer ? [digitalocean_loadbalancer.web[0].urn] : []
  )
}
