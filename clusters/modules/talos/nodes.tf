locals {
  cluster_endpoint = "https://${var.cluster_vip}:6443"

  controlplane_nodes = {
    for name, node in var.nodes : name => node
    if node.machine_type == "controlplane"
  }

  worker_nodes = {
    for name, node in var.nodes : name => node
    if node.machine_type == "worker"
  }

  controlplane_ips = [for name, node in local.controlplane_nodes : node.ip]
  worker_ips       = [for name, node in local.worker_nodes : node.ip]

  shared_patches = concat(
    [
      # Installer image + kernel args
      yamlencode({
        machine = {
          install = {
            image = data.talos_image_factory_urls.this.urls.installer
            extraKernelArgs = [
              "net.ifnames=0",
              "init_on_alloc=1",
              "init_on_free=1",
              "slab_nomerge",
              "pti=on",
            ]
          }
        }
      }),
      # Disable default CNI (Cilium installed separately)
      yamlencode({
        cluster = {
          network = {
            cni = {
              name = "none"
            }
          }
          proxy = {
            disabled = true
          }
        }
      }),
      # Allow scheduling on control planes
      yamlencode({
        cluster = {
          allowSchedulingOnControlPlanes = true
        }
      }),
      # Disable cluster discovery
      yamlencode({
        cluster = {
          discovery = {
            enabled = false
          }
        }
      }),
    ],
    var.extra_config_patches,
  )


}

data "talos_machine_configuration" "this" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = each.value.machine_type
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  docs     = false
  examples = false

  config_patches = concat(
    local.shared_patches,
    [
      local.node_patches[each.key],
      # HostnameConfig document — sets hostname without conflicting with v1alpha1 auto hostname
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = each.key
        auto       = "off"
      }),
    ],
  )
}

resource "talos_machine_configuration_apply" "this" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  node                        = each.value.ip
  endpoint                    = coalesce(each.value.endpoint, each.value.ip)
  apply_mode                  = "auto"
}

data "talos_cluster_health" "this" {
  count      = var.health_check_enabled ? 1 : 0
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  control_plane_nodes  = local.controlplane_ips
  worker_nodes         = local.worker_ips

  timeouts = {
    read = "10m"
  }
}
