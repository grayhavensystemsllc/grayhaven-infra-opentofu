# Infrastructure Naming & Tagging Conventions

Grayhaven Systems LLC infrastructure uses consistent names and DigitalOcean tags
so resources are easy to audit, filter, and operate during routine changes.

## Table of Contents

- [Naming](#naming)
- [DigitalOcean Tags](#digitalocean-tags)

## Naming

Resource names use stable, descriptive segments:

```text
<client>-<project>-<environment>-<role-or-service>
```

Indexed resources add a two-digit instance number:

```text
<client>-<project>-<environment>-<role>-NN
```

Current project segments are:

- `core`: primary runtime infrastructure such as web hosts, VPCs, and load
  balancers.
- `sec`: security and access infrastructure such as bastion hosts.

Examples:

- `example-core-baseline-vpc`
- `example-core-prod-vpc`
- `example-core-prod-web-01`
- `example-sec-prod-bastion-01`
- `example-core-prod-web-fw`
- `example-core-prod-web-lb`

[Back to top](#infrastructure-naming--tagging-conventions)

## DigitalOcean Tags

DigitalOcean tags are part of the operational contract for taggable resources.
They identify ownership, environment, role, firewall scope, TLS mode, and
Ansible convergence state.

All taggable resources contain one or more of the following common tags as
appropriate:

- `client-<client>`
- `env-<environment>`
- `managed-by-opentofu`
- `configured-by-ansible`
- `tls-mode-host` or `tls-mode-load-balancer`

Resources may contain these additional tags as appropriate:

- `project-<project>`
- `role-<role>`
- `scope-<scope>`
- `control-node`
- `control-capable`
- `alerts-in-grafana-cloud`
- `logs-to-grafana-cloud`

[Back to top](#infrastructure-naming--tagging-conventions)
