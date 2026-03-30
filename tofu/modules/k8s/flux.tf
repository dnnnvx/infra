resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  create_namespace = true

  values = [yamlencode({
    web = {
      config = {
        baseURL = "https://flux.casasulgorgo.net"
        authentication = {
          type = "OAuth2"
          oauth2 = {
            provider     = "OIDC"
            issuerURL    = "https://auth.casasulgorgo.net"
            clientID     = var.flux_web_client_id
            clientSecret = var.flux_web_client_secret
          }
        }
      }
    }
  })]
}

resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  values = [var.flux_instance_values]
}
