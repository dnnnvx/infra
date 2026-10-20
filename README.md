# Homelab

Kubernetes homelab running on Intel NUCs with Talos Linux, managed by OpenTofu and Flux.

## Stack

- **Cluster:** Talos Linux · OpenTofu · Flux (GitOps + image automation) · Renovate
- **Network:** Cilium (eBPF, Gateway API, LB IPAM) · cert-manager · Cloudflare
- **Storage:** Piraeus / LINSTOR (DRBD) · CloudNativePG
- **Registry:** zot (Pocket-ID OIDC)
- **CI/CD:** Tekton (Pipelines, Triggers, Chains) · rootless BuildKit
- **Supply chain:** syft (SBOM) · grype (vuln scan) · cosign + SLSA provenance · oras · crane
- **Policy and secrets:** SOPS + age · checkov · trufflehog · tflint · kubeconform · Cilium default-deny · ValidatingAdmissionPolicy
- **Observability:** Gatus · Hubble · metrics-server

## Docs

```bash
just docs       # build and serve at http://localhost:3000
```

Or read the source in [`docs/src/`](docs/src/SUMMARY.md):

- [Overview](docs/src/overview.md)
- [Architecture](docs/src/architecture.md)
- [Hardware](docs/src/hardware.md)
- [Networking](docs/src/networking.md)
- [Storage](docs/src/storage.md)
- [CI/CD](docs/src/cicd.md)
- [OpenTofu](docs/src/opentofu.md)
- [Secrets](docs/src/secrets.md)
- [Security](docs/src/security.md)
- [Debugging](docs/src/debugging.md)
