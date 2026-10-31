terraform {
  required_version = "1.13.1"

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
  }
}

locals {
  atproto_did = "did:plc:qzac7ebdharodtvwlxb7wsof"

  # Pinned rather than ssh-keyscan'd on every plan (tofu-controller runs this in-cluster).
  # Re-check after a host key rotation: ssh-keyscan tangled.org
  tangled_known_hosts = "tangled.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII2UShEm/FFPmYZUizaPnIqOJuynoCQpcLhl5PPHd02n\n"

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
      install_disk = "/dev/sda" # "/dev/nvme0n1"
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
      cname_subdomains = ["ha", "auth", "uptime", "recipes", "notes", "flux", "books", "ci", "matrix"]
      atproto_did      = local.atproto_did
      local_gateway_ip = "192.168.0.202" # homelab-local Gateway (infrastructure/configs/cilium/gateway-local.yaml)
    }
    "marcods.dev" = {
      atproto_did = local.atproto_did
    }
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
        known_hosts    = local.tangled_known_hosts
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
      data      = var.flux_substitutions
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
