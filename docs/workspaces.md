# Workspaces

Grayhaven Systems LLC infrastructure uses OpenTofu workspaces to separate
shared baseline resources from environment-specific runtime infrastructure.

## Table of Contents

- [Supported Workspaces](#supported-workspaces)
- [Baseline](#baseline)
- [Staging](#staging)
- [Production](#production)

## Supported Workspaces

The supported workspaces are:

- `baseline`
- `staging`
- `prod`

[Back to top](#workspaces)

## Baseline

The `baseline` workspace manages shared resources that staging and production
depend on, including:

- the DigitalOcean project;
- admin SSH keys;
- DNS zones;
- mail DNS records;
- CAA records;
- permanent regional VPCs and configured peerings.

Baseline VPCs are regional defaults and are not intended for workloads.
Environment deployments select a permanent VPC for their environment and region.

Protected baseline resources cannot be destroyed through normal OpenTofu
operations. To be absolutely safe, you should not attempt to destroy the
`baseline` workspace. Staging and production depend on the shared resources it
manages, and destroying the `baseline` workspace will cause production outages
for mail and HTTPS services.

[Back to top](#workspaces)

## Staging

The `staging` workspace manages temporary environment infrastructure used to
validate changes before promotion to production.

Staging owns environment-specific resources such as:

- staging bastion and web droplets;
- staging firewall attachments;
- staging web DNS records;
- staging droplet DNS records;
- staging load balancers when the compute policy requires them.

Staging reads plaintext configuration from the `staging` Git ref in the local
`grayhaven-vault` checkout. The checkout can use another branch, but the
`staging` ref must be present locally.

Destroying the `staging` workspace leaves its permanent VPC and peerings intact.

[Back to top](#workspaces)

## Production

The `prod` workspace manages production runtime infrastructure.

Production owns environment-specific resources such as:

- production bastion and web droplets;
- production firewall attachments;
- production web DNS records;
- production droplet DNS records;
- production load balancers when the compute policy requires them.

Production reads plaintext configuration from the `main` Git ref in the local
`grayhaven-vault` checkout. The checkout can use another branch, but the `main`
ref must be present locally.

Changes to the `prod` workspace should follow Grayhaven Systems LLC change
control procedures.

The `prod` workspace should not be destroyed. Destroying the `prod` workspace
will cause production outages.

[Back to top](#workspaces)
