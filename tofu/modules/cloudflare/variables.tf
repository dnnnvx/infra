variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read and DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "zone_name" {
  description = "Cloudflare zone (domain) to manage"
  type        = string
}

variable "cname_subdomains" {
  description = "Subdomains to create as CNAMEs pointing to the apex (e.g. [\"ha\"])"
  type        = list(string)
  default     = []
}
