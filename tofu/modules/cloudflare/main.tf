data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# Apex A record — placeholder, DDNS deployment keeps it updated
resource "cloudflare_dns_record" "apex" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "@"
  content = "0.0.0.0"
  type    = "A"
  ttl     = 60
  proxied = false

  lifecycle {
    ignore_changes = [content]
  }
}
