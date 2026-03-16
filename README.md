# Homelab

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Architecture

```
tofu/                    # OpenTofu (Terraform) — provisions the cluster
├── homelab/             # Cluster definition (nodes, IPs, extensions)
└── modules/
    ├── talos/           # Talos Linux cluster provisioning
    ├── k8s/             # Bootstrap (Cilium, Flux, namespaces, secrets)
    ├── cloudflare/      # DNS records (apex A + subdomain CNAMEs)
    └── github/          # Deploy key + pinned SSH known_hosts

clusters/homelab/        # Flux entry point (synced by FluxInstance)
├── kustomization.yaml   # ConfigMapGenerators for Helm values
├── infrastructure.yaml  # Flux Kustomization → ./infrastructure
├── config.yaml          # Flux Kustomization → ./config (dependsOn infrastructure)
├── home-assistant.yaml  # Flux Kustomization → ./apps/home-assistant/overlays/homelab
├── ddns.yaml            # Flux Kustomization → ./apps/ddns/overlays/homelab
└── values/              # Cluster-specific Helm values

infrastructure/          # Base HelmReleases (reusable, values optional)
├── cilium/              # CNI + Gateway API CRDs
├── cert-manager/        # TLS certificates
├── flux/                # Flux operator + instance
├── metrics-server/      # Resource metrics
└── piraeus/             # LINSTOR storage (DRBD)

config/                  # Post-install configuration (CRDs must exist)
├── cert-manager/        # ClusterIssuer (Let's Encrypt DNS-01) + wildcard Certificate
├── cilium/              # Gateway, IP pool, L2 policy, Hubble HTTPRoute
├── flux/                # Flux operator HTTPRoute
└── piraeus/             # LinstorSatelliteConfiguration

apps/                    # User-facing applications
├── home-assistant/
│   ├── base/            # Deployment, Service, PVC, Matter Server
│   └── overlays/homelab # HTTPRoutes (internal + external), NetworkPolicy, patches
└── ddns/
    ├── base/            # favonia/cloudflare-ddns Deployment
    └── overlays/homelab # Homelab-specific env (domain, secret ref)
```

## Reconciliation order

```
FluxInstance (tofu bootstrap)
  └── clusters/homelab (Flux Kustomization: flux-system)
        ├── infrastructure (Flux Kustomization, prune: false)
        │   └── Cilium → cert-manager, Flux, metrics-server, Piraeus
        ├── config (Flux Kustomization, dependsOn: infrastructure)
        │   └── Gateway, HTTPRoutes, IP pool, L2 policy, ClusterIssuer, Certificate
        ├── apps/home-assistant (Flux Kustomization, dependsOn: infrastructure + config)
        └── ddns (Flux Kustomization, dependsOn: infrastructure + config)
```

## Networking

### Internal (LAN)

| Hostname      | Service        |
|---------------|----------------|
| `ha.home`     | Home Assistant |
| `hubble.home` | Hubble UI      |
| `flux.home`   | Flux Operator  |

All internal services share a single Cilium Gateway at `192.168.0.200` (HTTP, port 80).
DNS configured on the router pointing each `*.home` hostname to `192.168.0.200`.

### External (Internet)

| Hostname                | Service        |
|-------------------------|----------------|
| `ha.casasulgorgo.net`   | Home Assistant |

External access via Cloudflare proxy (orange cloud) → port-forward 443 → Cilium Gateway (HTTPS, port 443).
TLS terminated at the Gateway using a Let's Encrypt wildcard cert (`*.casasulgorgo.net`) issued via DNS-01.
DDNS (`favonia/cloudflare-ddns`) keeps the apex A record updated with the home public IP.

## Secrets management

Secrets are injected by Tofu directly into Kubernetes (not managed by Flux/SOPS for bootstrap secrets):
- `flux-system/flux-system` — Flux SSH deploy key + GitHub known_hosts
- `flux-system/sops-age` — Age key for SOPS decryption
- `flux-system/flux-substitutions` — Variable substitutions for Flux postBuild
- `cert-manager/cloudflare-api-token` — Cloudflare token for DNS-01 challenges
- `ddns/cloudflare-api-token` — Cloudflare token for DDNS updates

Namespaces required before Flux runs (`cert-manager`, `ddns`) are also created by Tofu.

## Hardware

| Node    | CPU          | Role          | IP            |
|---------|--------------|---------------|---------------|
| nuc-101 | Celeron J3455| Control plane | 192.168.0.101 |
| nuc-102 | i3-7100U     | Worker        | 192.168.0.102 |
| nuc-103 | J5005        | Worker        | 192.168.0.103 |
| nuc-104 | J5005        | Worker        | 192.168.0.104 |

VIP: `192.168.0.100` — Gateway LB: `192.168.0.200`
