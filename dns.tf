locals {
  dns_policy = yamldecode(
    var.grayhaven_test_dns_policy_path != null
    ? file(var.grayhaven_test_dns_policy_path)
    : (local.is_baseline ? data.external.vault_config[0].result.baseline_dns_yml : data.external.vault_config[0].result.dns_yml)
  )
  dns_ttl = try(local.dns_policy.ttl, 300)

  dns_supported_baseline_protected_record_types    = toset(["A", "CNAME", "MX", "TXT", "CAA"])
  dns_supported_environment_protected_record_types = toset(["A", "CNAME", "TXT"])
  dns_supported_protected_record_types             = local.is_baseline ? local.dns_supported_baseline_protected_record_types : local.dns_supported_environment_protected_record_types
  dns_supported_record_types                       = toset(["A", "CNAME", "TXT"])

  dns_domains = {
    for domain_key, domain in local.dns_policy.domains : domain_key => {
      name                    = domain.name
      environment_apex        = try(domain.environment.apex, false)
      environment_web_aliases = try(domain.environment.web_aliases, false)
      records                 = try(domain.records, {})
      protected_records       = try(domain.protected_records, {})
    }
  }

  dns_protected_records = merge(flatten([
    for domain_key, domain in local.dns_domains : [
      for record_key, record in domain.protected_records : {
        "${domain_key}.${record_key}" = {
          domain_key = domain_key
          record     = record
        }
      }
    ]
  ])...)

  dns_records = merge(flatten([
    for domain_key, domain in local.dns_domains : [
      for record_key, record in domain.records : {
        "${domain_key}.${record_key}" = {
          domain_key = domain_key
          record     = record
        }
      }
    ]
  ])...)

  dns_all_records = merge(
    {
      for record_key, record in local.dns_protected_records :
      "protected.${record_key}" => record
    },
    {
      for record_key, record in local.dns_records :
      "records.${record_key}" => record
    }
  )

  dns_protected_record_types = toset([
    for _, record in local.dns_protected_records :
    upper(tostring(try(record.record.type, "")))
  ])

  dns_record_types = toset([
    for _, record in local.dns_records :
    upper(tostring(try(record.record.type, "")))
  ])

  dns_protected_records_by_type = {
    for record_type in local.dns_supported_protected_record_types : record_type => {
      for record_key, record in local.dns_protected_records : record_key => record
      if upper(tostring(try(record.record.type, ""))) == record_type
    }
  }

  dns_records_by_type = {
    for record_type in local.dns_supported_record_types : record_type => {
      for record_key, record in local.dns_records : record_key => record
      if upper(tostring(try(record.record.type, ""))) == record_type
    }
  }

  dns_records_with_unsupported_priority = toset([
    for record_key, record in local.dns_all_records : record_key
    if can(record.record.priority) && !(local.is_baseline && upper(tostring(try(record.record.type, ""))) == "MX")
  ])

  dns_records_with_unsupported_caa_attributes = toset([
    for record_key, record in local.dns_all_records : record_key
    if anytrue([can(record.record.flags), can(record.record.tag)]) && !(local.is_baseline && upper(tostring(try(record.record.type, ""))) == "CAA")
  ])

  environment_apex_dns = local.is_environment && length(local.web_instances) > 0 ? {
    for domain_key, domain in local.dns_domains : domain_key => {
      domain       = domain.name
      site_name    = local.is_prod ? domain.name : "staging.${domain.name}"
      env_root     = local.is_prod ? "@" : "staging"
      cname_target = local.is_prod ? "@" : "staging.${domain.name}."
    } if domain.environment_apex
  } : {}

  environment_web_alias_dns = local.is_environment ? {
    for domain_key, site in local.environment_apex_dns : domain_key => merge(site, {
      www_name = local.is_prod ? "www" : "www.staging"
      dev_name = local.is_prod ? "dev" : "dev.staging"
    })
    if local.dns_domains[domain_key].environment_web_aliases
  } : {}
}

data "digitalocean_domain" "managed" {
  for_each = local.is_environment ? local.dns_domains : {}

  name = each.value.name
}

resource "terraform_data" "dns_policy_guard" {
  input = {
    protected_record_types = local.dns_protected_record_types
    record_types           = local.dns_record_types
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for _, domain in local.dns_domains :
        !domain.environment_web_aliases || domain.environment_apex
      ])
      error_message = "DNS environment.web_aliases requires environment.apex."
    }

    precondition {
      condition     = length(setsubtract(local.dns_protected_record_types, local.dns_supported_protected_record_types)) == 0
      error_message = "DNS protected_records support A, CNAME, and TXT record types. Baseline protected_records also support MX and CAA."
    }

    precondition {
      condition     = length(setsubtract(local.dns_record_types, local.dns_supported_record_types)) == 0
      error_message = "DNS records support only A, CNAME, and TXT record types."
    }

    precondition {
      condition     = length(local.dns_records_with_unsupported_priority) == 0
      error_message = "DNS priority is supported only for baseline MX records."
    }

    precondition {
      condition     = length(local.dns_records_with_unsupported_caa_attributes) == 0
      error_message = "DNS flags and tag are supported only for baseline CAA records."
    }
  }
}

###############################################################################
# Baseline DNS zones and shared records
###############################################################################

