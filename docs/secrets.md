# Secrets

## Bootstrap secrets (Tofu-managed)

Injected by Tofu directly into Kubernetes — not managed by Flux/SOPS:

| Secret                              | Namespace      | Purpose                              |
|-------------------------------------|----------------|--------------------------------------|
| `flux-system`                       | `flux-system`  | SSH deploy key + GitHub known_hosts  |
| `sops-age`                          | `flux-system`  | Age key for SOPS decryption          |
| `flux-substitutions`                | `flux-system`  | Variable substitutions for postBuild |
| `cloudflare-api-token`              | `cert-manager` | DNS-01 challenge for Let's Encrypt   |
| `cloudflare-api-token`              | `ddns`         | DDNS A record updates + `domains`    |

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

`encrypt` only needs the public key from `.sops.yaml`. `edit-secret` (and `just tofu`) read the age private key
from `~/.config/sops/age/keys.txt` (mode 0600), via `SOPS_AGE_KEY_FILE` set in the justfile.

## Tofu inputs

Tofu's variables (`terraform.tfvars`) and the R2 state credentials live in the SOPS Secret
`infrastructure/tofu/secret.yaml`, shared by `just tofu …` locally and tofu-controller in-cluster.
See [OpenTofu](opentofu.md).

`*.tfvars`, `*.tfvars.json` and dotfiles (`.env`) stay gitignored as a safety net.
