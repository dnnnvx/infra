terraform {
  required_version = "1.12.6"

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

locals {
  # Talos default service CIDR (kube-apiserver --service-cluster-ip-range).
  # zot gets a pinned ClusterIP from the static band at its start, because
  # containerd on the nodes can't resolve *.svc.cluster.local. Single source of
  # truth: fed to the Talos registry mirror below and, via flux-substitutions,
  # to the zot Service (ZOT_CLUSTER_IP in infrastructure/controllers/zot/values.yaml).
  service_cidr   = "10.96.0.0/12"
  zot_cluster_ip = cidrhost(local.service_cidr, 50)
}

data "external" "tangled_known_hosts" {
  program = ["sh", "-c", "ssh-keyscan tangled.org 2>/dev/null | grep -v '^#' | jq -Rsc '{known_hosts: .}'"]
}

module "talos" {
  source = "../modules/talos"

  cluster_name = "production"
  cluster_vip  = "192.168.0.100"

  talos_version      = "v1.13"
  talos_version_full = "v1.13.10"
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
    # Images are referenced by zot's in-cluster name, which the node can't
    # resolve: point containerd at zot's pinned ClusterIP over plain HTTP.
    yamlencode({
      apiVersion   = "v1alpha1"
      kind         = "RegistryMirrorConfig"
      name         = "zot.zot.svc.cluster.local:5000"
      endpoints    = [{ url = "http://${local.zot_cluster_ip}:5000" }]
      skipFallback = true
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
    # "nuc-102" = {
    #   machine_type = "worker"
    #   ip           = "192.168.0.102"
    #   # endpoint     = "192.168.0.19"
    #   gateway      = "192.168.0.1"
    #   install_disk = "/dev/nvme0n1"
    #   region       = "production"
    #   zone         = "office"
    #   node-type    = "nuc"
    #   cpu-class    = "i3-7100U"
    #   gpu-class    = "HD620"
    #   storage      = "hdd"
    # }
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
  cname_subdomains      = ["ha", "auth", "uptime", "recipes", "notes", "flux", "books", "romm", "ci", "registry"]
  r2_buckets            = { "tofu-state" = {} }
  atproto_did           = local.atproto_did
  local_gateway_ip      = "192.168.0.202" # homelab-local Gateway (infrastructure/configs/cilium/gateway-local.yaml)
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
      data      = merge(var.flux_substitutions, { ZOT_CLUSTER_IP = local.zot_cluster_ip })
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
