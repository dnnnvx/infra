# Remote access

`kubectl` and `talosctl` from outside the LAN go through a WireGuard tunnel ending on the
controlplane `nuc-101` (Talos `WireguardConfig` document, `wg0`, `10.10.0.1/24`, `51820/udp`).
The ISP router can't run WireGuard, so it forwards `51820/udp` to `192.168.0.101`.

The tunnel lives on the node, so it's down whenever `nuc-101` is. That's accepted: with a single
controlplane, the API is down then too.

## How it routes

Clients route `192.168.0.100/32` (VIP) and `192.168.0.101/32` through the tunnel. Both are local
addresses of `nuc-101`, so the node never forwards or masquerades, and the usual kubeconfig
(`https://192.168.0.100:6443`) and talosconfig (endpoint `192.168.0.101`) work unchanged.
Other nodes are reached through apid's proxy: `talosctl -n 192.168.0.103 …`.
Nothing else on the LAN (`*.local`, AdGuard, the registry) is reachable through the tunnel.

If the VIP ever moves to another controlplane, kubectl over the tunnel stops working until the
client's `AllowedIPs` and the endpoint node change with it.

Turn the tunnel off at home: the same `/32`s would otherwise hairpin through the router.

## Configuration (tofu)

`tofu/modules/wireguard` generates the server and client keys (`ojford/wireguard` provider), and outputs the
Talos `WireguardConfig` patch (applied to nuc-101 via its `extra_patches`) and the client configs. Private keys
live only in the encrypted state and in those configs. Devices are listed in the module's `peers`
(`tofu/production/main.tf`, name → `10.10.0.x`).

`wireguard_hostname` (`terraform.tfvars`) is the DNS-only record DDNS points at the home IP, used as the
clients' `Endpoint`. It's kept out of git because a DNS-only record exposes the home IP. Tofu writes it into the
`domains` key of the `ddns/cloudflare-api-token` Secret, next to the apex, and `cloudflare-ddns` creates it
unproxied (`PROXIED=is(casasulgorgo.net)`: only the apex is proxied).

Unauthenticated packets get no reply, so the open port is invisible to scanners. A leaked client key only
gives network reachability: the Talos and Kubernetes APIs still need their mTLS client certs.

## Adding a device

Add it to the module's `peers` with the next free address and `tofu apply` (live-applied, no reboot).
Then import its config, and delete the file once imported:

```bash
tofu output -json wireguard_client_configs | jq -r .laptop > laptop.conf   # WireGuard app: import from file
tofu output -json wireguard_client_configs | jq -r .phone | qrencode -t ansiutf8   # mobile: scan QR
```

Remove a lost device by deleting its entry and applying: its key is destroyed with it.
Rotate the server key with `tofu apply -replace=module.wireguard.wireguard_asymmetric_key.server`, then re-import every client.
