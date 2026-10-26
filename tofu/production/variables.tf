# State encryption (main.tf `encryption` block)

variable "passphrase" {
  description = "PBKDF2 passphrase for OpenTofu state encryption (min 16 chars); losing it makes the state unreadable"
  type        = string
  sensitive   = true
}

# Cloudflare

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read, API Tokens: Edit, DNS:Edit permissions"
  type        = string
  sensitive   = true
}

# WireGuard (remote access, see docs/src/remote-access.md)

variable "wireguard_hostname" {
  description = "DNS-only record kept pointed at the home IP by DDNS, used as the clients' Endpoint; kept out of git"
  type        = string
}

# Flux

variable "flux_deploy_key" {
  description = "SSH private key for Flux to pull from the git repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flux_deploy_key_pub" {
  description = "SSH public key counterpart of flux_deploy_key"
  type        = string
  default     = ""
}

variable "sops_age_key" {
  description = "Age private key for SOPS decryption by Flux kustomize-controller"
  type        = string
  sensitive   = true
  default     = ""
}

variable "flux_substitutions" {
  description = "Key-value pairs exposed as Flux variable substitutions via the flux_substitutions Secret"
  type        = map(string)
  sensitive   = true
  default     = {}
}
