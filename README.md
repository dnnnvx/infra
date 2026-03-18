# Homelab

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Architecture

```
tofu/                    # OpenTofu (Terraform) — provisions the cluster
├── homelab/             # Cluster definition (nodes, IPs, extensions)
└── modules/
    ├── talos/           # Talos Linux cluster provisioning
    ├── k8s/             # Bootstrap (Cilium, Flux, namespaces, secrets)
    ├── cloudflare/      # DNS records (apex A + subdomain CNAMEs), R2 buckets
    └── github/          # Deploy key + pinned SSH known_hosts

clusters/homelab/        # Flux entry point (synced by FluxInstance)
├── kustomization.yaml   # ConfigMapGenerators for Helm values
├── infrastructure.yaml  # Flux Kustomization → ./infrastructure
├── config.yaml          # Flux Kustomization → ./config (dependsOn infrastructure)
├── home-assistant.yaml  # Flux Kustomization → ./apps/home-assistant/overlays/homelab
├── ddns.yaml            # Flux Kustomization → ./apps/ddns/overlays/homelab
├── adguard-home.yaml    # Flux Kustomization → ./apps/adguard-home/overlays/homelab
├── webauth.yaml         # Flux Kustomization → ./apps/webauth/overlays/homelab
├── lightnvr.yaml        # Flux Kustomization → ./apps/lightnvr/overlays/homelab
└── values/              # Cluster-specific Helm values

infrastructure/          # Base HelmReleases (reusable, values optional)
├── cilium/              # CNI + Gateway API CRDs
├── cert-manager/        # TLS certificates
├── flux/                # Flux operator + instance
├── metrics-server/      # Resource metrics
├── piraeus/             # LINSTOR storage (DRBD)
└── tofu-controller/     # Flux-managed OpenTofu (GitOps for IaC)

config/                  # Post-install configuration (CRDs must exist)
├── cert-manager/        # ClusterIssuer (Let's Encrypt DNS-01) + wildcard Certificate
├── cilium/              # Gateway, IP pool, L2 policy, Hubble HTTPRoute
├── flux/                # Flux operator HTTPRoute
└── piraeus/             # LinstorSatelliteConfiguration

apps/                    # User-facing applications
├── home-assistant/
│   ├── base/            # Deployment, Service, PVC, Matter Server
│   └── overlays/homelab # HTTPRoutes (internal + external), NetworkPolicy, patches
├── ddns/
│   ├── base/            # favonia/cloudflare-ddns Deployment
│   └── overlays/homelab # Homelab-specific env (domain, secret ref)
├── adguard-home/
│   ├── base/            # StatefulSet, DNS + Web Services
│   └── overlays/homelab # HTTPRoute, storage patches
├── webauth/
│   ├── base/            # Pocket-ID (OIDC IdP, passkey auth), OAuth2 Proxy (disabled)
│   └── overlays/homelab # HTTPRoute, SOPS-encrypted secrets
└── lightnvr/
    ├── base/            # Deployment, Service, PVC (recordings)
    └── overlays/homelab # HTTPRoute (nvr.home), piraeus-hdd storage
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
        ├── ddns (Flux Kustomization, dependsOn: infrastructure + config)
        ├── adguard-home
        ├── webauth
        └── lightnvr
```

## Networking

### Internal (LAN)

| Hostname      | Service        |
|---------------|----------------|
| `ha.home`     | Home Assistant |
| `hubble.home` | Hubble UI      |
| `flux.home`   | Flux Operator  |
| `nvr.home`    | LightNVR       |

All internal services share a single Cilium Gateway at `192.168.0.200` (HTTP, port 80).
DNS configured on the router pointing each `*.home` hostname to `192.168.0.200`.

### External (Internet)

| Hostname                | Service        |
|-------------------------|----------------|
| `ha.casasulgorgo.net`   | Home Assistant |
| `auth.casasulgorgo.net` | Pocket-ID      |

External access via Cloudflare proxy (orange cloud) → port-forward 443 → Cilium Gateway (HTTPS, port 443).
TLS terminated at the Gateway using a Let's Encrypt wildcard cert (`*.casasulgorgo.net`) issued via DNS-01.
DDNS (`favonia/cloudflare-ddns`) keeps the apex A record updated with the home public IP.