resource "digitalocean_domain" "managed" {
  for_each = local.is_baseline ? local.dns_domains : {}

  name = each.value.name

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_protected_a" {
  for_each = local.is_baseline ? local.dns_protected_records_by_type["A"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_protected_cname" {
  for_each = local.is_baseline ? local.dns_protected_records_by_type["CNAME"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_protected_a]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_protected_mx" {
  for_each = local.is_baseline ? local.dns_protected_records_by_type["MX"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_protected_cname]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_protected_txt" {
  for_each = local.is_baseline ? local.dns_protected_records_by_type["TXT"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_protected_mx]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_protected_caa" {
  for_each = local.is_baseline ? local.dns_protected_records_by_type["CAA"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_protected_txt]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "baseline_a" {
  for_each = local.is_baseline ? local.dns_records_by_type["A"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_protected_caa]
}

resource "digitalocean_record" "baseline_cname" {
  for_each = local.is_baseline ? local.dns_records_by_type["CNAME"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_a]
}

resource "digitalocean_record" "baseline_txt" {
  for_each = local.is_baseline ? local.dns_records_by_type["TXT"] : {}

  domain   = digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.baseline_cname]
}

###############################################################################
# Environment DNS records
###############################################################################

resource "digitalocean_record" "web_root_a" {
  for_each = local.is_environment ? local.environment_apex_dns : {}

  domain = each.value.domain
  type   = "A"
  name   = each.value.env_root
  value  = local.use_load_balancer ? digitalocean_loadbalancer.web[0].ip : try(module.web[local.primary_web_key].public_ipv4_address, "")
  ttl    = local.dns_ttl

  depends_on = [data.digitalocean_domain.managed]
}

resource "digitalocean_record" "web_www_cname" {
  for_each = local.is_environment ? local.environment_web_alias_dns : {}

  domain = each.value.domain
  type   = "CNAME"
  name   = each.value.www_name
  value  = each.value.cname_target
  ttl    = local.dns_ttl

  depends_on = [
    digitalocean_record.web_root_a,
    digitalocean_record.grayhaven_droplet_a,
    digitalocean_record.grayhaven_bastion_a,
  ]
}

resource "digitalocean_record" "web_dev_cname" {
  for_each = local.is_environment ? local.environment_web_alias_dns : {}

  domain = each.value.domain
  type   = "CNAME"
  name   = each.value.dev_name
  value  = each.value.cname_target
  ttl    = local.dns_ttl

  depends_on = [digitalocean_record.web_www_cname]
}

resource "digitalocean_record" "grayhaven_droplet_a" {
  for_each = local.droplet_dns_records

  domain = each.value.domain
  type   = "A"
  name   = each.value.name
  value  = each.value.value
  ttl    = local.dns_ttl

  depends_on = [data.digitalocean_domain.managed]
}

resource "digitalocean_record" "grayhaven_bastion_a" {
  count = local.is_environment ? 1 : 0

  domain = local.client_domain
  type   = "A"
  name   = local.is_prod ? "bastion" : "bastion.staging"
  value  = try(module.bastion[local.control_bastion_key].public_ipv4_address, "")
  ttl    = local.dns_ttl

  depends_on = [data.digitalocean_domain.managed]
}

resource "digitalocean_record" "environment_protected_a" {
  for_each = local.is_environment ? local.dns_protected_records_by_type["A"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [
    digitalocean_record.web_root_a,
    digitalocean_record.web_www_cname,
    digitalocean_record.web_dev_cname,
    digitalocean_record.grayhaven_droplet_a,
    digitalocean_record.grayhaven_bastion_a,
  ]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "environment_protected_cname" {
  for_each = local.is_environment ? local.dns_protected_records_by_type["CNAME"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.environment_protected_a]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "environment_protected_txt" {
  for_each = local.is_environment ? local.dns_protected_records_by_type["TXT"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.environment_protected_cname]

  lifecycle {
    prevent_destroy = true
  }
}

resource "digitalocean_record" "environment_a" {
  for_each = local.is_environment ? local.dns_records_by_type["A"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.environment_protected_txt]
}

resource "digitalocean_record" "environment_cname" {
  for_each = local.is_environment ? local.dns_records_by_type["CNAME"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.environment_a]
}

resource "digitalocean_record" "environment_txt" {
  for_each = local.is_environment ? local.dns_records_by_type["TXT"] : {}

  domain   = data.digitalocean_domain.managed[each.value.domain_key].name
  type     = each.value.record.type
  name     = each.value.record.name
  value    = each.value.record.value
  priority = try(each.value.record.priority, null)
  flags    = try(each.value.record.flags, null)
  tag      = try(each.value.record.tag, null)
  ttl      = try(each.value.record.ttl, local.dns_ttl)

  depends_on = [digitalocean_record.environment_cname]
}

resource "digitalocean_record" "grayhaven_mcp_a" {
  count      = length(local.mcp_instances) > 0 ? 1 : 0
  domain     = local.client_domain
  type       = "A"
  name       = local.is_prod ? "mcp" : "mcp.staging"
  value      = try(module.mcp[sort(keys(local.mcp_hosts))[0]].public_ipv4_address, "")
  ttl        = local.dns_ttl
  depends_on = [data.digitalocean_domain.managed]
}
