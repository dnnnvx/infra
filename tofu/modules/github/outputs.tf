output "known_hosts" {
  description = "GitHub SSH known_hosts entries, ready for use in the flux-system Secret"
  value       = data.external.github_known_hosts.result.known_hosts
}
