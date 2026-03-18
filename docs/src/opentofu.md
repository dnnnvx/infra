# OpenTofu

OpenTofu provisions the cluster (Talos nodes, Cilium, Flux, namespaces, secrets) and manages Cloudflare DNS/R2.

## State backend

State is stored remotely in Cloudflare R2 (S3-compatible object storage).

- **Bucket**: `tofu-state` (created by Tofu itself via `cloudflare_r2_bucket`)
- **Config**: `tofu/homelab/backend.tfbackend` (tracked in git — contains endpoint + skip flags)
- **Credentials**: `tofu/homelab/.env` (gitignored — contains `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`)

The R2 API token (S3 credentials) is separate from the Cloudflare API token. Create it in the Cloudflare dashboard under **R2 > Manage R2 API Tokens** with Object Read & Write on the `tofu-state` bucket.

## Usage

```bash
source tofu/homelab/.env
cd tofu/homelab
tofu init -backend-config=backend.tfbackend
tofu plan
tofu apply
```

## Modules

| Module      | Purpose                                           |
|-------------|---------------------------------------------------|
| `talos`     | Talos Linux cluster: nodes, machine configs, VIP  |
| `k8s`       | Bootstrap: Cilium Helm, Flux, namespaces, secrets |
| `cloudflare`| DNS records (apex A + CNAME subdomains), R2       |
| `github`    | Deploy key + SSH known_hosts                      |

## Applying node changes

`tofu apply` pushes updated machine configs to Talos nodes automatically via the Talos provider. For kernel module or extension changes, nodes pick up the config on next apply — no manual `talosctl apply-config` needed.

If a node needs a full image upgrade (Talos version bump), use:

```bash
just upgrade-nodes
```
