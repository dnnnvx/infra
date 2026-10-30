variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read and DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "domains" {
  description = "Cloudflare zones to manage, keyed by domain. Fields are described in ./domain/variables.tf."
  type = map(object({
    cname_subdomains = optional(list(string), [])
    local_gateway_ip = optional(string)
    atproto_did      = optional(string)
  }))
}

variable "r2_buckets" {
  description = "R2 buckets to create. Key is the bucket name."
  type = map(object({
    location = optional(string, "WEUR")
  }))
  default = {}
}
