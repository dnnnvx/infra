resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  create_namespace = true
}

resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  values = [var.flux_instance_values]
}

# github auth (ssh deploy key in k8s secrets)

data "external" "github_known_hosts" {
  program = ["bash", "-c", "ssh-keyscan github.com 2>/dev/null | jq -Rs '{known_hosts: .}'"]
}

resource "kubernetes_secret_v1" "flux_system" {
  metadata {
    name      = "flux-system"
    namespace = "flux-system"
  }

  data = {
    identity       = var.flux_deploy_key
    "identity.pub" = var.flux_deploy_key_pub
    known_hosts    = data.external.github_known_hosts.result.known_hosts
  }

  depends_on = [helm_release.flux_operator]
}
