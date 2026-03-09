variable "cluster_name" {
  description = "The Talos cluster name (used in machine config)"
  type        = string
}

variable "cluster_vip" {
  description = "Floating VIP shared across controlplane nodes for the cluster API endpoint"
  type        = string
}

variable "project" {
  description = "Project name used in node labels"
  type        = string
}

variable "talos_version" {
  description = "Short Talos version for secrets/config generation (e.g. v1.12)"
  type        = string
}

variable "talos_version_full" {
  description = "Full Talos version for image factory (e.g. v1.12.4)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g. v1.35.0)"
  type        = string
}

variable "nodes" {
  description = "Map of node definitions keyed by node name"
  type = map(object({
    machine_type  = string
    ip            = string
    endpoint      = optional(string) # override connection IP (e.g. DHCP IP in maintenance mode)
    gateway       = string
    install_disk  = string
    region        = string
    zone          = string
    prefix_length = optional(number, 24)
    node-type     = optional(string, "")
    cpu-class     = optional(string, "")
    gpu-class     = optional(string, "")
    storage       = optional(string, "")
    nameservers   = optional(list(string), ["192.168.0.1", "1.1.1.1", "8.8.8.8"])
    extra_disks = optional(list(object({
      device     = string
      mountpoint = string
    })), [])
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  validation {
    condition = alltrue([
      for name, node in var.nodes :
      contains(["controlplane", "worker"], node.machine_type)
    ])
    error_message = "machine_type must be 'controlplane' or 'worker'."
  }

  validation {
    condition     = length([for n, v in var.nodes : n if v.machine_type == "controlplane"]) >= 1
    error_message = "At least one controlplane node must be defined."
  }
}

variable "image_factory_extensions" {
  description = "List of official Talos system extensions to include in the image schematic"
  type        = list(string)
  default     = []
}

variable "extra_config_patches" {
  description = "Additional config patches applied to all nodes"
  type        = list(string)
  default     = []
}

variable "health_check_enabled" {
  description = "Enable cluster health check after bootstrap"
  type        = bool
  default     = true
}
