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
        nodeLabels = merge(
          {
            "node.kubernetes.io/name"         = name
            "topology.kubernetes.io/region"   = node.region
            "topology.kubernetes.io/zone"     = node.zone
            "cluster.sulgorgo.casa/node-type" = node.node-type
            "cluster.sulgorgo.casa/cpu-class" = node.cpu-class
            "cluster.sulgorgo.casa/gpu-class" = node.gpu-class
          }
        )

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

        kubelet = merge(
          {
            nodeIP = {
              validSubnets = ["${node.ip}/32"]
            }
          },
          length(node.taints) > 0 ? {
            extraConfig = {
              registerWithTaints = [
                for t in node.taints : {
                  key    = t.key
                  value  = t.value
                  effect = t.effect
                }
              ]
            }
          } : {},
        )
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
