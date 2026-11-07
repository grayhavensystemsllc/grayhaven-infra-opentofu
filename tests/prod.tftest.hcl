variables {
  grayhaven_test_operations_policy_path     = "tests/fixtures/operations.yml"
  grayhaven_test_infrastructure_policy_path = "tests/fixtures/infrastructure.yml"
  grayhaven_test_dns_policy_path            = "tests/fixtures/dns-prod.yml"
  grayhaven_test_compute_policy_path        = "tests/fixtures/compute-1x1-auto.yml"
  state_encryption_passphrase_prod          = "offline-test-prod-state-passphrase"
  do_token                                  = "offline-test-token"
  grayhaven_vault_checkout_path             = "/tmp/grayhaven-vault-offline-test"
  grayhaven_vault_password_prod             = "offline-test-prod-vault-password"
  grayhaven_test_ssh_keys_policy_path       = "tests/fixtures/ssh-keys-admin.yml"
  grayhaven_ansible_deploy_public_key       = "ssh-ed25519 AAAAoffline offline@example"
  grayhaven_ansible_deploy_private_key      = <<-EOT
    -----BEGIN OPENSSH PRIVATE KEY-----
    offline-test-private-key
    -----END OPENSSH PRIVATE KEY-----
  EOT
}

mock_provider "digitalocean" {
  mock_data "digitalocean_ssh_key" {
    defaults = {
      fingerprint = "offline-admin-key-fingerprint"
      id          = 1
      public_key  = "ssh-ed25519 AAAAoffline-admin admin@example"
    }
  }

  mock_data "digitalocean_domain" {
    defaults = {
      id = "domain-id"
    }
  }

  mock_data "digitalocean_project" {
    defaults = {
      id = "project-id"
    }
  }

  mock_resource "digitalocean_certificate" {
    defaults = {
      id   = "certificate-id"
      uuid = "certificate-uuid"
    }
  }

  mock_resource "digitalocean_droplet" {
    defaults = {
      id                   = 1
      urn                  = "do:droplet:droplet-id"
      ipv4_address         = "198.51.100.10"
      ipv4_address_private = "172.22.0.10"
    }
  }

  mock_resource "digitalocean_firewall" {
    defaults = {
      id = "firewall-id"
    }
  }

  mock_resource "digitalocean_loadbalancer" {
    defaults = {
      id  = "loadbalancer-id"
      ip  = "198.51.100.20"
      urn = "do:loadbalancer:loadbalancer-id"
    }
  }

  mock_resource "digitalocean_project_resources" {
    defaults = {
      id = "project-resources-id"
    }
  }

  mock_resource "digitalocean_record" {
    defaults = {
      id = "record-id"
    }
  }

  mock_resource "digitalocean_tag" {
    defaults = {
      id = "tag-id"
    }
  }

  mock_resource "digitalocean_vpc" {
    defaults = {
      id  = "vpc-id"
      urn = "do:vpc:vpc-id"
    }
  }
}

mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        config_yml   = <<-EOT
          certificate:
            environment: production
            email: admin@example.com
          network:
            vpc_cidr: 172.22.0.0/16
          discord_webhook: production
          backup:
            repositories:
              local:
                repository_path: /var/backups/restic
                homedir_archive_path: /var/backups/deleted-homedir-archives
            schedule: daily
            retention:
              keep_daily: 7
            include:
              - /home
              - /var/log
            exclude: []
        EOT
        firewall_yml = <<-EOT
          firewalls:
            bastion:
              inbound:
                - protocol: tcp
                  port_range: "22"
                  source_addresses:
                    - 0.0.0.0/0
              outbound:
                - protocol: tcp
                  port_range: "22"
                  destination_tags:
                    - bastion
                    - web
            web:
              inbound:
                - protocol: tcp
                  port_range: "22"
                  source_tags:
                    - bastion
                - protocol: tcp
                  port_range: "80"
                  source_addresses:
                    - 0.0.0.0/0
                - protocol: tcp
                  port_range: "443"
                  source_addresses:
                    - 0.0.0.0/0
              outbound:
                - protocol: tcp
                  port_range: "80"
                  destination_addresses:
                    - 0.0.0.0/0
                - protocol: tcp
                  port_range: "443"
                  destination_addresses:
                    - 0.0.0.0/0
            mcp:
              inbound:
                - protocol: tcp
                  port_range: "22"
                  source_tags:
                    - bastion
                - protocol: tcp
                  port_range: "443"
                  source_addresses:
                    - 0.0.0.0/0
              outbound:
                - protocol: tcp
                  port_range: "22"
                  destination_tags:
                    - bastion
                - protocol: tcp
                  port_range: "443"
                  destination_addresses:
                    - 0.0.0.0/0
        EOT
      }
    }
  }
}

