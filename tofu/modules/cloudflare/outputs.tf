output "cluster_api_token" {
  description = "Cloudflare API token for cluster services (cert-manager, external-dns, DDNS)"
  value       = var.cloudflare_api_token
  sensitive   = true
}

output "zone_id" {
  value = data.cloudflare_zone.main.zone_id
}
