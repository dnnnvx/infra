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
