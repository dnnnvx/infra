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

variable "mail_subdomain" {
  description = "Mail server subdomain"
  type        = string
  default     = "mail"
}

# variable "dkim_ed25519_selector" {
#   description = "DKIM Ed25519 selector (e.g. 202603e)"
#   type        = string
# }
#
# variable "dkim_ed25519_pubkey" {
#   description = "DKIM Ed25519 public key"
#   type        = string
# }
#
# variable "dkim_rsa_selector" {
#   description = "DKIM RSA selector (e.g. 202603r)"
#   type        = string
# }
#
# variable "dkim_rsa_pubkey" {
#   description = "DKIM RSA public key"
#   type        = string
# }
