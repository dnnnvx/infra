# Secrets

## Bootstrap secrets (Tofu-managed)

Injected by Tofu directly into Kubernetes — not managed by Flux/SOPS:

| Secret                              | Namespace      | Purpose                              |
|-------------------------------------|----------------|--------------------------------------|
| `flux-system`                       | `flux-system`  | SSH deploy key + GitHub known_hosts  |
| `sops-age`                          | `flux-system`  | Age key for SOPS decryption          |
| `flux-substitutions`                | `flux-system`  | Variable substitutions for postBuild |
| `cloudflare-api-token`              | `cert-manager` | DNS-01 challenge for Let's Encrypt   |
| `cloudflare-api-token`              | `ddns`         | DDNS A record updates                |

Namespaces required before Flux runs (`cert-manager`, `ddns`) are also created by Tofu.

## Application secrets (SOPS-encrypted)

App-specific secrets are SOPS-encrypted YAML files committed to git and decrypted by Flux's kustomize-controller.

Encrypt a secret:
```bash
just encrypt path/to/secret.yaml
```

Edit an encrypted secret:
```bash
just edit-secret path/to/secret.yaml
```

Both commands prompt for the Age private key interactively.

## Sensitive files (gitignored)

| File                          | Contents                        |
|-------------------------------|----------------------------------|
| `tofu/production/terraform.tfvars` | All Tofu variables (tokens, keys) |
| `tofu/production/.env`            | R2 S3 credentials (`AWS_*`)     |
| `*.tfvars`, `*.tfvars.json`   | Matched by `.gitignore`          |
| `.env*`                       | Matched by `.gitignore`          |
