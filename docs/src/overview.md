# Overview

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Reconciliation order

```
FluxInstance (tofu bootstrap)
  └── clusters/production (Flux Kustomization: flux-system)
        ├── infrastructure (Flux Kustomization, prune: false)
        │   └── Cilium → cert-manager, Flux, metrics-server, Piraeus
        ├── config (Flux Kustomization, prune: false, dependsOn: infrastructure)
        │   └── Gateway, HTTPRoutes, IP pool, L2 policy, ClusterIssuer, Certificate
        └── apps/ (one Flux Kustomization app-<name> per app, dependsOn: infrastructure + config,
            │      prune: true, deletionPolicy: Orphan)
            ├── app-home-assistant → apps/home-assistant
            ├── app-casasulgorgo   → apps/casasulgorgo (CI-built)
            └── …                  (list: clusters/production/apps/kustomization.yaml)
```

Apps prune what you delete from their directory. Disabling an app (commenting it out of the list) deletes
only its Kustomization: the namespace, PVCs and the rest stay until removed by hand.
