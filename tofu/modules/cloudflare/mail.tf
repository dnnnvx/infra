locals {
  mail_hostname = "${var.mail_subdomain}.${var.zone_name}"
}

# mail subdomain — unproxied so SMTP/IMAP traffic goes direct (Cloudflare proxy only handles HTTP)
resource "cloudflare_dns_record" "mail" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.mail_subdomain
  content = var.zone_name
  type    = "CNAME"
  ttl     = 1
  proxied = false
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

# SPF for mail subdomain: allow the mail host's own IP to send
resource "cloudflare_dns_record" "spf_mail" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.mail_subdomain
  content = "v=spf1 a ra=postmaster -all"
  type    = "TXT"
  ttl     = 3600
}

# DMARC
resource "cloudflare_dns_record" "dmarc" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=reject; rua=mailto:postmaster@${var.zone_name}; ruf=mailto:postmaster@${var.zone_name}"
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

# TLS reporting
resource "cloudflare_dns_record" "tls_rpt" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_smtp._tls"
  content = "v=TLSRPTv1; rua=mailto:postmaster@${var.zone_name}"
  type    = "TXT"
  ttl     = 3600
}

# DKIM Ed25519
resource "cloudflare_dns_record" "dkim_ed25519" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.dkim_ed25519_selector}._domainkey"
  content = "v=DKIM1; k=ed25519; h=sha256; p=${var.dkim_ed25519_pubkey}"
  type    = "TXT"
  ttl     = 3600
}

# DKIM RSA
resource "cloudflare_dns_record" "dkim_rsa" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "${var.dkim_rsa_selector}._domainkey"
  content = "v=DKIM1; k=rsa; h=sha256; p=${var.dkim_rsa_pubkey}"
  type    = "TXT"
  ttl     = 3600
}

# Additional SRV records
resource "cloudflare_dns_record" "srv_imap" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_imap._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 143, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_submission" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_submission._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 587, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_jmap" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_jmap._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 443, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_caldavs" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_caldavs._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 443, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_carddavs" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_carddavs._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 443, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_pop3s" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_pop3s._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 995, target = local.mail_hostname }
}

resource "cloudflare_dns_record" "srv_pop3" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_pop3._tcp"
  type    = "SRV"
  ttl     = 3600
  data    = { priority = 0, weight = 1, port = 110, target = local.mail_hostname }
}
