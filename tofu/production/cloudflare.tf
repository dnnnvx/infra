provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

locals {
  atproto_did = "did:plc:qzac7ebdharodtvwlxb7wsof"
}

module "cloudflare" {
  source = "../modules/cloudflare"

  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_buckets            = { "tofu-state" = {} }

  domains = {
    "casasulgorgo.net" = {
      cname_subdomains = ["ha", "auth", "uptime", "recipes", "flux", "books", "ci", "matrix"]
      atproto_did      = local.atproto_did
      # homelab-local Gateway (infrastructure/configs/cilium/gateway-local.yaml)
      local_gateway_ip = "192.168.0.202"
      # Raspberry Pis (Nix), each IP is a DHCP reservation on the router
      local_hosts = {
        "rpi-1" = "192.168.0.111"
      }
    }
    "marcods.dev" = {
      cname_subdomains = ["rad", "git", "notes", "docs"]
      atproto_did      = local.atproto_did
    }
  }
}
