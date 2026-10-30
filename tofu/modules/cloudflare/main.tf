module "domain" {
  source   = "./domain"
  for_each = var.domains

  zone_name        = each.key
  cname_subdomains = each.value.cname_subdomains
  local_gateway_ip = each.value.local_gateway_ip
  atproto_did      = each.value.atproto_did
}

resource "cloudflare_r2_bucket" "this" {
  for_each   = var.r2_buckets
  account_id = var.cloudflare_account_id
  name       = each.key
  location   = each.value.location
}
