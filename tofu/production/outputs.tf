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

output "wireguard_server_public_key" {
  value = module.wireguard.server_public_key
}

output "wireguard_client_configs" {
  description = "wg-quick configs per device: tofu output -json wireguard_client_configs | jq -r .<device>"
  value       = module.wireguard.client_configs
  sensitive   = true
}

output "dns_entries" {
  description = "DNS mappings for router configuration"
  value       = module.talos.dns_entries
}
