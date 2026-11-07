variables {
  grayhaven_test_ansible_configuration_path = "tests/fixtures/ansible.yml"
  grayhaven_test_server_configuration_path  = "tests/fixtures/server-configuration.yml"
  grayhaven_test_infrastructure_policy_path = "tests/fixtures/infrastructure.yml"
  grayhaven_test_dns_policy_path            = "tests/fixtures/dns-baseline-shared-records.yml"
  grayhaven_vault_checkout_path             = "/tmp/example-vault-offline-test"
}

mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {}
    }
  }
}

mock_provider "digitalocean" {
  mock_resource "digitalocean_domain" {
    defaults = {
      id = "domain-id"
    }
  }

  mock_resource "digitalocean_project" {
    defaults = {
      id = "project-id"
    }
  }

  mock_resource "digitalocean_record" {
    defaults = {
      id = "record-id"
    }
  }

  mock_resource "digitalocean_vpc" {
    defaults = {
      id  = "vpc-id"
      urn = "do:vpc:vpc-id"
    }
  }
}

run "baseline_configured_policy_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    state_encryption_passphrase_baseline = "offline-test-baseline-state-passphrase"
    do_token                             = "offline-test-token"
    grayhaven_test_ssh_keys_policy_path  = "tests/fixtures/ssh-keys-admin.yml"
    grayhaven_ansible_deploy_public_key  = "ssh-ed25519 AAAAoffline offline@example"
    grayhaven_ansible_deploy_private_key = <<-EOT
      -----BEGIN OPENSSH PRIVATE KEY-----
      offline-test-private-key
      -----END OPENSSH PRIVATE KEY-----
    EOT
  }

  assert {
    condition     = output.workspace == "baseline"
    error_message = "The baseline fixture policy must plan in the baseline workspace."
  }
}

run "baseline_fixture_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    state_encryption_passphrase_baseline = "offline-test-baseline-state-passphrase"
    do_token                             = "offline-test-token"
    grayhaven_test_dns_policy_path       = "tests/fixtures/dns-baseline-shared-records.yml"
    grayhaven_test_ssh_keys_policy_path  = "tests/fixtures/ssh-keys-admin.yml"
    grayhaven_ansible_deploy_public_key  = "ssh-ed25519 AAAAoffline offline@example"
    grayhaven_ansible_deploy_private_key = <<-EOT
      -----BEGIN OPENSSH PRIVATE KEY-----
      offline-test-private-key
      -----END OPENSSH PRIVATE KEY-----
    EOT
  }

  assert {
    condition     = digitalocean_project.grayhaven[0].name == "example"
    error_message = "The baseline plan must include the shared DigitalOcean project."
  }

  assert {
    condition     = digitalocean_domain.managed["example_primary"].name == "example.com" && digitalocean_domain.managed["example_secondary"].name == "example.net"
    error_message = "The baseline fixture plan must include both managed DNS zones."
  }

  assert {
    condition = (
      length(digitalocean_record.baseline_protected_a) +
      length(digitalocean_record.baseline_protected_cname) +
      length(digitalocean_record.baseline_protected_mx) +
      length(digitalocean_record.baseline_protected_txt) +
      length(digitalocean_record.baseline_protected_caa)
    ) == 6
    error_message = "The baseline fixture plan must include all protected shared DNS records."
  }

  assert {
    condition = (
      length(digitalocean_record.baseline_a) +
      length(digitalocean_record.baseline_cname) +
      length(digitalocean_record.baseline_txt)
    ) == 0
    error_message = "The operational DNS policy should not plan unprotected baseline records until they are explicitly added."
  }

  assert {
    condition     = digitalocean_record.baseline_protected_mx["example_primary.mx_primary"].type == "MX" && digitalocean_record.baseline_protected_mx["example_secondary.mx_primary"].type == "MX"
    error_message = "The baseline fixture plan must retain mail DNS records under baseline ownership."
  }

  assert {
    condition     = digitalocean_vpc.baseline[0].name == "example-core-baseline-vpc"
    error_message = "The baseline plan must include the protected baseline VPC."
  }

  assert {
    condition     = length(digitalocean_ssh_key.admin) == 1 && contains([for key in keys(digitalocean_ssh_key.admin) : digitalocean_ssh_key.admin[key].name], "admin@example.com")
    error_message = "The baseline plan must manage the admin SSH key from the test fixture."
  }
}

run "baseline_unprotected_dns_record_plan" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    state_encryption_passphrase_baseline = "offline-test-baseline-state-passphrase"
    do_token                             = "offline-test-token"
    grayhaven_test_ssh_keys_policy_path  = "tests/fixtures/ssh-keys-admin.yml"
    grayhaven_ansible_deploy_public_key  = "ssh-ed25519 AAAAoffline offline@example"
    grayhaven_ansible_deploy_private_key = <<-EOT
      -----BEGIN OPENSSH PRIVATE KEY-----
      offline-test-private-key
      -----END OPENSSH PRIVATE KEY-----
    EOT
    grayhaven_test_dns_policy_path       = "tests/fixtures/dns-with-unprotected-records.yml"
  }

  assert {
    condition = (
      length(digitalocean_record.baseline_a) +
      length(digitalocean_record.baseline_cname) +
      length(digitalocean_record.baseline_txt)
    ) == 3
    error_message = "The baseline test fixture must plan unprotected DNS records."
  }

  assert {
    condition = (
      digitalocean_record.baseline_a["primary_site.infrastructure_notice_a"].type == "A" &&
      digitalocean_record.baseline_cname["primary_site.infrastructure_notice_cname"].type == "CNAME" &&
      digitalocean_record.baseline_txt["primary_site.infrastructure_notice_txt"].type == "TXT"
    )
    error_message = "The unprotected DNS record collection must support A, CNAME, and TXT records."
  }

  assert {
    condition     = length(digitalocean_record.baseline_protected_a) == 1 && length(digitalocean_record.baseline_protected_mx) == 2
    error_message = "The baseline test fixture must still plan protected DNS records separately by type."
  }
}

run "baseline_unsupported_dns_record_type_rejected" {
  command = plan

  plan_options {
    refresh = false
  }

  providers = {
    digitalocean = digitalocean
    external     = external
  }

  variables {
    state_encryption_passphrase_baseline = "offline-test-baseline-state-passphrase"
    do_token                             = "offline-test-token"
    grayhaven_test_ssh_keys_policy_path  = "tests/fixtures/ssh-keys-admin.yml"
    grayhaven_ansible_deploy_public_key  = "ssh-ed25519 AAAAoffline offline@example"
    grayhaven_ansible_deploy_private_key = <<-EOT
      -----BEGIN OPENSSH PRIVATE KEY-----
      offline-test-private-key
      -----END OPENSSH PRIVATE KEY-----
    EOT
    grayhaven_test_dns_policy_path       = "tests/fixtures/dns-with-unsupported-records.yml"
  }

  expect_failures = [
    terraform_data.dns_policy_guard,
  ]
}
