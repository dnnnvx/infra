locals {
  # name → IP mappings for /etc/hosts on each node and router DNS output
  dns_entries = [
    for name, ip in merge(
      { for name, node in var.nodes : name => node.ip },
      { (var.cluster_name) = var.cluster_vip },
    ) : { ip = ip, aliases = [name] }
  ]

  node_patches = {
    for name, node in var.nodes : name => yamlencode({
      machine = merge({
        nodeLabels = {
          "node.kubernetes.io/name"            = name
          "topology.kubernetes.io/region"      = node.region
          "topology.kubernetes.io/zone"        = node.zone
          "cluster.casasulgorgo.net/node-type" = node.node-type
          "cluster.casasulgorgo.net/cpu-class" = node.cpu-class
          "cluster.casasulgorgo.net/gpu-class" = node.gpu-class
          "cluster.casasulgorgo.net/storage"   = node.storage
        },

        install = {
          disk              = node.install_disk
          wipe              = true
          grubUseUKICmdline = false
        }

        network = {
          # use deviceSelector instead of interface name — avoids dependency on
          # net.ifnames=0 and works across NUCs with different NIC drivers
          interfaces = [
            merge(
              {
                deviceSelector = { physical = true }
                dhcp           = false
                addresses      = ["${node.ip}/${node.prefix_length}"]
                routes         = [{ network = "0.0.0.0/0", gateway = node.gateway }]
              },
              node.machine_type == "controlplane" ? { vip = { ip = var.cluster_vip } } : {}
            ),
          ]

          nameservers = node.nameservers

          extraHostEntries = local.dns_entries
        }

        kubelet = {
          nodeIP = {
            validSubnets = ["${node.ip}/32"]
          }
          extraConfig = merge(
            {
              # Keep CPU and memory back from pods for the OS and the kubelet: with Talos' defaults
              # (50m CPU, no kubeReserved) a Rust build in CI starved nuc-103's kubelet into NotReady.
              # Setting systemReserved replaces Talos' defaults, so pid/ephemeral-storage are repeated.
              systemReserved = {
                cpu                 = "100m"
                memory              = "512Mi"
                pid                 = "100"
                "ephemeral-storage" = "256Mi"
              }
              kubeReserved = {
                cpu    = "200m"
                memory = "256Mi"
              }
            },
            length(node.taints) > 0 ? {
              registerWithTaints = [
                for t in node.taints : {
                  key    = t.key
                  value  = t.value
                  effect = t.effect
                }
              ]
            } : {},
          )
        }
        }, length(node.extra_disks) > 0 ? {
        disks = [
          for d in node.extra_disks : {
            device     = d.device
            partitions = [{ mountpoint = d.mountpoint }]
          }
        ]
      } : {})
    })
  }
}
