output "machine_secrets" {
  description = "Machine secrets for disaster recovery"
  value       = talos_machine_secrets.this.machine_secrets
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "installer_image" {
  description = "Talos installer image URL for manual node installs"
  value       = data.talos_image_factory_urls.this.urls.installer
}

output "dns_entries" {
  description = "DNS mappings for router configuration"
  value       = local.dns_entries
}

output "kubernetes_client_configuration" {
  description = "Kubernetes client configuration for provider authentication"
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}
