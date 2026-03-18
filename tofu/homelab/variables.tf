# GitHub

variable "github_token" {
  description = "GitHub personal access token for managing the infra repository"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
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
