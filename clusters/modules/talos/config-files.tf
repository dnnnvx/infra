data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = [for name, node in var.nodes : node.ip]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = var.cluster_vip
  endpoint             = var.cluster_vip
  client_configuration = talos_machine_secrets.this.client_configuration
}
