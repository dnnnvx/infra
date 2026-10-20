# Networking

## Internal (LAN)

| Hostname                         | Service        |
|----------------------------------|----------------|
| `ha.local.casasulgorgo.net`      | Home Assistant |
| `adguard.local.casasulgorgo.net` | AdGuard Home   |
| `uptime.local.casasulgorgo.net`  | Gatus          |
| `hubble.local.casasulgorgo.net`  | Hubble UI      |
| `flux.local.casasulgorgo.net`    | Flux Operator  |
| `nvr.local.casasulgorgo.net`     | LightNVR       |
| `tekton.local.casasulgorgo.net`  | Tekton Dashboard (read-only) |

Internal services share the LAN-only Cilium Gateway `homelab-local` at `192.168.0.202` (HTTPS; HTTP redirects).
The router doesn't forward anything to `.202`, so these routes can't be reached from the internet.
TLS uses the same Let's Encrypt cert, which also covers `*.local.casasulgorgo.net`.
DNS: a DNS-only (not proxied) Cloudflare record `*.local.casasulgorgo.net → 192.168.0.202` (tofu, `local_gateway_ip`),
so every resolver, including browser DoH, gets the same answer. Publishing the private IP is harmless.

Don't attach LAN-only routes to the `homelab` Gateway: its port 443 is forwarded from the internet,
so any route on it is publicly reachable by SNI/Host even without a DNS record.

## External (Internet)

| Hostname                | Service        |
|-------------------------|----------------|
| `ha.casasulgorgo.net`   | Home Assistant |
| `auth.casasulgorgo.net` | Pocket-ID      |
| `casasulgorgo.net`      | Landing page   |
| `ci.casasulgorgo.net`   | Tekton EventListener (Tangled webhooks) |
| `registry.casasulgorgo.net` | zot UI only (no push/pull) |

The registry API is LAN-only: `registry.local.casasulgorgo.net` on the `homelab-local` Gateway (public wildcard cert, so no client needs insecure flags). Nodes and pods resolve it through a Talos `StaticHostConfig` (see [CI/CD](./cicd.md)).

External access via Cloudflare proxy (orange cloud) → port-forward 443 → Cilium Gateway (HTTPS, port 443).
TLS terminated at the Gateway using a Let's Encrypt wildcard cert (`*.casasulgorgo.net`) issued via DNS-01.
DDNS (`favonia/cloudflare-ddns`) keeps the apex A record updated with the home public IP.

## DNS notes

- Router DHCP advertises AdGuard (`192.168.0.201`) as DNS server
- IPv6 RA DNS must be disabled on the router — otherwise macOS prefers `fe80::1` over DHCP DNS
- iCloud Private Relay ("Limit IP Address Tracking") intercepts DNS at `127.0.2.2` — disable per-network if custom DNS stops working
- macOS DNS cache: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
