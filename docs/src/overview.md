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
            │      prune: true; data annotated kustomize.toolkit.fluxcd.io/prune: disabled)
            ├── app-home-assistant → apps/home-assistant
            ├── app-casasulgorgo   → apps/casasulgorgo (CI-built)
            └── …                  (list: clusters/production/apps/kustomization.yaml)
```

Apps prune what you delete from their directory. Disabling an app (commenting it out of the list) deletes
all its resources except those annotated `kustomize.toolkit.fluxcd.io/prune: disabled`: stateful apps set it
on their Namespace, PVCs and CNPG Cluster, so the data stays until removed by hand (deleting the Namespace
would take the PVCs with it). Stateless apps and kubbot have no annotation and are removed completely.
Give a new stateful app the same annotations.
