locals {
  first_cp_ip = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.first_cp_ip
  endpoint             = local.first_cp_ip
  client_configuration = talos_machine_secrets.this.client_configuration

  timeouts = {
    create = "10m"
  }
}
