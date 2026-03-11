output "known_hosts" {
  description = "GitHub SSH known_hosts entries, ready for use in the flux-system Secret"
  value       = local.github_known_hosts
}
