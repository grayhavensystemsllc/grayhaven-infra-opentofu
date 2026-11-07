# DNS Architecture

This document summarizes how this repository manages DNS behavior. DNS policy
file formats are documented in [Policy Files](policy.md).

Environment droplets receive FQDNs from `identity.client_domain` in
`policy/infrastructure.yml`. Staging adds the `staging.` prefix.

DigitalOcean creates PTR records for droplets from their configured hostnames.

The `baseline` workspace owns shared DNS zones and baseline records. Shared
records such as mail records and CAA records should be managed as protected
baseline records. Less critical baseline records can be managed as unprotected
baseline records.

Environment workspaces create computed runtime records for domains listed in
their DNS policy. `environment.apex: true` creates the environment apex record.
`environment.web_aliases: true` creates `www` and `dev` aliases for that
environment.

DNS records are created in ordered type groups to reduce provider-side DNS
transaction contention. The sequence depends on the active workspace:

- `baseline`: `protected_records` are created as A, CNAME, MX, TXT, then CAA;
- `baseline`: unprotected `records` are created as A, CNAME, then TXT;
- environment workspaces: computed records are created as A, then CNAME;
- environment workspaces: `protected_records` are created as A, CNAME, then TXT;
- environment workspaces: unprotected `records` are created as A, CNAME, then
  TXT.

Please see the
[hosted domain documentation](https://github.com/grayhavensystemsllc/grayhaven-vault-example/blob/main/docs/schema.md#hosted-domain-dns-coordination)
in the
[`grayhaven-vault-example`](https://github.com/grayhavensystemsllc/grayhaven-vault-example)
repository for information on how to keep hosted web domains aligned with DNS
policy.

[Back to top](#dns-architecture)
