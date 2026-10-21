output "config_patch" {
  description = "Talos WireguardConfig document for the endpoint node"
  value = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "WireguardConfig"
    name       = "wg0"
    privateKey = wireguard_asymmetric_key.server.private_key
    listenPort = var.listen_port
    addresses  = [{ address = var.address }]
    peers = [for name, address in var.peers : {
      publicKey  = wireguard_asymmetric_key.peer[name].public_key
      allowedIPs = ["${address}/32"]
    }]
  })
  sensitive = true
}

output "server_public_key" {
  value = wireguard_asymmetric_key.server.public_key
}

output "client_configs" {
  description = "wg-quick config per device"
  sensitive   = true
  value = {
    for name, address in var.peers : name => <<-EOT
      [Interface]
      PrivateKey = ${wireguard_asymmetric_key.peer[name].private_key}
      Address = ${address}/32

      [Peer]
      PublicKey = ${wireguard_asymmetric_key.server.public_key}
      Endpoint = ${var.hostname}:${var.listen_port}
      AllowedIPs = ${join(", ", concat(["${local.server_ip}/32"], [for ip in var.routed_ips : "${ip}/32"]))}
      PersistentKeepalive = 25
    EOT
  }
}
