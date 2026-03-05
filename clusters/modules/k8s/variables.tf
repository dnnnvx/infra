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
