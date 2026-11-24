# Homelab

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Stack

- **Cluster:** Talos Linux · OpenTofu · Flux (GitOps + image automation) · Renovate
- **Network:** Cilium (eBPF, Gateway API, LB IPAM) · cert-manager · Cloudflare
- **Storage:** Piraeus / LINSTOR (DRBD) · CloudNativePG
- **Registry:** zot (Pocket-ID OIDC)
- **CI/CD:** Tekton (Pipelines, Triggers, Chains) · Nix (nix2container) builds
- **Supply chain:** syft (SBOM) · grype (vuln scan) · cosign + SLSA provenance · oras · crane
- **Policy and secrets:** SOPS + age · checkov · trufflehog · tflint · kubeconform · Cilium default-deny · ValidatingAdmissionPolicy
- **Observability:** Gatus · Hubble · metrics-server

## Docs

Published at <https://docs.marcods.dev>.
