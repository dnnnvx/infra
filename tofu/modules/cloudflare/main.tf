data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# Apex A record — placeholder, DDNS deployment keeps it updated
# Subdomains are static CNAMEs pointing here; DDNS propagates the real public IP transitively
resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "@"
  content = "0.0.0.0"
  type    = "A"
  ttl     = 1
  proxied = true

  lifecycle {
    ignore_changes = [content]
  }
}

resource "cloudflare_r2_bucket" "this" {
  for_each   = var.r2_buckets
  account_id = var.cloudflare_account_id
  name       = each.key
  location   = each.value.location
}

resource "cloudflare_dns_record" "cname_subdomains" {
  for_each = toset(var.cname_subdomains)

  zone_id = data.cloudflare_zone.main.zone_id
  name    = each.key
  content = var.zone_name
  type    = "CNAME"
  ttl     = 1 # 1 = auto (TTL is ignored when proxied)
  proxied = true
}
