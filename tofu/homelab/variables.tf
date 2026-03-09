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
