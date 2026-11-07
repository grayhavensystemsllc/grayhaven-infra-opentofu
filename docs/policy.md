# Policy Files

OpenTofu reads committed configuration from the selected `grayhaven-vault`
Git ref. File schemas and examples are documented in
[grayhaven-vault-example](https://github.com/grayhavensystemsllc/grayhaven-vault-example/blob/main/docs/schema.md).

## Table of Contents

- [Overview](#overview)
- [Infrastructure Configuration](#infrastructure-configuration)
- [DNS Policy](#dns-policy)
- [Firewall Policy](#firewall-policy)
- [Admin SSH Key Policy](#admin-ssh-key-policy)
- [Compute Policy](#compute-policy)

## Overview

Set `TF_VAR_grayhaven_vault_checkout_path` to the local vault checkout.
Baseline and production read `main`; staging reads `staging`. OpenTofu reads
committed files from that ref, regardless of the checked-out branch.

| File | Configuration |
| --- | --- |
| `policy/infrastructure.yml` | Identity, project, defaults, repositories, VPC |
| `policy/compute.yml` | Environment server instances and web TLS mode |
| `policy/dns.yml` | Environment DNS records |
| `policy/baseline/dns.yml` | Shared DNS zones and records |
| `policy/baseline/ssh-keys.yml` | First-boot admin public keys |
| `config.yml` | Certificate settings |
| `server_configuration.yml` | Server settings and environment network |
| `ansible.yml` | Automation schedules and notifications |
| `grafana/observability.yml` | Grafana Cloud selectors |
| `vault/bastion.yml` | Encrypted Ansible control public key |
| `policy/firewall.yml` | Shared cloud and host firewall policy |

[Back to top](#policy-files)

## Infrastructure Configuration

`policy/infrastructure.yml` supplies resource identity, DigitalOcean project settings,
provider defaults, baseline VPC CIDR and bootstrap repository URLs.

[Back to top](#policy-files)

## DNS Policy

Baseline owns shared zones and mail records in `policy/baseline/dns.yml`.
Environment workspaces use `policy/dns.yml` for explicit records and computed web
records. See [DNS Architecture](dns-architecture.md).

[Back to top](#policy-files)

## Firewall Policy

OpenTofu and Ansible read the same environment-specific `policy/firewall.yml`.
Load-balancer TLS derives web origin rules from that policy. Multi-web-host
load-balanced environments also receive a web-tag-scoped TCP `8791` path for
deployment fanout.

[Back to top](#policy-files)

## Admin SSH Key Policy

`policy/baseline/ssh-keys.yml` supplies admin public keys for first-boot access.
Baseline manages the DigitalOcean key resources; environment workspaces look
them up by name. Private keys remain outside these plaintext policy files.

[Back to top](#policy-files)

## Compute Policy

`policy/compute.yml` supplies instance maps for `bastion`, `web`, and `mcp` roles.
An environment requires at least one bastion. Web hosts may be omitted, and
MCP permits at most one instance. Instance `size` and `image` values override
the defaults in `policy/infrastructure.yml`.

`web.tls_mode: auto` uses host TLS for one web host and load-balancer TLS for
multiple web hosts. `load_balancer` selects load-balancer TLS when web hosts
exist. MCP uses host TLS.

Bootstrap obtains `ansible_control.public_key` from encrypted
`vault/bastion.yml` using the environment's Vault password. Only the public
key is returned to OpenTofu; it is installed alongside the bootstrap deployment
public key.

[Back to top](#policy-files)
