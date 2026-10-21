# Keys are generated once and kept in the (encrypted) state;
# private keys only leave it through the client_configs output.
resource "wireguard_asymmetric_key" "server" {}

resource "wireguard_asymmetric_key" "peer" {
  for_each = var.peers
}

locals {
  server_ip = split("/", var.address)[0]
}
