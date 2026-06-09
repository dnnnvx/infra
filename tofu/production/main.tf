terraform {
  backend "s3" {}

  encryption {
    key_provider "pbkdf2" "this" {
      passphrase = var.passphrase
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

locals {
  atproto_did = "did:plc:qzac7ebdharodtvwlxb7wsof"

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
  kubernetes {
    host                   = module.talos.kubernetes_client_configuration.host
    client_certificate     = local.client_certificate
    client_key             = local.client_key
    cluster_ca_certificate = local.cluster_ca_certificate
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

data "external" "tangled_known_hosts" {
  program = ["sh", "-c", "ssh-keyscan tangled.org 2>/dev/null | grep -v '^#' | jq -Rsc '{known_hosts: .}'"]
}

module "talos" {
  source  = "../modules/talos"
  project = "production"

  cluster_name = "production"
  cluster_vip  = "192.168.0.100"

  talos_version      = "v1.12"
  talos_version_full = "v1.12.4"
  kubernetes_version = "v1.35.0"

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
    }
    "nuc-102" = {
      machine_type = "worker"
      ip           = "192.168.0.102"
      # endpoint     = "192.168.0.19"
      gateway      = "192.168.0.1"
      install_disk = "/dev/nvme0n1"
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

module "cloudflare" {
  source = "../modules/cloudflare"

  cloudflare_account_id = var.cloudflare_account_id
  zone_name             = "casasulgorgo.net"
  cloudflare_api_token  = var.cloudflare_api_token
  cname_subdomains      = ["ha", "auth", "uptime", "recipes", "task", "flux", "books"]
  r2_buckets            = { "tofu-state" = {} }
  atproto_did           = local.atproto_did
}

module "k8s" {
  source = "../modules/k8s"

  cilium_values        = file("${path.module}/../../infrastructure/cilium/overlays/production/values.yaml")
  flux_operator_values = file("${path.module}/../../infrastructure/flux/overlays/production/values-operator.yaml")
  flux_instance_values = file("${path.module}/../../infrastructure/flux/overlays/production/values-instance.yaml")

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
        known_hosts    = data.external.tangled_known_hosts.result.known_hosts
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
      data      = { api-token = module.cloudflare.cluster_api_token }
    },
  ]
}
