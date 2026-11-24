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
      install_disk = "/dev/sda" # not the NVMe: its PM961 hangs on cold boot (docs/hardware.md)
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

# Remote access (docs/remote-access.md): WireGuard on nuc-101, the router forwards 51820/udp to it.
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
