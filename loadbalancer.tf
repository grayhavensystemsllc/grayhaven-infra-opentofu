resource "tls_private_key" "web_lb_staging" {
  count = local.use_load_balancer && local.certificate_environment == "staging" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "web_lb_staging" {
  count = local.use_load_balancer && local.certificate_environment == "staging" ? 1 : 0

  private_key_pem       = tls_private_key.web_lb_staging[0].private_key_pem
  validity_period_hours = 2160
  early_renewal_hours   = 168
  dns_names             = local.web_domain_names
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]

  subject {
    common_name  = try(local.web_domain_names[0], "localhost")
    organization = local.organization
  }
}

resource "digitalocean_certificate" "web_lb_staging" {
  count = local.use_load_balancer && local.certificate_environment == "staging" ? 1 : 0

  name             = "${local.client_name}-core-${local.environment}-web-self-signed"
  type             = "custom"
  private_key      = tls_private_key.web_lb_staging[0].private_key_pem
  leaf_certificate = tls_self_signed_cert.web_lb_staging[0].cert_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "digitalocean_certificate" "web_lb_production" {
  count = local.use_load_balancer && local.certificate_environment == "production" ? 1 : 0

  name    = "${local.client_name}-core-${local.environment}-web-lets-encrypt"
  type    = "lets_encrypt"
  domains = local.web_domain_names

  lifecycle {
    create_before_destroy = true
  }
}

resource "digitalocean_loadbalancer" "web" {
  count = local.use_load_balancer ? 1 : 0

  name                   = "${local.client_name}-core-${local.environment}-web-lb"
  region                 = local.default_region
  vpc_uuid               = module.vpc[0].id
  droplet_ids            = [for droplet in module.web : droplet.id]
  redirect_http_to_https = true

  forwarding_rule {
    entry_protocol  = "http"
    entry_port      = 80
    target_protocol = "http"
    target_port     = 80
  }

  forwarding_rule {
    entry_protocol  = "https"
    entry_port      = 443
    target_protocol = "http"
    target_port     = 80
    certificate_name = (
      local.certificate_environment == "production"
      ? digitalocean_certificate.web_lb_production[0].name
      : digitalocean_certificate.web_lb_staging[0].name
    )
  }

  healthcheck {
    protocol                 = "http"
    port                     = 80
    path                     = "/"
    check_interval_seconds   = 10
    response_timeout_seconds = 5
    unhealthy_threshold      = 3
    healthy_threshold        = 5
  }
}
