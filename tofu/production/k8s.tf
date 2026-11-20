locals {
  client_certificate     = base64decode(module.talos.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(module.talos.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(module.talos.kubernetes_client_configuration.ca_certificate)
}

provider "kubernetes" {
  host                   = module.talos.kubernetes_client_configuration.host
  client_certificate     = local.client_certificate
  client_key             = local.client_key
  cluster_ca_certificate = local.cluster_ca_certificate
}

provider "helm" {
  kubernetes = {
    host                   = module.talos.kubernetes_client_configuration.host
    client_certificate     = local.client_certificate
    client_key             = local.client_key
    cluster_ca_certificate = local.cluster_ca_certificate
  }
}

module "k8s" {
  source = "../modules/k8s"

  cilium_values        = file("${path.module}/../../infrastructure/controllers/cilium/values.yaml")
  flux_operator_values = file("${path.module}/../../infrastructure/controllers/flux/values-operator.yaml")
  flux_instance_values = file("${path.module}/../../infrastructure/controllers/flux/values-instance.yaml")

  namespaces = [
    "cert-manager",
    "ddns",
  ]

  secrets = [
    {
      name      = "flux-system"
      namespace = "flux-system"
      data = {
        identity       = var.flux_deploy_key
        "identity.pub" = var.flux_deploy_key_pub
        known_hosts    = local.git_known_hosts
      }
    },
    {
      name      = "sops-age"
      namespace = "flux-system"
      data      = { "age.agekey" = var.sops_age_key }
    },
    {
      name      = "flux-substitutions"
      namespace = "flux-system"
      data = merge(var.flux_substitutions, {
        github_webhook_secret = random_password.github_webhook.result
        flux_receiver_token   = random_password.flux_receiver.result
        }, {
        # base64 so the multi-line key substitutes into a Secret's data on one line
        for repo, key in tls_private_key.ci_clone :
        "git_ssh_key_${replace(repo, "-", "_")}" => base64encode(key.private_key_openssh)
      })
    },
    {
      name      = "cloudflare-api-token"
      namespace = "cert-manager"
      data      = { api-token = module.cloudflare.cluster_api_token }
    },
    {
      name      = "cloudflare-api-token"
      namespace = "ddns"
      data = {
        api-token = module.cloudflare.cluster_api_token
        # the WireGuard hostname exposes the home IP, so it's kept out of git
        domains = join(",", compact(["casasulgorgo.net", "marcods.dev", var.wireguard_hostname]))
      }
    },
  ]
}
