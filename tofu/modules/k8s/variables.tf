variable "cilium_values" {
  description = "YAML values for the Cilium Helm chart"
  type        = string
  default     = ""
}

variable "flux_instance_values" {
  description = "YAML values for the flux-instance Helm chart (FluxInstance spec)"
  type        = string
  default     = ""
}

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
