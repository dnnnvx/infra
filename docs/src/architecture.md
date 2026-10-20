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
├── infrastructure.yaml  # Flux Kustomization → ./infrastructure/controllers
├── config.yaml          # Flux Kustomization → ./infrastructure/configs (dependsOn infrastructure)
└── apps/                # one Flux Kustomization per app: app-<name> → ./apps/<name> (dependsOn both)

infrastructure/
├── controllers/         # Operators and their CRDs: HelmReleases (+ values.yaml) or upstream manifests
│   ├── cert-manager/    # TLS certificates
│   ├── cilium/          # CNI + Gateway API CRDs
│   ├── cnpg/            # CloudNativePG operator
│   ├── flux/            # Flux operator + instance
│   ├── metrics-server/  # Resource metrics
│   ├── piraeus/         # LINSTOR storage (DRBD)
│   ├── tekton/          # Pipelines, Triggers, Pruner, Dashboard
│   └── zot/             # OCI registry
└── configs/             # Custom resources for those controllers (their CRDs must exist)
    ├── cert-manager/    # ClusterIssuer (Let's Encrypt DNS-01) + wildcard Certificate
    ├── cilium/          # Default-deny policy, Gateway, IP pool, L2 policy, Hubble HTTPRoute
    ├── flux/            # Web UI, webhook Receiver, notifications, ImageUpdateAutomation
    ├── piraeus/         # LinstorCluster, satellite configs, storage pools + classes
    └── tekton/          # tekton-ci namespace, Tasks, Pipeline, EventListener

apps/                    # User-facing applications, one flat directory each (enabled in clusters/production/apps/)
└── <app>/               # Namespace, CiliumNetworkPolicy, workloads, HTTPRoute, SOPS secrets
```
