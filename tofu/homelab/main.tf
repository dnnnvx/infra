terraform {
  backend "local" {}

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
  }
}

locals {
  project = "homelab"

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

module "talos" {
  source  = "../modules/talos"
  project = local.project

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
          ]
        }
      }
    }),
  ]

  cluster_name = local.project
  cluster_vip  = "192.168.0.100"

  # install_disk: device name while booted from USB
  # (may shift after USB removal; Talos uses disk UUID post-install)
  nodes = {
    "nuc-101" = {
      machine_type = "controlplane"
      ip           = "192.168.0.101"
      # endpoint     = "192.168.0.199"
      gateway      = "192.168.0.1"
      install_disk = "/dev/sdb"
      region       = "homelab"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "J3455"
      gpu-class    = "HD500"
    }
    "nuc-102" = {
      machine_type = "worker"
      ip           = "192.168.0.102"
      # endpoint     = "192.168.0.199"
      gateway      = "192.168.0.1"
      install_disk = "/dev/nvme0n1"
      region       = "homelab"
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
      region       = "homelab"
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
      region       = "homelab"
      zone         = "office"
      node-type    = "nuc"
      cpu-class    = "J5005"
      gpu-class    = "HD605"
      storage      = "local"
    }
  }
}

module "k8s" {
  source = "../modules/k8s"

  cilium_values        = file("${path.module}/../../clusters/homelab/values/cilium.yaml")
  flux_instance_values = file("${path.module}/../../clusters/homelab/values/flux-instance.yaml")
  flux_deploy_key      = var.flux_deploy_key
  flux_deploy_key_pub  = var.flux_deploy_key_pub
  flux_substitutions   = var.flux_substitutions
  sops_age_key         = var.sops_age_key
}
