locals {
  ssh_keys_policy = yamldecode(
    var.grayhaven_test_ssh_keys_policy_path != null
    ? file(var.grayhaven_test_ssh_keys_policy_path)
    : data.external.vault_config[0].result.ssh_keys_yml
  )
  admin_ssh_key_public_keys = toset(try(local.ssh_keys_policy.admin_ssh_keys, []))

  admin_ssh_key_parts = {
    for public_key in local.admin_ssh_key_public_keys :
    public_key => split(" ", trimspace(public_key))
  }

  admin_ssh_key_ids = {
    for public_key, parts in local.admin_ssh_key_parts :
    public_key => substr(sha256(join(" ", slice(parts, 0, 2))), 0, 16)
  }

  admin_ssh_keys = {
    for public_key, parts in local.admin_ssh_key_parts :
    local.admin_ssh_key_ids[public_key] => {
      public_key = public_key
      title = (
        length(parts) > 2
        ? join(" ", slice(parts, 2, length(parts)))
        : "admin-ssh-key-${local.admin_ssh_key_ids[public_key]}"
      )
    }
  }

  admin_ssh_key_fingerprints = local.is_environment ? [
    for key in sort(keys(data.digitalocean_ssh_key.admin)) : data.digitalocean_ssh_key.admin[key].fingerprint
  ] : []
}

resource "digitalocean_ssh_key" "admin" {
  for_each = local.is_baseline ? local.admin_ssh_keys : {}

  name       = each.value.title
  public_key = each.value.public_key
}

data "digitalocean_ssh_key" "admin" {
  for_each = local.is_environment ? local.admin_ssh_keys : {}

  name = each.value.title
}
