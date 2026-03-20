locals {
  mail_hostname = "mail.${var.zone_name}"
}

# MX record: example.com → mail.example.com
resource "cloudflare_dns_record" "mx" {
  zone_id  = data.cloudflare_zone.main.zone_id
  name     = "@"
  content  = local.mail_hostname
  type     = "MX"
  priority = 10
  ttl      = 3600
}

# SPF: only the MX host is allowed to send
resource "cloudflare_dns_record" "spf" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "@"
  content = "v=spf1 mx ra=postmaster -all"
  type    = "TXT"
  ttl     = 3600
}

# DMARC
resource "cloudflare_dns_record" "dmarc" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=reject; rua=mailto:postmaster@${var.zone_name}"
  type    = "TXT"
  ttl     = 3600
}

# MTA-STS CNAME
resource "cloudflare_dns_record" "mta_sts" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "mta-sts"
  content = local.mail_hostname
  type    = "CNAME"
  ttl     = 3600
  proxied = false
}

# Autoconfig (Thunderbird etc.)
resource "cloudflare_dns_record" "autoconfig" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "autoconfig"
  content = local.mail_hostname
  type    = "CNAME"
  ttl     = 3600
  proxied = false
}

# Autodiscover (Outlook)
resource "cloudflare_dns_record" "autodiscover" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "autodiscover"
  content = local.mail_hostname
  type    = "CNAME"
  ttl     = 3600
  proxied = false
}

# SRV records for email client autoconfiguration
resource "cloudflare_dns_record" "srv_imaps" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_imaps._tcp"
  type    = "SRV"
  ttl     = 3600
  data = {
    priority = 0
    weight   = 1
    port     = 993
    target   = local.mail_hostname
  }
}

resource "cloudflare_dns_record" "srv_submissions" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_submissions._tcp"
  type    = "SRV"
  ttl     = 3600
  data = {
    priority = 0
    weight   = 1
    port     = 465
    target   = local.mail_hostname
  }
}
