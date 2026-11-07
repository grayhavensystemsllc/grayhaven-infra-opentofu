locals {
  #############################################################################
  # Repository and workspace identity
  #############################################################################

  client_name            = local.infrastructure_policy.identity.client_name
  client_domain          = local.infrastructure_policy.identity.client_domain
  organization           = local.infrastructure_policy.identity.organization
  supported_workspaces   = ["baseline", "staging", "prod"]
  environment_workspaces = ["staging", "prod"]
  environment            = terraform.workspace
  is_baseline            = local.environment == "baseline"
  is_environment         = contains(local.environment_workspaces, local.environment)
  is_prod                = local.environment == "prod"

  config_repo_ref = local.is_prod && !var.allow_prod_config_repo_ref_override ? "main" : var.grayhaven_config_repo_ref
  vault_repo_ref  = local.environment == "staging" ? "staging" : "main"

  state_encryption_passphrase = (
    local.environment == "baseline" ? var.state_encryption_passphrase_baseline :
    local.environment == "staging" ? var.state_encryption_passphrase_staging :
    local.environment == "prod" ? var.state_encryption_passphrase_prod :
    coalesce(
      var.state_encryption_passphrase_baseline,
      var.state_encryption_passphrase_staging,
      var.state_encryption_passphrase_prod,
    )
  )
  state_encryption_previous_passphrase = coalesce(
    local.environment == "baseline" ? var.state_encryption_previous_passphrase_baseline : null,
    local.environment == "staging" ? var.state_encryption_previous_passphrase_staging : null,
    local.environment == "prod" ? var.state_encryption_previous_passphrase_prod : null,
    local.state_encryption_passphrase,
  )

  #############################################################################
  # Shared selectors and vault policy
  #############################################################################

  common_tags = [
    "client-${local.client_name}",
    "env-${local.environment}",
    "managed-by-opentofu",
    "configured-by-ansible",
    "tls-mode-${replace(local.effective_tls_mode, "_", "-")}"
  ]

  compute_policy = local.is_environment ? yamldecode(
    var.grayhaven_test_compute_policy_path != null
    ? file(var.grayhaven_test_compute_policy_path)
    : data.external.vault_config[0].result.compute_yml
  ) : null

  vault_checkout_path = coalesce(
    var.grayhaven_vault_checkout_path,
    abspath("${path.module}/../grayhaven-vault"),
  )

  infrastructure_policy = yamldecode(
    var.grayhaven_test_infrastructure_policy_path != null
    ? file(var.grayhaven_test_infrastructure_policy_path)
    : data.external.vault_config[0].result.infrastructure_yml
  )
  default_region       = local.infrastructure_policy.defaults.region
  default_os_image     = local.infrastructure_policy.defaults.os_image
  default_droplet_size = local.infrastructure_policy.defaults.droplet_size
  operations_policy = yamldecode(
    var.grayhaven_test_operations_policy_path != null
    ? file(var.grayhaven_test_operations_policy_path)
    : data.external.vault_config[0].result.operations_yml
  )
  bootstrap_control_public_key = local.is_environment ? try(local.compute_policy.bootstrap.control_public_key, "") : ""
  baseline_vpc_cidr            = local.infrastructure_policy.baseline.vpc_cidr
  config_repo_url              = local.infrastructure_policy.repositories.config
  vault_repo_url               = local.infrastructure_policy.repositories.vault

  # Environment workspaces read config.yml from the intended vault Git ref, not
  # from whichever branch is checked out in the local vault working tree.
  vault_config_yaml = (
    local.is_environment
    ? (
      var.grayhaven_test_vault_config_path != null
      ? file(var.grayhaven_test_vault_config_path)
      : data.external.vault_config[0].result.config_yml
    )
    : "{}\n"
  )
  vault_config = yamldecode(local.vault_config_yaml)

  network_config = try(local.vault_config.network, {})
  environment_vpc_cidr = (
    local.is_environment
    ? try(local.network_config.vpc_cidr, null)
    : null
  )

  certificate_config = try(local.vault_config.certificate, {})

  grafana_cloud_config         = try(local.vault_config.observability.grafana_cloud, {})
  grafana_cloud_enabled        = local.is_environment ? try(tobool(local.grafana_cloud_config.enabled), false) : false
  grafana_cloud_logs_requested = local.is_environment ? try(tobool(local.grafana_cloud_config.logs_enabled), false) : false
  grafana_cloud_logs_enabled   = local.grafana_cloud_enabled && local.grafana_cloud_logs_requested
  grafana_cloud_tags = (
    local.is_prod && local.grafana_cloud_enabled
    ? concat(
      ["alerts-in-grafana-cloud"],
      local.grafana_cloud_logs_enabled ? ["logs-to-grafana-cloud"] : [],
    )
    : []
  )
  environment_host_common_tags = concat(local.common_tags, local.grafana_cloud_tags)

  firewall_policy_yaml = (
    local.is_environment
    ? (
      var.grayhaven_test_firewall_policy_path != null
      ? file(var.grayhaven_test_firewall_policy_path)
      : data.external.vault_config[0].result.firewall_yml
    )
    : "firewalls: {}\n"
  )
  firewall_policy = yamldecode(local.firewall_policy_yaml)

  vault_password = !local.is_environment ? null : (
    local.is_prod
    ? var.grayhaven_vault_password_prod
    : var.grayhaven_vault_password_staging
  )
  certificate_environment = (
    local.is_environment
    ? try(local.certificate_config.environment, null)
    : "staging"
  )

  bastion_instances = local.is_environment ? local.compute_policy.bastions.instances : {}
  mcp_instances     = local.is_environment ? try(local.compute_policy.mcp.instances, {}) : {}
  web_instances     = local.is_environment ? local.compute_policy.web.instances : {}
  web_tls_setting   = local.is_environment ? try(local.compute_policy.web.tls_mode, "auto") : "auto"

  # In auto mode, a single web host terminates TLS locally; multiple web hosts
  # use a DigitalOcean load balancer so certificate and backend behavior stay
  # consistent during scale-out.
  use_load_balancer = (
    local.is_environment
    ? length(local.web_instances) > 0 && (local.web_tls_setting == "load_balancer" || (
      local.web_tls_setting == "auto" && length(local.web_instances) > 1
    ))
    : false
  )

  effective_tls_mode = local.is_environment ? (
    local.use_load_balancer ? "load_balancer" : "host"
  ) : "host"

  control_bastion_key = local.is_environment ? local.compute_policy.bastions.control_node : ""
  primary_web_key     = local.is_environment ? try(sort(keys(local.web_instances))[0], "") : ""

  environment_hostname_suffix = local.is_prod ? local.client_domain : "staging.${local.client_domain}"

  #############################################################################
  # Host inventory and cloud-init handoff
  #############################################################################

  web_domain_names = local.is_environment ? flatten([
    for domain_key, site in local.environment_apex_dns : concat(
      [site.site_name],
      contains(keys(local.environment_web_alias_dns), domain_key) ? [
        "${local.environment_web_alias_dns[domain_key].www_name}.${site.domain}",
        "${local.environment_web_alias_dns[domain_key].dev_name}.${site.domain}"
      ] : []
    )
  ]) : []

  firewall_tag_names = local.is_environment ? merge(
    { bastion = digitalocean_tag.bastion_scope[0].name },
    length(local.web_instances) > 0 ? { web = digitalocean_tag.web_scope[0].name } : {},
    length(local.mcp_instances) > 0 ? { mcp = digitalocean_tag.mcp_scope[0].name } : {},
  ) : {}

  bastion_hosts = {
    for key, instance in local.bastion_instances : key => {
      index           = instance.index
      hostname        = format("%s-sec-%s-bastion-%02d.%s", local.client_name, local.environment, instance.index, local.environment_hostname_suffix)
      is_control_node = key == local.control_bastion_key
      size            = try(instance.size, local.default_droplet_size)
      image           = try(instance.image, local.default_os_image)
      tags = concat(local.environment_host_common_tags, [
        "project-sec",
        "role-bastion",
        "scope-${local.client_name}-sec-${local.environment}-bastion",
        "bastion-${format("%02d", instance.index)}",
        key == local.control_bastion_key ? "control-node" : "control-capable"
      ])
    }
  }

  web_hosts = {
    for key, instance in local.web_instances : key => {
      index    = instance.index
      hostname = format("%s-core-%s-web-%02d.%s", local.client_name, local.environment, instance.index, local.environment_hostname_suffix)
      size     = try(instance.size, local.default_droplet_size)
      image    = try(instance.image, local.default_os_image)
      tags = concat(local.environment_host_common_tags, [
        "project-core",
        "role-web",
        "scope-${local.client_name}-core-${local.environment}-web",
        "web-${format("%02d", instance.index)}"
      ])
    }
  }

  mcp_hosts = {
    for key, instance in local.mcp_instances : key => {
      index    = instance.index
      hostname = format("%s-core-%s-mcp-%02d.%s", local.client_name, local.environment, instance.index, local.environment_hostname_suffix)
      size     = try(instance.size, local.default_droplet_size)
      image    = try(instance.image, local.default_os_image)
      tags = concat([for tag in local.environment_host_common_tags : tag if !startswith(tag, "tls-mode-")], [
        "tls-mode-host",
        "project-core",
        "role-mcp",
        "scope-${local.client_name}-core-${local.environment}-mcp",
        "mcp-${format("%02d", instance.index)}"
      ])
    }
  }

  bastion_bootstrap_vars = {
    for key, host in local.bastion_hosts : key => merge(local.operations_policy, { infrastructure = local.infrastructure_policy }, {
      grayhaven_hostname                                                                          = host.hostname
      grayhaven_environment                                                                       = local.environment
      grayhaven_role                                                                              = "bastion"
      grayhaven_is_control_node                                                                   = host.is_control_node
      grayhaven_control_bastion_key                                                               = local.control_bastion_key
      grayhaven_config_repo_url                                                                   = local.config_repo_url
      grayhaven_config_repo_ref                                                                   = local.config_repo_ref
      grayhaven_vault_repo_url                                                                    = local.vault_repo_url
      grayhaven_vault_repo_ref                                                                    = local.vault_repo_ref
      grayhaven_vault_password                                                                    = local.vault_password
      grayhaven_ansible_control_public_key                                                        = local.bootstrap_control_public_key
      grayhaven_ansible_deploy_public_key                                                         = var.grayhaven_ansible_deploy_public_key
      grayhaven_ansible_deploy_private_key                                                        = var.grayhaven_ansible_deploy_private_key
      grayhaven_certificate_environment                                                           = local.certificate_environment
      grayhaven_tls_mode                                                                          = local.effective_tls_mode
    })
  }

  web_bootstrap_vars = {
    for key, host in local.web_hosts : key => merge(local.operations_policy, { infrastructure = local.infrastructure_policy }, {
      grayhaven_hostname                                                                      = host.hostname
      grayhaven_environment                                                                   = local.environment
      grayhaven_role                                                                          = "web"
      grayhaven_config_repo_url                                                               = local.config_repo_url
      grayhaven_config_repo_ref                                                               = local.config_repo_ref
      grayhaven_control_bastion_key                                                           = local.control_bastion_key
      grayhaven_ansible_control_public_key                                                    = local.bootstrap_control_public_key
      grayhaven_ansible_deploy_public_key                                                     = var.grayhaven_ansible_deploy_public_key
      grayhaven_certificate_environment                                                       = local.certificate_environment
      grayhaven_tls_mode                                                                      = local.effective_tls_mode
    })
  }

  mcp_bootstrap_vars = {
    for key, host in local.mcp_hosts : key => merge(local.operations_policy, { infrastructure = local.infrastructure_policy }, {
      grayhaven_hostname                                                                      = host.hostname
      grayhaven_environment                                                                   = local.environment
      grayhaven_role                                                                          = "mcp"
      grayhaven_config_repo_url                                                               = local.config_repo_url
      grayhaven_config_repo_ref                                                               = local.config_repo_ref
      grayhaven_control_bastion_key                                                           = local.control_bastion_key
      grayhaven_ansible_control_public_key                                                    = local.bootstrap_control_public_key
      grayhaven_ansible_deploy_public_key                                                     = var.grayhaven_ansible_deploy_public_key
      grayhaven_certificate_environment                                                       = local.certificate_environment
      grayhaven_tls_mode                                                                      = "host"
    })
  }

  bastion_user_data = {
    for key, bootstrap_vars in local.bastion_bootstrap_vars : key => templatefile("${path.module}/templates/cloud-init/bootstrap-vars.yml.tftpl", {
      bootstrap_vars_yaml = yamlencode(bootstrap_vars)
      config_repo_ref     = local.config_repo_ref
      config_repo_url     = local.config_repo_url
    })
  }

  web_user_data = {
    for key, bootstrap_vars in local.web_bootstrap_vars : key => templatefile("${path.module}/templates/cloud-init/bootstrap-vars.yml.tftpl", {
      bootstrap_vars_yaml = yamlencode(bootstrap_vars)
      config_repo_ref     = local.config_repo_ref
      config_repo_url     = local.config_repo_url
    })
  }

  mcp_user_data = {
    for key, bootstrap_vars in local.mcp_bootstrap_vars : key => templatefile("${path.module}/templates/cloud-init/bootstrap-vars.yml.tftpl", {
      bootstrap_vars_yaml = yamlencode(bootstrap_vars)
      config_repo_ref     = local.config_repo_ref
      config_repo_url     = local.config_repo_url
    })
  }

  #############################################################################
  # DNS and firewall policy expansion
  #############################################################################

  droplet_dns_records = local.is_environment ? merge(
    {
      for key, host in local.bastion_hosts : "bastion-${key}" => {
        domain = local.client_domain
        name   = trimsuffix(module.bastion[key].name, ".${local.client_domain}")
        value  = module.bastion[key].public_ipv4_address
      }
    },
    {
      for key, host in local.web_hosts : "web-${key}" => {
        domain = local.client_domain
        name   = trimsuffix(module.web[key].name, ".${local.client_domain}")
        value  = module.web[key].public_ipv4_address
      }
    },
    {
      for key, host in local.mcp_hosts : "mcp-${key}" => {
        domain = local.client_domain
        name   = trimsuffix(module.mcp[key].name, ".${local.client_domain}")
        value  = module.mcp[key].public_ipv4_address
      }
    }
  ) : {}

  firewall_policy_web_inbound_rules = try(local.firewall_policy.firewalls.web.inbound, [])
  firewall_policy_web_tcp_ports = toset([
    for rule in local.firewall_policy_web_inbound_rules : rule.port_range
    if rule.protocol == "tcp"
  ])

  firewall_policy_rules = local.is_environment ? {
    for role, policy in local.firewall_policy.firewalls : role => {
      inbound = [
        for rule in try(policy.inbound, []) : {
          protocol                  = rule.protocol
          port_range                = rule.port_range
          source_addresses          = try(rule.source_addresses, [])
          source_load_balancer_uids = []
          source_tags               = [for tag in try(rule.source_tags, []) : local.firewall_tag_names[tag] if !contains(["web", "mcp"], tag) || contains(keys(local.firewall_tag_names), tag)]
        }
        if length(try(rule.source_tags, [])) == 0 || length(try(rule.source_addresses, [])) > 0 || anytrue([for tag in try(rule.source_tags, []) : !contains(["web", "mcp"], tag) || contains(keys(local.firewall_tag_names), tag)])
      ]
      outbound = [
        for rule in try(policy.outbound, []) : {
          protocol              = rule.protocol
          port_range            = rule.port_range
          destination_addresses = try(rule.destination_addresses, [])
          destination_tags      = [for tag in try(rule.destination_tags, []) : local.firewall_tag_names[tag] if !contains(["web", "mcp"], tag) || contains(keys(local.firewall_tag_names), tag)]
        }
        if length(try(rule.destination_tags, [])) == 0 || length(try(rule.destination_addresses, [])) > 0 || anytrue([for tag in try(rule.destination_tags, []) : !contains(["web", "mcp"], tag) || contains(keys(local.firewall_tag_names), tag)])
      ]
    }
    if contains(keys(local.firewall_tag_names), role)
  } : {}

  web_load_balancer_origin_ports = toset(["80"])
  web_direct_origin_tls_ports    = toset(["443"])
  web_deploy_fanout_port         = "8791"
  web_deploy_fanout_enabled      = local.use_load_balancer && length(local.web_instances) > 1

  web_firewall_inbound_base_rules = local.is_environment ? [
    for rule in try(local.firewall_policy_rules.web.inbound, []) : merge(rule, (
      local.use_load_balancer &&
      rule.protocol == "tcp" &&
      contains(local.web_load_balancer_origin_ports, rule.port_range)
      ? {
        source_addresses          = []
        source_load_balancer_uids = [digitalocean_loadbalancer.web[0].id]
        source_tags               = []
      }
      : {}
    ))
    if !(
      local.use_load_balancer &&
      rule.protocol == "tcp" &&
      contains(local.web_direct_origin_tls_ports, rule.port_range)
    )
  ] : []

  web_deploy_fanout_inbound_rule = {
    protocol                  = "tcp"
    port_range                = local.web_deploy_fanout_port
    source_addresses          = []
    source_load_balancer_uids = []
    source_tags               = length(local.web_instances) > 0 ? [digitalocean_tag.web_scope[0].name] : []
  }

  web_firewall_inbound_rules = concat(
    local.web_firewall_inbound_base_rules,
    local.web_deploy_fanout_enabled ? [local.web_deploy_fanout_inbound_rule] : [],
  )

  web_deploy_fanout_outbound_rule = {
    protocol              = "tcp"
    port_range            = local.web_deploy_fanout_port
    destination_addresses = []
    destination_tags      = length(local.web_instances) > 0 ? [digitalocean_tag.web_scope[0].name] : []
  }

  web_firewall_outbound_rules = concat(
    try(local.firewall_policy_rules.web.outbound, []),
    local.web_deploy_fanout_enabled ? [local.web_deploy_fanout_outbound_rule] : [],
  )

  firewall_rules = local.is_environment ? merge(
    local.firewall_policy_rules,
    {
      web = merge(try(local.firewall_policy_rules.web, { inbound = [], outbound = [] }), {
        inbound  = local.web_firewall_inbound_rules
        outbound = local.web_firewall_outbound_rules
      })
    }
  ) : {}
}
