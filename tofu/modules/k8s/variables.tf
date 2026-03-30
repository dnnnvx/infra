variable "cilium_values" {
  description = "YAML values for the Cilium Helm chart"
  type        = string
  default     = ""
}

variable "flux_operator_values" {
  description = "YAML values for the flux-operator Helm chart"
  type        = string
  default     = ""
}

variable "flux_instance_values" {
  description = "YAML values for the flux-instance Helm chart (FluxInstance spec)"
  type        = string
  default     = ""
}

variable "namespaces" {
  description = "Namespaces to create before applying secrets (bootstrapped outside of Flux)"
  type        = list(string)
  default     = []
}

variable "secrets" {
  description = "Kubernetes secrets to create (e.g. third-party credentials)"
  type = list(object({
    name      = string
    namespace = string
    data      = map(string)
  }))
  default   = []
}