run "prod_without_mcp_policy_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  assert {
    condition     = length(module.mcp) == 0 && length(digitalocean_tag.mcp_scope) == 0 && length(digitalocean_record.grayhaven_mcp_a) == 0
    error_message = "An input policy without MCP must not create MCP resources."
  }

  assert {
    condition     = output.workspace == "prod"
    error_message = "The committed production policy must plan in the prod workspace."
  }

  assert {
    condition     = length(digitalocean_record.environment_cname) == 1 && digitalocean_record.environment_cname["primary_site.app_cname"].type == "CNAME" && digitalocean_record.environment_cname["primary_site.app_cname"].name == "service" && digitalocean_record.environment_cname["primary_site.app_cname"].value == "example.com."
    error_message = "The supplied DNS policy must produce the configured service CNAME."
  }
}

run "prod_config_ref_override_requires_explicit_approval" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_config_repo_ref = "issue-test-branch"
  }

  assert {
    condition     = local.config_repo_ref == "main"
    error_message = "Production must ignore grayhaven_config_repo_ref unless the explicit approval variable is true."
  }
}

run "prod_config_ref_override_uses_approved_ref" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    allow_prod_config_repo_ref_override = true
    grayhaven_config_repo_ref           = "issue-test-branch"
  }

  assert {
    condition     = local.config_repo_ref == "issue-test-branch"
    error_message = "Production must use grayhaven_config_repo_ref when the explicit approval variable is true."
  }
}

run "prod_1x1_auto_host_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
  }

  assert {
    condition     = output.workspace == "prod"
    error_message = "The production tests must run in the prod workspace."
  }

  assert {
    condition     = output.web_tls_mode == "host"
    error_message = "A 1/1 auto production policy must resolve to host TLS."
  }

  assert {
    condition     = length(output.bastion_public_ipv4_addresses) == 1 && length(output.web_public_ipv4_addresses) == 1
    error_message = "The 1/1 production policy must plan one bastion and one web host."
  }

  assert {
    condition = !contains([
      for rule in output.web_firewall_inbound_rules :
      rule.port_range
      if rule.protocol == "tcp"
    ], "8791")
    error_message = "The 1/1 production policy must not expose web deploy fanout ingress."
  }

  assert {
    condition = !contains([
      for rule in local.web_firewall_outbound_rules :
      rule.port_range
      if rule.protocol == "tcp"
    ], "8791")
    error_message = "The 1/1 production policy must not expose web deploy fanout egress."
  }

  assert {
    condition     = output.control_bastion.key == "bastion-01"
    error_message = "The 1/1 production policy must keep bastion-01 as the control node."
  }

  assert {
    condition = (
      length(digitalocean_record.baseline_protected_a) +
      length(digitalocean_record.baseline_protected_cname) +
      length(digitalocean_record.baseline_protected_mx) +
      length(digitalocean_record.baseline_protected_txt) +
      length(digitalocean_record.baseline_protected_caa)
    ) == 0
    error_message = "Production must not own baseline shared or mail DNS records."
  }

  assert {
    condition = (
      length(digitalocean_record.baseline_a) +
      length(digitalocean_record.baseline_cname) +
      length(digitalocean_record.baseline_txt)
    ) == 0
    error_message = "Production must not own unprotected baseline DNS records."
  }

  assert {
    condition     = digitalocean_record.web_root_a["primary_site"].name == "@" && digitalocean_record.web_dev_cname["secondary_site"].name == "dev"
    error_message = "Production must plan computed environment DNS records from DNS policy."
  }

  assert {
    condition     = length(output.admin_ssh_key_fingerprints) == 1 && output.admin_ssh_key_fingerprints[0] == "offline-admin-key-fingerprint"
    error_message = "Production droplets must receive admin SSH keys from policy lookup."
  }
}

