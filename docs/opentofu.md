# OpenTofu

OpenTofu provisions the cluster (Talos nodes, Cilium, Flux, namespaces, secrets) and manages Cloudflare DNS/R2.

## State backend

State is stored remotely in Cloudflare R2 (S3-compatible object storage).

- **Bucket**: `tofu-state` (created by Tofu itself via `cloudflare_r2_bucket`)
- **Config**: the `backend "s3"` block in `tofu/production/main.tf`
- **Credentials**: `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` from the SOPS Secret `infrastructure/tofu/secret.yaml` (see below)

The R2 API token (S3 credentials) is separate from the Cloudflare API token. Create it in the Cloudflare dashboard under **R2 > Manage R2 API Tokens** with Object Read & Write on the `tofu-state` bucket.

## Inputs

There's no local `.env` or `terraform.tfvars`. The SOPS Secret `infrastructure/tofu/secret.yaml` is the single
source for both the laptop and tofu-controller: it holds `terraform.tfvars` (HCL) and the R2 keys (`AWS_*`).
The only thing outside git is the age private key, in `~/.config/sops/age/keys.txt` (mode 0600; the justfile
exports `SOPS_AGE_KEY_FILE`, override it to use another path).

`just tofu …` decrypts the Secret in memory, exports the R2 keys and each variable
as `TF_VAR_<name>` (parsed with `yq -p hcl`: strings as-is, maps as JSON), and runs tofu. Nothing is written to disk.

To change a variable: `just edit-secret infrastructure/tofu/secret.yaml`, commit, and the controller re-plans.

## Usage

```bash
just tofu init
just tofu plan
just tofu apply
```

The recipes that read outputs (`add-kubeconfig`, `add-talosconfig`, `upgrade-nodes`) go through `just tofu output`.

## In-cluster plans and drift detection (tofu-controller)

[tofu-controller](https://github.com/flux-iac/tofu-controller) (`infrastructure/controllers/tofu-controller`)
runs `tofu/production` from the `Terraform` object `flux-system/production` (`infrastructure/tofu`), in
**manual mode**: it plans every hour and on every new commit, and never applies on its own.

- **Source**: its own GitRepository `infra-tofu` (the `flux-system` one excludes `tofu/` via `.sourceignore`).
- **State**: the same R2 backend as the laptop (`backendConfig.customConfiguration` repeats the `backend "s3"`
  block from `main.tf`, keep them in sync). There's no state locking, so don't apply from both at once.
- **Inputs**: the SOPS Secret `infrastructure/tofu/secret.yaml` holds `terraform.tfvars` (mounted into the
  workspace) and the R2 keys; it's the same file `just tofu` reads locally (see [Inputs](#inputs)).
- **tofu version**: the stock runner ships an older tofu, so an init container copies `ghcr.io/opentofu/opentofu`
  in. Its tag must equal `required_version` in `main.tf` (Renovate is disabled for it); bump both together.
- **Alerts**: Flux Alerts can't watch `Terraform` objects, so the `tofu` Flux Kustomization health-checks it:
  drift (`Ready=False`) or a plan waiting for approval fails the Kustomization, which alerts Matrix.

### Approving a plan

The plan ID is derived from the commit (`plan-main-<sha>`), and the controller re-plans just before applying.
Approving by committing `approvePlan` would create a new commit and invalidate the plan, so approve in-cluster
(`approvePlan` isn't set in git, so Flux leaves the field alone):

```bash
just tofu-plans            # pending plan ID and the stored plan (storeReadablePlan: human)
just tofu-plan approve     # asks first, then sets spec.approvePlan to the pending ID
just tofu-plan reject      # drops the pending plan and re-plans
```

If a new commit lands before the apply, the re-plan gets a new ID and waits for approval again.

The controller has no real reject: re-planning the same commit gives the same plan, so revert or fix the commit
to discard a change for good. Until then the plan keeps waiting, and nothing is applied.

When drift is detected the controller only reports it (`DriftDetected`) and doesn't plan. The next commit
triggers a plan, or `just tofu-plan reject` forces one; then approve it as above (applying reverts the drift),
or change the code to match.

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
