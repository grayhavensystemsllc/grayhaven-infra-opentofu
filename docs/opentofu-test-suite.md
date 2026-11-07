# OpenTofu Test Suite

This document describes the offline OpenTofu test suite for this repository.

## Table of Contents

- [Purpose](#purpose)
- [How Tests Run](#how-tests-run)
- [Test Policy Fixtures](#test-policy-fixtures)
- [What Is Tested](#what-is-tested)
- [Limitations](#limitations)
- [Local Use](#local-use)

## Purpose

The OpenTofu tests provide offline plan-shape validation. They verify that
fictional configuration fixtures produce the expected resource
graph for the supported workspaces without deploying infrastructure.

The suite is intended to catch regressions in workspace ownership, DNS
expansion, compute scaling behavior, TLS mode selection, and admin SSH key
attachment before a change reaches a live `tofu plan` or `tofu apply`.

[Back to top](#opentofu-test-suite)

## How Tests Run

CI runs OpenTofu validation in two jobs:

- `Validate`: runs formatting, static validation, YAML linting, Markdown
  linting, ShellCheck, and GitHub Actions linting.
- `Offline Plan Tests`: runs `tofu test` against `baseline`, `staging`, and
  `prod` from a backend-disabled checkout.

The OpenTofu test job initializes with `tofu init -backend=false`, creates a
temporary local workspace for each supported workspace, and runs the matching
test file:

- `tests/baseline.tftest.hcl`
- `tests/staging.tftest.hcl`
- `tests/prod.tftest.hcl`

The test files use mocked providers, fake sensitive values, and
`refresh = false` plans. The external vault-config lookup is mocked for
environment tests so the suite does not need access to `grayhaven-vault`
repository. The mocked vault lookup supplies fictional configuration and a fictional
control public key.
Test-only path overrides load independent fixtures; tests do not read live
vault configuration.

[Back to top](#opentofu-test-suite)

## Test Policy Fixtures

The test suite uses optional policy path overrides to load static fixture files
from `tests/fixtures/`:

- `grayhaven_test_infrastructure_policy_path`
- `grayhaven_test_compute_policy_path`
- `grayhaven_test_dns_policy_path`
- `grayhaven_test_firewall_policy_path`
- `grayhaven_test_ssh_keys_policy_path`
- `grayhaven_test_vault_config_path`
- `grayhaven_test_server_configuration_path`
- `grayhaven_test_ansible_configuration_path`
- `grayhaven_test_observability_configuration_path`

These variables exist only for offline plan tests and disposable validation
checkouts. Leave them unset for operational deployments.

[Back to top](#opentofu-test-suite)

## What Is Tested

Baseline tests verify that the `baseline` workspace plans shared resources
under baseline ownership:

- the shared DigitalOcean project;
- managed DNS zones;
- protected shared DNS records, including mail records;
- the protected baseline VPC;
- admin SSH key resources.

Baseline fixture tests also verify support for unprotected A, CNAME, and TXT
records under `records`, and verify that unsupported DNS record types are
rejected by the DNS policy guard.

DNS fixture tests use the test-only DNS policy override to verify baseline
unprotected records, environment explicit records, unsupported DNS record
rejection, baseline-only MX/CAA protected record handling, apex-only environment
records, and invalid environment alias combinations.

Staging and production tests verify fixture plans for their matching
workspaces, plus fixed scenario fixtures:

- 1 bastion / 1 web host with `auto` TLS resolving to host TLS;
- 2 bastions / 2 web hosts with `auto` TLS resolving to load-balancer TLS;
- 3 bastions / 3 web hosts with explicit load-balancer TLS;
- control bastion selection for each scaling fixture;
- environment DNS records for apex, `www`, and `dev`;
- explicit environment DNS `records` and A/CNAME/TXT `protected_records`;
- rejection of environment `protected_records` using MX or CAA;
- apex-only DNS behavior when aliases are disabled;
- validation that web aliases require an apex record;
- load-balancer certificate domain name ordering;
- load-balancer TLS web firewall behavior;
- conditional web-to-web deploy fanout firewall behavior for multi-web
  load-balancer plans;
- rejection of web firewall policy that omits required HTTP or HTTPS origin
  rules;
- rejection of Grafana Cloud observability outside production;
- production-only Grafana Cloud observability tags;
- validation that Grafana Cloud log shipping requires the main Grafana Cloud
  observability switch;
- admin SSH key lookup and droplet attachment.

Environment tests also verify that staging and production do not plan baseline
DNS resources. This keeps shared DNS ownership in `baseline` and runtime DNS
ownership in the environment workspaces.

[Back to top](#opentofu-test-suite)

The Python configuration-reader unit tests cover committed file selection,
public-key extraction, password delivery, validation failures and value-free
diagnostics using invented inputs. Line and branch coverage must remain at
least 90%.

## Limitations

The tests do not deploy resources and do not contact DigitalOcean. They cannot
prove provider availability, API permissions, quota availability, DNS
propagation, certificate issuance, SSH access, cloud-init execution, or
Ansible convergence.

The suite validates create/update plan shape. It does not prove destroy
behavior or live migration behavior for existing state.

The suite uses static fixtures and mocked provider defaults. It is designed to
catch repository logic regressions, not to replace live staging validation.

[Back to top](#opentofu-test-suite)

## Local Use

Local test execution should happen from a temporary state-free copy, not from
the operational checkout used for real deployments. The full local validation
workflow is documented in [CONTRIBUTING.md](../CONTRIBUTING.md#local-validation).

[Back to top](#opentofu-test-suite)