run "prod_grafana_cloud_observability_tags" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_vault_config_path   = "tests/fixtures/vault-config-grafana-enabled.yml"
  }

  assert {
    condition = alltrue([
      for _, tags in output.bastion_tags :
      contains(tags, "alerts-in-grafana-cloud") && contains(tags, "logs-to-grafana-cloud")
    ])
    error_message = "Production bastion hosts must receive Grafana Cloud observability tags when enabled."
  }

  assert {
    condition = alltrue([
      for _, tags in output.web_tags :
      contains(tags, "alerts-in-grafana-cloud") && contains(tags, "logs-to-grafana-cloud")
    ])
    error_message = "Production web hosts must receive Grafana Cloud observability tags when enabled."
  }
}

run "prod_grafana_cloud_logs_require_enabled" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_vault_config_path   = "tests/fixtures/vault-config-grafana-logs-without-enabled.yml"
  }

  expect_failures = [
    terraform_data.environment_policy_guard,
  ]
}

run "prod_2x2_auto_load_balancer_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-2x2-auto.yml"
  }

  assert {
    condition     = output.web_tls_mode == "load_balancer"
    error_message = "A 2/2 auto production policy must resolve to load-balancer TLS."
  }

  assert {
    condition     = length(output.bastion_public_ipv4_addresses) == 2 && length(output.web_public_ipv4_addresses) == 2
    error_message = "The 2/2 production policy must plan two bastions and two web hosts."
  }

  assert {
    condition     = output.control_bastion.key == "bastion-02"
    error_message = "The 2/2 production policy must move control to bastion-02."
  }

  assert {
    condition     = length(digitalocean_loadbalancer.web) == 1 && length(digitalocean_certificate.web_lb_production) == 1
    error_message = "A 2/2 production load-balancer plan must include a load balancer and production certificate."
  }

  assert {
    condition = (
      length([
        for rule in output.web_firewall_inbound_rules :
        rule if rule.protocol == "tcp" && rule.port_range == "80"
      ]) == 1 &&
      alltrue([
        for rule in output.web_firewall_inbound_rules :
        length(rule.source_load_balancer_uids) == 1
        if rule.protocol == "tcp" && rule.port_range == "80"
      ])
    )
    error_message = "Production load-balancer TLS must restrict web HTTP origin traffic to the load balancer."
  }

  assert {
    condition = !contains([
      for rule in output.web_firewall_inbound_rules :
      rule.port_range
      if rule.protocol == "tcp"
    ], "443")
    error_message = "Production load-balancer TLS must not expose direct web HTTPS origin traffic."
  }

  assert {
    condition = length([
      for rule in output.web_firewall_inbound_rules :
      rule if rule.protocol == "tcp" &&
      rule.port_range == "8791" &&
      jsonencode(rule.source_tags) == jsonencode(["scope-example-core-prod-web"])
    ]) == 1
    error_message = "Production multi-web load-balancer plans must allow private deploy fanout ingress from web hosts."
  }

  assert {
    condition = length([
      for rule in local.web_firewall_outbound_rules :
      rule if rule.protocol == "tcp" &&
      rule.port_range == "8791" &&
      jsonencode(rule.destination_tags) == jsonencode(["scope-example-core-prod-web"])
    ]) == 1
    error_message = "Production multi-web load-balancer plans must allow private deploy fanout egress to web hosts."
  }

  assert {
    condition = jsonencode(output.web_certificate_domain_names) == jsonencode([
      "example.com",
      "www.example.com",
      "dev.example.com",
      "example.net",
      "www.example.net",
      "dev.example.net"
    ])
    error_message = "Production load-balancer certificate names must keep the per-domain apex, www, dev order."
  }
}

