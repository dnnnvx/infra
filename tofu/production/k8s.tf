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
    "rustfs",
    "tekton-ci",
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
        # base64 so the multi-line key substitutes on one line (git-ssh stringData, decoded by git-clone)
        for repo, key in tls_private_key.ci_clone :
        "git_ssh_key_${replace(repo, "-", "_")}" => base64encode(key.private_key_openssh)
      })
    },
    {
      # Root credentials (console, admin API, the rustfs provider). Clients get their own keys.
      name      = "rustfs-root"
      namespace = "rustfs"
      data = {
        RUSTFS_ACCESS_KEY = random_password.rustfs_access_key.result
        RUSTFS_SECRET_KEY = random_password.rustfs_secret_key.result
      }
    },
    {
      # Nix binary cache on RustFS: the build steps read, only the push-cache step writes
      name      = "nix-cache-read"
      namespace = "tekton-ci"
      data      = module.rustfs.credentials["nix-cache-read"]
    },
    {
      name      = "nix-cache-write"
      namespace = "tekton-ci"
      data      = module.rustfs.credentials["nix-cache-write"]
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

# Created by Flux before tofu owned Secrets in them; Flux keeps managing their labels
import {
  to = module.k8s.kubernetes_namespace_v1.namespaces["rustfs"]
  id = "rustfs"
}

import {
  to = module.k8s.kubernetes_namespace_v1.namespaces["tekton-ci"]
  id = "tekton-ci"
}
