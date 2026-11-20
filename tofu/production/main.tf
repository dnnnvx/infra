terraform {
  required_version = "1.13.2"

  backend "s3" {
    bucket                      = "tofu-state"
    encrypt                     = true
    endpoint                    = "https://997f91bd76e7456df317ac9ac3fff92b.r2.cloudflarestorage.com"
    key                         = "homelab/terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
    # access_key                  = "<redacted>"
    # secret_key                  = "<redacted>"
  }

  encryption {
    key_provider "pbkdf2" "this" {
      passphrase = var.passphrase
    }

    method "aes_gcm" "this" {
      keys = key_provider.pbkdf2.this
    }

    state {
      method = method.aes_gcm.this
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

locals {
  atproto_did = "did:plc:qzac7ebdharodtvwlxb7wsof"

  # Pinned rather than ssh-keyscan'd on every plan (tofu-controller runs this in-cluster).
  # Re-check after a host key rotation: https://api.github.com/meta (ssh_keys).
  # tangled.org stays only while Flux moves its sources to GitHub: drop it afterwards.
  git_known_hosts = <<-EOT
    github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
    tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2UShEm/FFPmYZUizaPnIqOJuynoCQpcLhl5PPHd02n
  EOT

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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  owner = "dnnnvx"
  token = var.github_token
}

module "talos" {
  source = "../modules/talos"

  cluster_name = "production"
  cluster_vip  = "192.168.0.100"

  talos_version      = "v1.13"
  talos_version_full = "v1.13.12"
  kubernetes_version = "v1.36.4"

  # waits for all nodes to be healthy after apply (blocks if a node is down)
  health_check_enabled = false

  image_factory_extensions = [
    # load "drbd" and "drbd_transport_tcp" kernel modules
    "siderolabs/drbd",
  ]

  extra_config_patches = [
    yamlencode({
      machine = {
        kernel = {
          modules = [
            {
              name       = "drbd"
              parameters = ["usermode_helper=disabled"]
            },
            {
              name = "drbd_transport_tcp"
            },
            {
              name = "dm_thin_pool"
            },
          ]
        }
      }
    }),
    # zot is served on the LAN Gateway (homelab-local, LB IP pinned in
    # infrastructure/configs/cilium/gateway-local.yaml). Pinned in /etc/hosts so
    # image pulls don't depend on DNS; host DNS also answers CoreDNS, so pods
    # (Tekton, Chains, Flux) resolve it the same way.
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "StaticHostConfig"
      name       = "192.168.0.202"
      hostnames  = ["registry.local.casasulgorgo.net"]
    }),
  ]

  # install_disk: device name while booted from USB
  # (may shift after USB removal; Talos uses disk UUID post-install)
  nodes = {
    "nuc-101" = {
      machine_type = "controlplane"
      ip           = "192.168.0.101"
      # endpoint     = "192.168.0.199"
      gateway      = "192.168.0.1"
      install_disk = "/dev/sdb"
      region       = "production"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "J3455"
      gpu-class    = "HD500"
      # WireGuard endpoint: must hold the VIP, so keep it on a controlplane node
      extra_patches = [module.wireguard.config_patch]
    }
    "nuc-102" = {
      machine_type = "worker"
      ip           = "192.168.0.102"
      # endpoint     = "192.168.0.20"
      gateway      = "192.168.0.1"
      install_disk = "/dev/sda" # not the NVMe: its PM961 hangs on cold boot (docs/src/hardware.md)
      region       = "production"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "i3-7100U"
      gpu-class    = "HD620"
      storage      = "hdd"
    }
    "nuc-103" = {
      machine_type = "worker"
      ip           = "192.168.0.103"
      # endpoint     = "192.168.0.199"
      gateway      = "192.168.0.1"
      install_disk = "/dev/sdb"
      region       = "production"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "J5005"
      gpu-class    = "HD605"
      storage      = "local"
    }
    "nuc-104" = {
      machine_type = "worker"
      ip           = "192.168.0.104"
      # endpoint     = "192.168.0.199"
      gateway      = "192.168.0.1"
      install_disk = "/dev/sdb"
      region       = "production"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "J5005"
      gpu-class    = "HD605"
      storage      = "local"
    }
  }
}

# Remote access (docs/src/remote-access.md): WireGuard on nuc-101, the router forwards 51820/udp to it.
# Clients route the VIP and node IP through the tunnel; both are local addresses of nuc-101, so the
# node doesn't forward anything and kubeconfig/talosconfig work unchanged.
module "wireguard" {
  source = "../modules/wireguard"

  hostname   = var.wireguard_hostname
  routed_ips = ["192.168.0.100", "192.168.0.101"]
  peers = {
    laptop = "10.10.0.2",
    phone  = "10.10.0.3",
  }
}

module "cloudflare" {
  source = "../modules/cloudflare"

  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_buckets            = { "tofu-state" = {} }

  domains = {
    "casasulgorgo.net" = {
      cname_subdomains = ["ha", "auth", "uptime", "recipes", "flux", "books", "ci", "matrix"]
      atproto_did      = local.atproto_did
      # homelab-local Gateway (infrastructure/configs/cilium/gateway-local.yaml)
      local_gateway_ip = "192.168.0.202"
      # Raspberry Pis (Nix), each IP is a DHCP reservation on the router
      local_hosts = {
        "rpi-1" = "192.168.0.111"
      }
    }
    "marcods.dev" = {
      cname_subdomains = ["rad", "git", "notes"]
      atproto_did      = local.atproto_did
    }
  }
}

# Webhook HMAC secrets: GitHub gets them here, the cluster through flux-substitutions
# (infrastructure/configs/tekton/triggers/github-webhook-secret.yaml, infrastructure/configs/flux/receiver-token.yaml)
resource "random_password" "github_webhook" {
  length  = 48
  special = false
}

resource "random_password" "flux_receiver" {
  length  = 48
  special = false
}

module "github" {
  source = "../modules/github"

  repositories = {
    # CI-built (ci_webhook: Trigger in apps/<project>/ci.yaml or infrastructure/configs/tekton/triggers/)
    infra = {
      description = "Homelab cluster as code"
      topics      = ["fluxcd", "gitops", "homelab", "iac", "kubernetes", "talos", "tofu"]
      ci_webhook  = true
    }
    casasulgorgo = {
      description  = "Local nature, season by season"
      homepage_url = "https://casasulgorgo.net"
      has_wiki     = true
      ci_webhook   = true
    }
    kubbot = {
      description = "A Matrix bot for the homelab (flux, kyverno, tekton, k8s)"
      has_wiki    = true
      topics      = ["alerting", "alerts", "bot", "chat", "ci", "cicd", "fluxcd", "kyverno", "matrix", "tekton"]
      ci_webhook  = true
    }
    marcods = {
      description = "Portfolio / website"
      visibility  = "private"
      ci_webhook  = true
    }
    # settings only
    nix = {
      description = "Macbook and Raspberry Pis setup"
      has_wiki    = true
      topics      = ["dotfiles", "home-manager", "nix"]
    }
    radicle-images = {
      description  = "Radicle container images"
      homepage_url = "https://github.com/dnnnvx?tab=packages&repo_name=radicle-images"
      has_wiki     = true
      topics       = ["container", "containerization", "containers", "docker", "docker-compose", "docker-image", "dockerfile", "kubernetes", "radicle"]
    }
    dnnnvx = {
      description = "dnnnvx meets dnnnvx"
      has_wiki    = true
    }
    tangled-interceptor = {
      description = "Tekton interceptor that verifies Tangled webhook signatures."
      has_wiki    = true
      topics      = ["cicd", "interceptor", "tangled", "tekton", "webhook"]
    }
    dotfiles = {
      description = "dot dot :lizard:"
      has_wiki    = true
      topics      = ["configuration", "dotfiles"]
    }
    solzk = {
      description = "Solidity / ZK circuits / Test & Exercises"
      has_wiki    = true
    }
  }

  ci_webhook = {
    url    = "https://ci.casasulgorgo.net/"
    secret = random_password.github_webhook.result
  }

  flux = {
    repository     = "infra"
    deploy_key_pub = var.flux_deploy_key_pub
    # Flux's path is /hook/sha256(token + name + namespace) of the Receiver (infrastructure/configs/flux/receiver.yaml)
    receiver_url    = "https://flux.casasulgorgo.net/hook/${sha256("${random_password.flux_receiver.result}github-pushflux-system")}"
    receiver_secret = random_password.flux_receiver.result
  }
}

# Repositories and the Flux deploy key created by hand before tofu managed GitHub. The key was read-only:
# deploy keys are immutable, so the first apply replaces it with a read-write one.
import {
  for_each = toset(["infra", "casasulgorgo", "kubbot", "marcods", "nix", "radicle-images", "dnnnvx", "tangled-interceptor", "dotfiles", "solzk"])
  to       = module.github.github_repository.repos[each.key]
  id       = each.key
}

import {
  to = module.github.github_repository_deploy_key.flux
  id = "infra:145162879"
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
