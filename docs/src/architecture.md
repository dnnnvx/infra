# Architecture

```
tofu/                    # OpenTofu (Terraform) — provisions the cluster
├── production/          # Cluster definition (nodes, IPs, extensions)
└── modules/
    ├── talos/           # Talos Linux cluster provisioning
    ├── k8s/             # Bootstrap (Cilium, Flux, namespaces, secrets)
    ├── cloudflare/      # DNS records (apex A + subdomain CNAMEs), R2 buckets
    └── github/          # Deploy key + pinned SSH known_hosts

clusters/production/     # Flux entry point (synced by FluxInstance)
├── kustomization.yaml   # ConfigMapGenerators for Helm values
├── infrastructure.yaml  # Flux Kustomization → ./infrastructure
├── config.yaml          # Flux Kustomization → ./config (dependsOn infrastructure)
├── home-assistant.yaml  # Flux Kustomization → ./apps/home-assistant/overlays/production
├── ddns.yaml            # Flux Kustomization → ./apps/ddns/overlays/production
├── adguard-home.yaml    # Flux Kustomization → ./apps/adguard-home/overlays/production
├── webauth.yaml         # Flux Kustomization → ./apps/webauth/overlays/production
├── lightnvr.yaml        # Flux Kustomization → ./apps/lightnvr/overlays/production
└── values/              # Cluster-specific Helm values

infrastructure/          # Base HelmReleases (reusable, values optional)
├── cilium/              # CNI + Gateway API CRDs
├── cert-manager/        # TLS certificates
├── flux/                # Flux operator + instance
├── metrics-server/      # Resource metrics
├── piraeus/             # LINSTOR storage (DRBD)

config/                  # Post-install configuration (CRDs must exist)
├── cert-manager/        # ClusterIssuer (Let's Encrypt DNS-01) + wildcard Certificate
├── cilium/              # Gateway, IP pool, L2 policy, Hubble HTTPRoute
├── flux/                # Flux operator HTTPRoute
└── piraeus/             # LinstorSatelliteConfiguration

apps/                    # User-facing applications
├── home-assistant/
│   ├── base/               # Deployment, Service, PVC, Matter Server
│   └── overlays/production # HTTPRoutes (internal + external), NetworkPolicy, patches
├── ddns/
│   ├── base/               # favonia/cloudflare-ddns Deployment
│   └── overlays/production # Homelab-specific env (domain, secret ref)
├── adguard-home/
│   ├── base/               # StatefulSet, DNS + Web Services
│   └── overlays/production # HTTPRoute, storage patches
├── webauth/
│   ├── base/               # Pocket-ID (OIDC IdP, passkey auth), OAuth2 Proxy (disabled)
│   └── overlays/production # HTTPRoute, SOPS-encrypted secrets
└── lightnvr/
    ├── base/               # Deployment, Service, PVC (recordings)
    └── overlays/production # HTTPRoute (nvr.home), piraeus-hdd storage
```
