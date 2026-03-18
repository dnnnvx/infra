variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read and DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "zone_name" {
  description = "Cloudflare zone (domain) to manage"
  type        = string
}

variable "r2_buckets" {
  description = "R2 buckets to create. Key is the bucket name."
  type = map(object({
    location = optional(string, "WEUR")
  }))
  default = {}
}

variable "cname_subdomains" {
  description = "Subdomains to create as CNAMEs pointing to the apex (e.g. [\"ha\"])"
  type        = list(string)
  default     = []
}
