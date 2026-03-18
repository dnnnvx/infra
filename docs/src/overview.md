# Overview

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Reconciliation order

```
FluxInstance (tofu bootstrap)
  └── clusters/homelab (Flux Kustomization: flux-system)
        ├── infrastructure (Flux Kustomization, prune: false)
        │   └── Cilium → cert-manager, Flux, metrics-server, Piraeus
        ├── config (Flux Kustomization, dependsOn: infrastructure)
        │   └── Gateway, HTTPRoutes, IP pool, L2 policy, ClusterIssuer, Certificate
        ├── apps/home-assistant (Flux Kustomization, dependsOn: infrastructure + config)
        ├── ddns
        ├── adguard-home
        ├── webauth
        └── lightnvr
```
