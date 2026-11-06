# Grayhaven Systems LLC Infrastructure (OpenTofu)

[![CI](https://github.com/grayhavensystemsllc/grayhaven-infra-opentofu/actions/workflows/ci.yml/badge.svg)](https://github.com/grayhavensystemsllc/grayhaven-infra-opentofu/actions/workflows/ci.yml)
[![OpenTofu Plan Tests](https://github.com/grayhavensystemsllc/grayhaven-infra-opentofu/actions/workflows/tofu-tests.yml/badge.svg)](https://github.com/grayhavensystemsllc/grayhaven-infra-opentofu/actions/workflows/tofu-tests.yml)

Infrastructure-as-code repository for Grayhaven Systems LLC using OpenTofu and
DigitalOcean.

This repository is public for transparency and operational demonstration. It
shows how Grayhaven Systems LLC manages its own infrastructure, but it does not
store client infrastructure, client credentials, private deployment data,
private SSH keys, secrets, generated state, or other private operational data.

## Table of Contents

- [Scope](#scope)
- [Requirements](#requirements)
- [Deployment Quick Reference](#deployment-quick-reference)
- [Other Documentation](#other-documentation)
- [Contributing](#contributing)
- [License](#license)

## Scope

- Manage shared baseline resources and separate staging/production runtime
  environments.
- Provision DigitalOcean VPCs, droplets, cloud firewalls, load balancers, DNS
  records, SSH keys, and projects based on vault configuration files.
- Manage resource project assignment and tagging for supported resources.
- Bootstrap hosts into
  [`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible)
  for first-boot configuration and setup for automated full Ansible
  convergence.
- Interface with a
  [`grayhaven-vault-example`](https://github.com/grayhavensystemsllc/grayhaven-vault-example)
  based private configuration repository with separate configuration supported
  for staging and production environments.
- Maintain local encrypted OpenTofu state.

This repository is not a general-purpose deployment template. Deploying similar
automation for another organization requires review and adaptation.

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)

## Requirements

This repository must be initialized and configured before use. This process is
documented in [Setup](docs/setup.md).

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)

## Deployment Quick Reference

Select the target workspace, review a plan, and apply only after the proposed
changes are understood.

Apply the shared baseline before deploying an environment:

```bash
tofu workspace select baseline
tofu plan
tofu apply
```

Deploy staging:

```bash
tofu workspace select staging
tofu plan
tofu apply
```

Deploy production:

```bash
tofu workspace select prod
tofu plan
tofu apply
```

For staging and production, the approved `tofu apply` is the single command
that carries the environment from infrastructure provisioning through
configuration convergence. It provisions DigitalOcean resources, renders
cloud-init, bootstraps hosts into
[`grayhaven-config-ansible`](https://github.com/grayhavensystemsllc/grayhaven-config-ansible),
and starts full Ansible convergence from the active control bastion.

See [Operations](docs/operations.md) for routine plan/apply workflows, destroy
procedures, control-node changes, and TLS-mode changes. See
[Safety](docs/safety.md) for secret, state, and destructive-action guardrails.

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)

## Other Documentation

- Setup & Configuration
  - [Setup](docs/setup.md)
  - [Policy Files](docs/policy.md)
- Operations & Safety
  - [Workspaces](docs/workspaces.md)
  - [Operations](docs/operations.md)
  - [Safety](docs/safety.md)
  - [Troubleshooting](docs/troubleshooting.md)
- Architecture & Standards
  - [Runtime Architecture](docs/runtime-architecture.md)
  - [Infrastructure Naming & Tagging Conventions](docs/naming-tagging-conventions.md)
  - [DNS Architecture](docs/dns-architecture.md)
  - [OpenTofu Test Suite](docs/opentofu-test-suite.md)

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands and contribution
guidelines.

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)

## License

[MIT](LICENSE)

[Back to top](#grayhaven-systems-llc-infrastructure-opentofu)
