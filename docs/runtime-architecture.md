# Runtime Architecture

This document summarizes the supported runtime architecture for
Grayhaven Systems LLC infrastructure. Policy file schemas are documented in
[Policy Files](policy.md).

## Table of Contents

- [Supported Runtime Roles](#supported-runtime-roles)
- [Control Bastion](#control-bastion)
- [Admin SSH Keys](#admin-ssh-keys)
- [Web TLS Modes](#web-tls-modes)
- [Firewall Policy](#firewall-policy)
- [Observability Tags](#observability-tags)
- [Configuration Handoff](#configuration-handoff)

## Supported Runtime Roles

Environment workspaces currently support two runtime server roles:

- `bastion`: SSH entry point and, for the selected control bastion, Ansible
  convergence runner.
- `web`: nginx-based web host managed by
  [`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible).

Stable instance keys such as `bastion-01` and `web-01` are used as OpenTofu
resource keys. Numeric `index` values in compute policy are used for generated
resource names.

[Back to top](#runtime-architecture)

## Control Bastion

The active control bastion is selected by `bastions.control_node` in the
environment compute policy. The selected bastion receives the easy
`bastion.*` DNS record and the `control-node` tag.

[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
uses the control-node tag to identify the host that should run scheduled
Ansible convergence.

[Back to top](#runtime-architecture)

## Admin SSH Keys

The DigitalOcean SSH key name is derived from the public key comment when one is
present. When no comment is present, the name is generated from the public key
material.

[Back to top](#runtime-architecture)

## Web TLS Modes

Web TLS behavior is selected by `web.tls_mode` in environment compute policy:

- `auto`: one web host uses host TLS; two or more web hosts use load balancer
  TLS.
- `load_balancer`: always use load balancer TLS.

When web hosts scale from one node to two or more nodes in `auto` TLS mode,
OpenTofu creates a DigitalOcean load balancer and points web DNS at it. Moving
from load balancer TLS back to host TLS removes the load balancer and returns
DNS to the primary web host.

Adding or removing nodes from an existing load-balanced layout does not require
host certificate issuance. Moving between host TLS and load balancer TLS can
produce a short transition window while DNS, load balancer certificates, and
Ansible backend configuration converge.

[Back to top](#runtime-architecture)

## Firewall Policy

Cloud firewalls and host firewalld policy are both derived from the
environment-specific `firewall.yml` file in
`grayhaven-vault`.

OpenTofu reads this file from the local vault checkout during plan and apply.
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
reads the same file from the vault checkout on the active control bastion
during convergence.

When an environment uses load-balancer TLS, OpenTofu transforms the web cloud
firewall so origin HTTP accepts traffic from the DigitalOcean load balancer and
direct origin HTTPS is not exposed. The vault firewall policy remains the shared
cloud and host firewall input, while the runtime TLS mode determines the
effective web origin firewall shape.

For load-balanced environments with two or more web hosts, OpenTofu adds a
web-tag-scoped TCP `8791` path between web hosts for private website deployment
fanout. The path is omitted when an environment has only one web host, including
single-web-host environments that explicitly use load-balancer TLS.

[Back to top](#runtime-architecture)

## Observability Tags

Production droplets can receive Grafana Cloud observability tags from
`config.yml` in `grayhaven-vault`. When enabled, OpenTofu adds
`alerts-in-grafana-cloud` to production droplets so
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
can configure metrics shipping and managed alert rules. When log shipping is
also enabled, OpenTofu adds `logs-to-grafana-cloud`.

Grafana Cloud observability is intentionally production-only at this time.
Staging plans fail clearly if Grafana Cloud is enabled in staging config.

[Back to top](#runtime-architecture)

## Configuration Handoff

OpenTofu renders cloud-init data for each new droplet. During first boot, each
host is bootstrapped into
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
and receives the environment-specific values needed for convergence.

The cloud-init handoff writes bootstrap variables to
`/etc/grayhaven/bootstrap/bootstrap-vars.yml` and then runs `ansible-pull`
against
`grayhaven-config-ansible`.
All hosts receive their hostname, role, environment, configuration repository
ref, active control bastion selector, vault-selected certificate environment,
TLS mode, and first-boot deployment public key.

Bastion hosts also receive the `grayhaven-vault` repository URL and ref, Ansible
Vault passphrase, deployment SSH keypair, and control-node flag. Those values
are used only to prepare the first runner execution. The bootstrap playbook
removes the handoff file before starting the initial full convergence run.

Environment workspaces read plaintext configuration from the intended
`grayhaven-vault` Git ref instead of whichever branch is checked out locally.
Production uses the `main` ref and staging uses the `staging` ref. The
environment VPC CIDR comes from `config.yml` `network.vpc_cidr`.

Bootstrap role settings are loaded from the selected Vault branch's
`operations.yml`. The current control public key comes from
`compute.yml` at `bootstrap.control_public_key`; bootstrap installs it alongside
the deployment public key so existing control nodes can manage new hosts.

[Back to top](#runtime-architecture)