## Storage (Piraeus/LINSTOR)

Piraeus provides distributed storage via LINSTOR + DRBD, backed by the Talos nodes' local disks.

### Storage classes

| Class          | Pool          | Replicas | Nodes         | Use case                        |
|----------------|---------------|----------|---------------|---------------------------------|
| `piraeus`      | `file-thin`   | 2        | nuc-103/104   | Default — replicated app data   |
| `piraeus-hdd`  | `lvm-thin-hdd`| 1        | nuc-102 only  | Bulk data — recordings, logs    |

- **`piraeus`**: File-backed thin provisioning on NVMe/eMMC. 2 replicas across nuc-103 and nuc-104 via DRBD. Good for databases, app state, anything that needs redundancy.
- **`piraeus-hdd`**: LVM thin provisioning on the 500GB HDD in nuc-102. Single replica (no replication) — meant for large, replaceable data like NVR recordings.

### HDD pool setup (nuc-102)

The HDD pool requires the `dm_thin_pool` kernel module (loaded via Talos machine config) and an LVM thin pool on `/dev/sda`.

The VG `linstor-hdd-vg` is pre-created on `/dev/sda`. If the thin pool is missing (LINSTOR shows `Error` state), create it:

```bash
# Check pool status
kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor storage-pool list -n nuc-102

# Create the thin pool (from the satellite pod)
kubectl exec -n piraeus-datastore linstor-satellite.nuc-102-<suffix> -c linstor-satellite -- \
  lvcreate -l 100%FREE -T linstor-hdd-vg/linstor-hdd-thinpool
```

If `dm_thin_pool` module is missing (`modprobe: FATAL: Module dm-thin-pool not found`), it needs to be added to the Talos kernel modules in `tofu/homelab/main.tf` → `extra_config_patches`, then applied with `tofu apply` + `talosctl upgrade` on nuc-102.

### Useful LINSTOR commands

```bash
# All commands run inside the linstor-controller pod
alias linstor='kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor'

linstor storage-pool list              # Pool status per node
linstor volume list                    # All volumes and their locations
linstor resource list                  # DRBD resources and sync status
```

## OpenTofu state backend

State is stored remotely in Cloudflare R2 (S3-compatible object storage).

- **Bucket**: `tofu-state` (created by Tofu itself via `cloudflare_r2_bucket`)
- **Config**: `tofu/homelab/backend.tfbackend` (tracked in git — contains endpoint + skip flags)
- **Credentials**: `tofu/homelab/.env` (gitignored — contains `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)

The R2 API token (S3 credentials) is separate from the Cloudflare API token. Create it in the Cloudflare dashboard under **R2 > Manage R2 API Tokens** with Object Read & Write on the `tofu-state` bucket.

```bash
# Before running tofu commands, source the credentials
source tofu/homelab/.env
cd tofu/homelab
tofu init -backend-config=backend.tfbackend
tofu plan
tofu apply
```

## Secrets management

Secrets are injected by Tofu directly into Kubernetes (not managed by Flux/SOPS for bootstrap secrets):
- `flux-system/flux-system` — Flux SSH deploy key + GitHub known_hosts
- `flux-system/sops-age` — Age key for SOPS decryption
- `flux-system/flux-substitutions` — Variable substitutions for Flux postBuild
- `cert-manager/cloudflare-api-token` — Cloudflare token for DNS-01 challenges
- `ddns/cloudflare-api-token` — Cloudflare token for DDNS updates

Namespaces required before Flux runs (`cert-manager`, `ddns`) are also created by Tofu.

## Hardware

| Node    | CPU          | Role          | IP            | Storage                          |
|---------|--------------|---------------|---------------|----------------------------------|
| nuc-101 | Celeron J3455| Control plane | 192.168.0.101 | —                                |
| nuc-102 | i3-7100U     | Worker        | 192.168.0.102 | 256GB NVMe + 500GB HDD (piraeus-hdd) |
| nuc-103 | J5005        | Worker        | 192.168.0.103 | ~110GB file-thin (piraeus)       |
| nuc-104 | J5005        | Worker        | 192.168.0.104 | ~110GB file-thin (piraeus)       |

VIP: `192.168.0.100` — Gateway LB: `192.168.0.200`
