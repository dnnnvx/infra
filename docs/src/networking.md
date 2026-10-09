# Networking

## Internal (LAN)

| Hostname      | Service        |
|---------------|----------------|
| `ha.home`     | Home Assistant |
| `hubble.home` | Hubble UI      |
| `flux.home`   | Flux Operator  |
| `nvr.home`    | LightNVR       |

All internal services share a single Cilium Gateway at `192.168.0.200` (HTTP, port 80).
DNS is handled by AdGuard Home (`192.168.0.201`), configured via DHCP on the router. Each `*.home` hostname resolves to `192.168.0.200`.

## External (Internet)

| Hostname                | Service        |
|-------------------------|----------------|
| `ha.casasulgorgo.net`   | Home Assistant |
| `auth.casasulgorgo.net` | Pocket-ID      |
| `casasulgorgo.net`      | Landing page   |
| `ci.casasulgorgo.net`   | Tekton EventListener (Tangled webhooks) |
| `registry.casasulgorgo.net` | zot UI only (no push/pull) |

Image traffic never leaves the cluster: everything uses `zot.zot.svc.cluster.local:5000`, and nodes reach it through a Talos registry mirror on a pinned ClusterIP (see [CI/CD](./cicd.md)).

External access via Cloudflare proxy (orange cloud) → port-forward 443 → Cilium Gateway (HTTPS, port 443).
TLS terminated at the Gateway using a Let's Encrypt wildcard cert (`*.casasulgorgo.net`) issued via DNS-01.
DDNS (`favonia/cloudflare-ddns`) keeps the apex A record updated with the home public IP.

## DNS notes

- Router DHCP advertises AdGuard (`192.168.0.201`) as DNS server
- IPv6 RA DNS must be disabled on the router — otherwise macOS prefers `fe80::1` over DHCP DNS
- iCloud Private Relay ("Limit IP Address Tracking") intercepts DNS at `127.0.2.2` — disable per-network if custom DNS stops working
- macOS DNS cache: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