run "prod_apex_only_dns_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_dns_policy_path     = "tests/fixtures/dns-with-apex-only-environment.yml"
  }

  assert {
    condition     = length(digitalocean_record.web_root_a) == 1 && digitalocean_record.web_root_a["primary_site"].name == "@"
    error_message = "Production apex DNS must be optional and independent from web aliases."
  }

  assert {
    condition     = length(digitalocean_record.web_www_cname) == 0 && length(digitalocean_record.web_dev_cname) == 0
    error_message = "Production must not plan www/dev aliases when environment.web_aliases is false."
  }

  assert {
    condition     = jsonencode(output.web_certificate_domain_names) == jsonencode(["example.com"])
    error_message = "Production apex-only DNS must request only the apex certificate name."
  }
}

run "prod_firewall_requires_web_http_origin_rule" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path  = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_firewall_policy_path = "tests/fixtures/firewall-missing-web-http.yml"
  }

  expect_failures = [
    terraform_data.environment_policy_guard,
  ]
}

run "prod_firewall_requires_web_https_origin_rule" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path  = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_firewall_policy_path = "tests/fixtures/firewall-missing-web-https.yml"
  }

  expect_failures = [
    terraform_data.environment_policy_guard,
  ]
}

run "prod_explicit_dns_record_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_dns_policy_path     = "tests/fixtures/dns-with-environment-records.yml"
  }

  assert {
    condition = (
      length(digitalocean_record.environment_a) +
      length(digitalocean_record.environment_cname) +
      length(digitalocean_record.environment_txt)
    ) == 3
    error_message = "Production must plan explicit unprotected DNS records from environment DNS policy."
  }

  assert {
    condition = (
      digitalocean_record.environment_a["primary_site.infrastructure_notice_a"].type == "A" &&
      digitalocean_record.environment_cname["primary_site.infrastructure_notice_cname"].type == "CNAME" &&
      digitalocean_record.environment_txt["primary_site.infrastructure_notice_txt"].type == "TXT"
    )
    error_message = "Production environment DNS records must support A, CNAME, and TXT records."
  }

  assert {
    condition = (
      length(digitalocean_record.environment_protected_a) == 1 &&
      length(digitalocean_record.environment_protected_cname) == 1 &&
      length(digitalocean_record.environment_protected_txt) == 1
    )
    error_message = "Production must plan explicit protected DNS records from environment DNS policy."
  }
}

run "prod_environment_protected_mx_caa_rejected" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-auto.yml"
    grayhaven_test_dns_policy_path     = "tests/fixtures/dns-with-environment-protected-mx-caa.yml"
  }

  expect_failures = [
    terraform_data.dns_policy_guard,
  ]
}

run "prod_3x3_explicit_load_balancer_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-3x3-load-balancer.yml"
  }

  assert {
    condition     = output.web_tls_mode == "load_balancer"
    error_message = "A 3/3 explicit production policy must use load-balancer TLS."
  }

  assert {
    condition     = length(output.bastion_public_ipv4_addresses) == 3 && length(output.web_public_ipv4_addresses) == 3
    error_message = "The 3/3 production policy must plan three bastions and three web hosts."
  }

  assert {
    condition     = output.control_bastion.key == "bastion-03"
    error_message = "The 3/3 production policy must move control to bastion-03."
  }

  assert {
    condition     = length(digitalocean_loadbalancer.web) == 1 && length(digitalocean_certificate.web_lb_production) == 1
    error_message = "A 3/3 production load-balancer plan must include a load balancer and production certificate."
  }
}

run "prod_with_mcp_policy_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-1x1-mcp.yml"
  }

  assert {
    condition     = length(module.mcp) == 1 && length(digitalocean_tag.mcp_scope) == 1 && length(digitalocean_record.grayhaven_mcp_a) == 1
    error_message = "An input policy with one MCP host must create its host, scope tag, and endpoint."
  }

  assert {
    condition     = length(module.bastion) == 1 && length(module.web) == 1
    error_message = "Adding MCP must preserve the requested bastion and web instance counts."
  }
}

