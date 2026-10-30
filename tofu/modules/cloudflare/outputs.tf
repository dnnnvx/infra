output "cluster_api_token" {
  description = "Cloudflare API token for cluster services (cert-manager, DDNS)"
  value       = var.cloudflare_api_token
  sensitive   = true
}

output "zone_ids" {
  value = { for domain, config in module.domain : domain => config.zone_id }
}

output "account_id" {
  value = var.cloudflare_account_id
}
