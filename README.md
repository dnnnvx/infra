# Homelab

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Architecture

```
tofu/                    # OpenTofu (Terraform) — provisions the cluster
├── homelab/             # Cluster definition (nodes, IPs, extensions)
└── modules/
    ├── talos/           # Talos Linux cluster provisioning
    └── k8s/             # Bootstrap (Cilium, Flux)

clusters/homelab/        # Flux entry point (synced by FluxInstance)
├── kustomization.yaml   # ConfigMapGenerators for Helm values
├── namespaces.yaml      # Cluster namespaces
├── infrastructure.yaml  # Flux Kustomization → ./infrastructure
├── config.yaml          # Flux Kustomization → ./config (dependsOn infrastructure)
└── values/              # Cluster-specific Helm values

infrastructure/          # Base HelmReleases (reusable, values optional)
├── cilium/              # CNI + Gateway API CRDs
├── cert-manager/        # TLS certificates
├── flux/                # Flux operator + instance
├── metrics-server/      # Resource metrics
└── piraeus/             # LINSTOR storage (DRBD)

config/                  # Post-install configuration (CRDs must exist)
├── cilium/              # Gateway, IP pool, L2 policy, Hubble HTTPRoute
├── flux/                # Flux operator HTTPRoute
└── piraeus/             # LinstorSatelliteConfiguration
```

## Reconciliation order

```
FluxInstance (tofu bootstrap)
  └── clusters/homelab (Flux Kustomization: flux-system)
        ├── infrastructure (Flux Kustomization, prune: false)
        │   └── Cilium → cert-manager, Flux, metrics-server, Piraeus
        └── config (Flux Kustomization, dependsOn: infrastructure)
            └── Gateway, HTTPRoutes, IP pool, L2 policy, satellite config
```

## Networking

| Hostname         | Service        | Port |
|------------------|----------------|------|
| `hubble.homelab` | Hubble UI      | 80   |
| `flux.homelab`   | Flux Operator  | 9080 |

All services share a single Cilium Gateway at `192.168.0.200` with host-based routing.
DNS configured on the router pointing each hostname to `192.168.0.200`.

## Hardware

| Node    | CPU          | Role          | IP            |
|---------|--------------|---------------|---------------|
| nuc-101 | Celeron J3455| Control plane | 192.168.0.101 |
| nuc-102 | i3-7100U     | Worker        | 192.168.0.102 |
| nuc-103 | J5005        | Worker        | 192.168.0.103 |
| nuc-104 | —            | Worker        | 192.168.0.104 |

VIP: `192.168.0.100`

## Usage

```sh
# Enter dev shell
just dev

# Validate manifests before pushing
just validate

# Sync Flux manually
just sync

# Upgrade node images (after changing Talos extensions)
just upgrade-nodes

# Reconcile a single Flux Kustomization
flux reconcile kustomization infrastructure -n flux-system
```