run "prod_bastion_only_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path  = "tests/fixtures/compute-bastion-only.yml"
    grayhaven_test_firewall_policy_path = "tests/fixtures/firewall-bastion-only.yml"
  }

  assert {
    condition     = length(module.bastion) == 1 && length(module.web) == 0 && length(module.mcp) == 0
    error_message = "Empty web instances must preserve the requested bastion and MCP hosts."
  }

  assert {
    condition     = length(module.web_firewall) == 0 && length(digitalocean_tag.web_scope) == 0 && length(digitalocean_loadbalancer.web) == 0 && length(digitalocean_certificate.web_lb_staging) == 0 && length(digitalocean_certificate.web_lb_production) == 0
    error_message = "A policy without web hosts must omit web firewall, tag, load-balancer and certificate resources."
  }

  assert {
    condition     = length(digitalocean_record.web_root_a) == 0 && length(digitalocean_record.web_www_cname) == 0 && length(digitalocean_record.web_dev_cname) == 0 && length(digitalocean_record.grayhaven_bastion_a) == 1
    error_message = "A policy without web hosts must omit automatic web DNS and retain bastion DNS."
  }

  assert {
    condition     = alltrue([for rule in local.firewall_policy_rules.bastion.outbound : !contains(rule.destination_tags, "scope-example-core-prod-web")])
    error_message = "Bastion egress must not reference an absent web scope tag."
  }
}

run "prod_bastion_mcp_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-bastion-mcp.yml"
  }

  assert {
    condition     = length(module.bastion) == 1 && length(module.web) == 0 && length(module.mcp) == 1
    error_message = "Empty web instances must preserve the requested bastion and MCP hosts."
  }

  assert {
    condition     = length(module.web_firewall) == 0 && length(digitalocean_tag.web_scope) == 0 && length(digitalocean_loadbalancer.web) == 0 && length(digitalocean_certificate.web_lb_staging) == 0 && length(digitalocean_certificate.web_lb_production) == 0
    error_message = "A policy without web hosts must omit web firewall, tag, load-balancer and certificate resources."
  }

  assert {
    condition     = length(digitalocean_record.web_root_a) == 0 && length(digitalocean_record.web_www_cname) == 0 && length(digitalocean_record.web_dev_cname) == 0 && length(digitalocean_record.grayhaven_bastion_a) == 1
    error_message = "A policy without web hosts must omit automatic web DNS and retain bastion DNS."
  }

  assert {
    condition     = alltrue([for rule in local.firewall_policy_rules.bastion.outbound : !contains(rule.destination_tags, "scope-example-core-prod-web")])
    error_message = "Bastion egress must not reference an absent web scope tag."
  }
}

run "prod_no_web_load_balancer_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    grayhaven_test_compute_policy_path = "tests/fixtures/compute-bastion-only-lb.yml"
  }

  assert {
    condition     = length(module.bastion) == 1 && length(module.web) == 0 && length(module.mcp) == 0
    error_message = "Empty web instances must preserve the requested bastion and MCP hosts."
  }

  assert {
    condition     = length(module.web_firewall) == 0 && length(digitalocean_tag.web_scope) == 0 && length(digitalocean_loadbalancer.web) == 0 && length(digitalocean_certificate.web_lb_staging) == 0 && length(digitalocean_certificate.web_lb_production) == 0
    error_message = "A policy without web hosts must omit web firewall, tag, load-balancer and certificate resources."
  }

  assert {
    condition     = length(digitalocean_record.web_root_a) == 0 && length(digitalocean_record.web_www_cname) == 0 && length(digitalocean_record.web_dev_cname) == 0 && length(digitalocean_record.grayhaven_bastion_a) == 1
    error_message = "A policy without web hosts must omit automatic web DNS and retain bastion DNS."
  }

  assert {
    condition     = alltrue([for rule in local.firewall_policy_rules.bastion.outbound : !contains(rule.destination_tags, "scope-example-core-prod-web")])
    error_message = "Bastion egress must not reference an absent web scope tag."
  }
}
