data "external" "github_known_hosts" {
  program = ["bash", "-c", "ssh-keyscan github.com 2>/dev/null | jq -Rs '{known_hosts: .}'"]
}

resource "github_repository_deploy_key" "flux" {
  title      = "flux-homelab"
  repository = var.repository
  key        = var.deploy_key_pub
  read_only  = true
}
