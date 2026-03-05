output "kubeconfig" {
  value     = module.talos.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.talos.talosconfig
  sensitive = true
}

output "machine_secrets" {
  description = "Machine secrets for disaster recovery"
  value       = module.talos.machine_secrets
  sensitive   = true
}

output "installer_image" {
  description = "Talos installer image URL for manual node installs"
  value       = module.talos.installer_image
}

output "dns_entries" {
  description = "DNS mappings for router configuration"
  value       = module.talos.dns_entries
}
