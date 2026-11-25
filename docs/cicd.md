# CI/CD

Tekton builds images, zot stores them, Tekton Chains signs them, Flux deploys them. The design follows
[Konflux](https://konflux-ci.dev) (a Tekton-based platform) at homelab scale: a build pipeline that can't sign or
release anything, provenance generated and signed outside the pipeline, and a release pipeline that trusts
signatures, not whoever triggered it. CI holds no cluster or git write credentials.
Pushes to this repository run a separate, read-only validation pipeline
([Infra validation](#infra-validation-validate-infra)).

```
git push main (GitHub) ──signed webhook──▶ ci.casasulgorgo.net ─▶ EventListener "github" (tekton-ci)
    interceptors: github (HMAC check) ─▶ cel (filter + tags)
    └▶ PipelineRun build-image: clone ─▶ build (nix-build)          ─┬▶ scan (grype on the image)
                                          │ push :<sha>                └▶ scan-source (grype on lockfiles) ─▶ sbom (oras attach)
                                          ▼
                  zot (registry.local.casasulgorgo.net, LAN Gateway, public TLS)
                                          ▲ image signature + SLSA v1 provenance (OCI referrers)
    Tekton Chains (tekton-chains, holds the key) ── signs the build once it has succeeded
                                          │
    tekton-events-controller ── CloudEvent "pipelinerun.successful" ─▶ EventListener "tekton-events" (internal)
    └▶ PipelineRun release-image: release (cosign verify + verify-attestation, then crane tag
                                            :latest, :production) ─▶ deploy (flux-sync)
                                          │
Flux ImageRepository/ImagePolicy ◀────────┘ scan `production`, reflect its digest
Flux ImageUpdateAutomation ─▶ commits the new digest to apps/** on main ─▶ kustomize-controller deploys
```

## Images and tags

Images are `<project>/<image>`, where project is set in the app's Trigger (normally the GitHub repo name, e.g. `dnnnvx/casasulgorgo`):
`registry.local.casasulgorgo.net/casasulgorgo/web`.

| Tag | Meaning |
|-----|---------|
| `<full commit sha>` | Immutable, one per build. Pushed by nix-build, before scans and signing |
| `latest` | Last released build of the default branch |
| `production` | What should run in production (`main` → production). Moved by release-image only |

Apps reference `…/web:production@sha256:<digest>`, and Flux rewrites the digest
(`digestReflectionPolicy: Always`). Every rollout is therefore a commit, and a
rollback is a `git revert`.

## Where things live

| Path | What |
|------|------|
| `infrastructure/controllers/tekton/` | Tekton Pipelines, Triggers (+ core interceptors), Pruner, Chains, Dashboard (`tekton.local.casasulgorgo.net`, behind oauth2-proxy + pocket-id): upstream release manifests, versions bumped by Renovate. `chains/` (release + config), `secrets-chains.yaml` (SOPS signing key, applied with the controller that mounts it), `patch-events.yaml` (CloudEvents sink) |
| `infrastructure/controllers/zot/` | zot HelmRelease, config (`values.yaml`), SOPS secrets (htpasswd, OIDC client, session keys), UI-only HTTPRoute |
| `infrastructure/configs/tekton/` | `tekton-ci` namespace and its fences, RBAC, push credentials, Chains public key (`chains.pub` → ConfigMap `chains-public-key` and the Kyverno policy `image-policy.yaml`), webhook HMAC secret, dashboard HTTPRoute |
| `infrastructure/controllers/kyverno/` | Kyverno (admission controller only), enforcing `image-policy.yaml` |
| `infrastructure/configs/tekton/tasks/` | one file per Task (`git-clone`, `nix-build`, `sbom`, `scan-image`, `scan-source`, `release-image`, `flux-sync`, `validate-manifests`, `lint-tofu`, `checkov`, `trufflehog`) |
| `infrastructure/configs/tekton/pipelines/` | one file per Pipeline (`build-image`, `release-image`, `validate-infra`) |
| `infrastructure/configs/tekton/triggers/` | TriggerTemplates, EventListeners (`github`: public webhooks; `tekton-events`: internal CloudEvents), the `github-webhook` HMAC Secret, this repo's Trigger (`trigger-infra.yaml`), the release Trigger (`trigger-release.yaml`), webhook HTTPRoute |
| `.checkov.yaml`, `tofu/.tflint.hcl` | scanner config for `validate-infra` |
| `clusters/production/apps/<project>.yaml` | the app's Flux Kustomization `app-<project>` |
| `apps/<project>/ci.yaml` | the app's Trigger, ImageRepository/ImagePolicy per image and name-scoped `flux-sync` Role/RoleBinding |
| `apps/<project>/kustomization.yaml` | `images:` entry with the `digest:` marker Flux rewrites |
| `tofu/production/talos.tf` | Talos `StaticHostConfig` pinning `registry.local.casasulgorgo.net` to the LAN Gateway, so pulls don't depend on DNS |

## Build, sign, release

**build-image** (started by the app's Trigger) clones, builds and pushes each image under its commit tag only,
then:

- **scan**: grype scans the image and fails the run on vulnerabilities of severity `high` or worse that have a
  fix (`fail-on` param, `--only-fixed`). Unfixable CVEs don't block a release.
- **scan-source** (in parallel with scan): the same check on the repository's lockfiles, see
  [Vulnerability scans](#vulnerability-scans). Both honour the repo's time-boxed `.grype-ignore`.
- **sbom** (after scan-source): oras attaches SBOMs to each image as OCI referrers: the image's own
  (`application/spdx+json` from syft, or for nix-build the closure's `application/vnd.cyclonedx+json` from
  sbomnix) and `source-lockfiles.cdx.json` from scan-source. The image SBOM's blob digest is the `sboms` result.

The pipeline has no signing key and never moves `latest`/`production`.

**Tekton Chains** (namespace `tekton-chains`, key in `signing-secrets`) watches PipelineRuns. When one succeeds it
signs every image named in the type-hinted `IMAGES` result and generates a SLSA v1.0 provenance for the whole run
(deep inspection: every TaskRun, its params, results and step images). Both go to zot as Sigstore bundles
referring to the image (OCI 1.1 referrers). Same choices as Konflux's Chains config, see
`infrastructure/controllers/tekton/chains/patch-chains.yaml`. Nothing goes to the public Rekor log, so verification
skips the tlog. Chains authenticates to zot with `pipeline-runner`'s `secrets` (`registry-push`); since v0.30.0 it ignores
`imagePullSecrets`.

**release-image** is started by the `release` Trigger on the internal `tekton-events` EventListener, which receives
Tekton's own CloudEvents. A `dev.tekton.event.pipelinerun.successful.v1` event of a `build-image` run becomes a
release run with the build's `registry`, `project`, `tags`, `flux-kustomization` params and `digests` result. It:

1. waits (up to 5 min) until each digest has a Chains signature and SLSA provenance, verifying both against
   `chains.pub`;
2. moves the release tags with crane, unless the tag already points at a newer commit;
3. runs `deploy` (flux-sync, below), skipped when step 2 moved nothing.

The event isn't authenticated. That's fine: release-image only promotes digests signed by Chains, i.e. images that
a successful build-image run produced. The worst a forged event can do is re-release such an image, and even that
can't roll back: every image carries the label `ci.casasulgorgo.net/commit-timestamp` (commit date: the flake sets it
from `self.lastModified`), and release-image leaves a tag alone when its current image has a later timestamp. Images without
the label (built before it existed) are never released. Tekton does replay `successful` events for old, finished
runs (seen on 2026-10-27: yesterday's casasulgorgo build re-released, `production` went back a version).

To check an image from a laptop on the LAN:

```bash
cosign verify --key infrastructure/configs/tekton/chains.pub --insecure-ignore-tlog \
  registry.local.casasulgorgo.net/casasulgorgo/web:production
cosign verify-attestation --type slsaprovenance1 --key infrastructure/configs/tekton/chains.pub \
  --insecure-ignore-tlog registry.local.casasulgorgo.net/casasulgorgo/web:production | jq -r .payload | base64 -d | jq .predicate
oras discover registry.local.casasulgorgo.net/casasulgorgo/web:production   # signature, provenance, SBOM
```

**Admission check.** release-image guards the tags, but anyone able to push to zot could still move `production` to an
unsigned image and Flux would deploy it. So Kyverno (`infrastructure/controllers/kyverno`, admission controller only)
enforces the ImageValidatingPolicy `chains-signed-images` (`infrastructure/configs/tekton/image-policy.yaml`): in every
namespace except the infrastructure ones listed in the policy (flux-system, piraeus-datastore, cnpg-system,
cert-manager, zot, tekton-*, kube-system, kyverno; add new ones there), every `registry.local.casasulgorgo.net/*` image needs a digest, a
Chains signature and a Chains-signed SLSA provenance, checked against `chains.pub` (injected by a kustomize replacement,
so the key lives in one file) without Rekor. The image reference is the selector, so a new CI app is covered without
opting in. Autogen rules cover Deployments etc., so Flux's apply fails instead of a ReplicaSet silently not creating
pods. Other images aren't checked. The webhook is `failurePolicy: Fail`, so Kyverno runs 2 replicas with a PDB; if both
are down, app pods can't be (re)created until one is back, while the platform keeps working.
sigstore policy-controller isn't used because it can't verify key-signed sigstore bundles (only keyless ones), which is
what Chains writes.

To see a rejection: `kubectl -n <project> get events --field-selector reason=PolicyViolation`, or the Flux
Kustomization `app-<project>`'s status (`admission webhook ... denied the request`).

The same policy also checks what the provenance says, since Chains signs any PipelineRun in `tekton-ci`, hand-started
ones included:

- `pipelineRef` is `build-image`;
- the `repo-url` param is one of our GitHub repositories (`https://github.com/dnnnvx/<repo>`, pinned in each Trigger;
  repos under another owner need an allowlist entry in the policy before their first build gets deployed);
- the subject name is the repository the image is pulled from, so a signed image copied into another app's repository
  is rejected (Kyverno already matches the subject digest).

The branch isn't recorded in the provenance: only the Trigger's CEL filter (`refs/heads/main`) restricts builds to main.

## Flux sync (deploy task)

After the release, the optional `deploy` task (`flux-sync`, ServiceAccount `flux-sync`) skips Flux's polling:
it reconciles the ImageRepository, waits until the ImagePolicy resolves the pushed digest, runs
`ImageUpdateAutomation/apps` (the bot commit), then reconciles `app-<app>` with its source and waits for
the rollout. A failed rollout fails the release PipelineRun. Names follow a convention: ImageRepository/ImagePolicy `<project>-<image>` and Kustomization `app-<project>`.
An app may have several images: the build task builds them one after the other and returns a
`name=digest` list, and `flux-sync` waits for every policy before the single bot commit.
A build started without `flux-kustomization` is released without the task.

The bot commits are GPG-signed (`signingKey` in `infrastructure/configs/flux/image-update-automation.yaml`,
private key in the SOPS Secret `signing-key.yaml`) as `fluxcdbot <17187206+dnnnvx@users.noreply.github.com>`. tofu
registers the public half (`tofu/production/flux-signing-key.asc`) on the GitHub account, so they show as Verified.
To rotate: generate a new key with the same identity, replace both files and run `just tofu apply`.

Every app has its own Kustomization (`clusters/production/apps/<project>.yaml`), so the deploy task waits
for this app only: an unhealthy unrelated app doesn't fail the release.

## Adding a repo/image

1. Copy `apps/casasulgorgo/ci.yaml` into `apps/<project>/` (list it in its `kustomization.yaml`) and
   `clusters/production/apps/casasulgorgo.yaml` to `<project>.yaml` (list it in `clusters/production/apps/kustomization.yaml`).
   Replace the project name, the GitHub repository in the Trigger's CEL filter and `repo-url` binding, and the image name
   (the header comment of `ci.yaml` lists every spot). For more images, add an ImageRepository/ImagePolicy pair per image, its name in the
   Role's `resourceNames`, and a `<name>,<attr>,<flakedir>` entry in the Trigger's space-separated `images` binding
   (see [Builder](#builder) for what the flake must expose).
2. In `apps/<project>/kustomization.yaml`, use a kustomize `images:` entry per image with a `digest:` marker
   `# {"$imagepolicy": "flux-system:<project>-<image>:digest"}` (copy casasulgorgo's). Kyverno then only admits
   Chains-signed digests of it. If the repo lives outside `github.com/dnnnvx`, add it to the
   `repo-url` allowlist in `infrastructure/configs/tekton/image-policy.yaml` first.
3. Add the repo with `ci_webhook = true` to `repositories` in `module "github"` (`tofu/production/github.tf`; an existing repo also needs an
   `import` entry) and run `just tofu apply`: tofu manages the repo settings and creates its push webhook to
   `https://ci.casasulgorgo.net/` with the HMAC secret.
4. Private repo: also add it to `tls_private_key.ci_clone` (`tofu/production/github.tf`) and a
   `<repo>: ${git_ssh_key_<repo>}` line (dashes as underscores) to `infrastructure/configs/tekton/git-ssh-secret.yaml`.
   Tofu registers a read-only deploy key and passes the private half via `flux-substitutions`; `git-clone` then fetches
   over SSH on `ssh.github.com:443` (no extra egress), while `repo-url` stays the HTTPS URL that Kyverno pins.

## Infra validation (validate-infra)

Every branch push to this repository (Flux's digest commits on `main` included) runs `validate-infra`. It has no
credentials and deploys nothing. After the clone, four tasks run in parallel:

| Task | What | Fails on |
|------|------|----------|
| `manifests` (`validate-manifests`) | `flux build ks --dry-run` for every Flux Kustomization in `clusters/production/` (+ plain kustomize for the root), then kubeconform `-strict` with the CRDs-catalog schemas | build/substitution errors, schema violations. `substituteFrom` variables stay as `${VAR}` (dry run, no cluster) |
| `tofu` (`lint-tofu`) | `tofu fmt -check -recursive tofu`, `tflint --recursive` (bundled terraform ruleset, `recommended` preset, `tofu/.tflint.hcl`) | unformatted files, any tflint issue |
| `policies` (`checkov`) | checkov over `tofu/` and the raw manifests (`.checkov.yaml`) | any finding not skipped in `.checkov.yaml` or annotated on the resource |
| `secrets` (`trufflehog`) | `trufflehog git` over the cloned commit, candidates verified against their providers | any finding |

Notes:

- Upstream release manifests and Helm charts aren't rendered, so checkov sees only what this repo writes.
- No baseline: platform-wide exceptions (CPU limits, secrets as env, Cilium instead of NetworkPolicy, tag pinning)
  are `skip-check`s in `.checkov.yaml` with their reason. A workload that needs an exception (hostNetwork,
  root, writable root filesystem, …) says so in its own metadata, next to the code:
  `checkov.io/skip1: CKV_K8S_19=LAN device discovery needs the host network`.
- Run it locally with `checkov --config-file .checkov.yaml -d .` (`nix shell nixpkgs#uv -c uvx checkov` works if the
  nixpkgs build is broken).
- The clone is shallow, so trufflehog only scans the pushed commit's tree, not older history.
- Results show up in Tekton (dashboard, `tkn pr list -n tekton-ci -l ci.casasulgorgo.net/project=infra`) and
  as a commit status on GitHub (see [Commit status](#commit-status)).

## Commit status

`validate-infra` and `build-image` report to GitHub's commit status API with the reusable `github-status` Task:
`pending` as their first task, then the result in `finally` (state `$(tasks.status)`), under the contexts
`tekton/validate-infra` and `tekton/build-image`. The check's "Details" link opens the PipelineRun in the Tekton
dashboard (LAN only). Another pipeline gets a check by adding the same two tasks with its own `context`.

The token is a fine-grained PAT in `tekton-ci/github-status` (`infrastructure/configs/tekton/github-status-secret.yaml`,
SOPS), limited to the CI repos with only "Commit statuses: Read and write". tofu can't create PATs, so it's set by
hand with `just edit-secret` and must be renewed before it expires. An empty token skips reporting, and a failed
API call only marks the task's own step (`onError: continue`): reporting never fails a build. The checks are
informational and not required in branch protection, since direct pushes to `main` (and Flux's image automation
commits) would be blocked waiting for a status that only exists after the push.

## Webhook verification

GitHub signs the body as `X-Hub-Signature-256: sha256=<hmac>`. The core `github` ClusterInterceptor
checks it against the `tekton-ci/github-webhook` Secret (it must be in the Trigger's namespace) and only
lets `push` events through; without `secretRef` it would accept anything, so every Trigger sets it.
The `cel` interceptor then filters on `repository.full_name` and the branch and computes the tags. The
commit comes from the authenticated payload; the clone URL is pinned in each Trigger, since Kyverno
allowlists it in the provenance. `just ci-build <repo> <sha>` replays a signed push.

tofu owns both webhook secrets (`random_password.github_webhook` for CI, `random_password.flux_receiver` for the
Flux Receiver on `infra`): it sets them on the GitHub webhooks (`tofu/modules/github`) and passes them to the cluster
as `github_webhook_secret` / `flux_receiver_token` in `flux-substitutions`, which fill
`triggers/github-webhook-secret.yaml` and `infrastructure/configs/flux/receiver-token.yaml`. Neither value is in git;
to rotate one, `just tofu apply -replace=random_password.<name>`.

## Registry access

| Who | How | Rights |
|-----|-----|--------|
| Humans | `registry.local.casasulgorgo.net` UI (LAN), Pocket-ID login (`registry_admins` group = admin) | read; admins delete |
| Tekton (pipelines, Chains) | `tekton` htpasswd user, `tekton-ci/registry-push` (Chains via `pipeline-runner`'s `secrets`) | read, create, update |
| containerd (nodes), Flux | anonymous (zot `anonymousPolicy`) | read |

Anonymous read is enabled because the kubelet's pulls don't use the Talos `RegistryAuthConfig`
(`no basic auth credentials`). zot's access control is the same for every hostname, so the whole
registry (UI included) is LAN-only: it isn't exposed on the public Gateway at all. Pushes still need
the `tekton` user. Laptops on the LAN pull from `registry.local.casasulgorgo.net` directly; for
anything else, log in with an API key created in the UI.

## Builder

Every repo builds with the `nix-build` Task: per `name,attr,flakedir` entry of the Trigger's `images` binding,
`nix flake check`, then `nix run <flake>#<attr>.copyTo` (nix2container → skopeo). There's no Dockerfile
builder: rootless BuildKit needed Unconfined seccomp/AppArmor, user namespaces on the nodes and a
`privileged` namespace, all gone with it.

`nix-build` runs `nixos/nix` single-user and non-root: a first step copies the image's `/nix` into an
emptyDir owned by uid 1000, the build step mounts it as `/nix`. `sandbox = false` (the pod is the sandbox), so
no user namespaces, RuntimeDefault seccomp, no capabilities. The flake must expose
`packages.x86_64-linux.<attr>` as a nix2container image with the `commit-timestamp` label (see casasulgorgo's
`flake.nix` for Node, kubbot's for Rust with crane).

Steps: `seed-store` → `build-and-push` → `push-cache` → `scan-closure` (sbomnix + vulnix, below).
`push-cache` runs even when the build fails (`build-and-push` has `onError: continue`; `scan-closure`
then exits with its code, so the run still fails), and before the scans. A failed build or CVE check
keeps whatever finished, e.g. crane's dependencies when the app doesn't compile. A derivation that dies
halfway (one crate inside the dependencies) has nothing to cache.

### Nix cache

nixpkgs comes from cache.nixos.org; everything the repos build or fetch themselves (crane's dependency
derivation, npm/crate tarballs, the app, the image layers) goes to the bucket `nix-cache` on
[RustFS](storage.md), a plain S3 binary cache reached over the in-cluster Service.

- Every step substitutes from it with the read-only keys (Secret `nix-cache-read`). Only `push-cache` gets
  the write keys (`nix-cache-write`) and the signing key (`nix-cache-signing-key`, SOPS, in
  `infrastructure/configs/tekton/`). Those mounts are in that step's container only, never where builds run.
  The public key is in the Task's `trusted-public-keys`.
- `push-cache` uploads every store path without a cache.nixos.org or our own signature, skipping `.drv`
  files, signed with `secret-key` on the upload.
- Best effort: `push-cache` has `onError: continue`, the credentials are optional, and `fallback = true`
  builds locally when a NAR is missing. A RustFS outage only makes the build slower.
- Objects expire after 30 days (bucket lifecycle). Whatever is still needed gets rebuilt and pushed again.
- Bucket, policies, users and both credential Secrets come from tofu (`tofu/modules/rustfs`, wired in
  `tofu/production/k8s.tf`).
- To rotate the signing key: generate it with `nix key generate-secret --key-name nix-cache.casasulgorgo.net-<n+1>`
  into the SOPS Secret (written and encrypted in one command), and swap the public key in `nix-build.yaml`.
  Paths signed with the old key stop being trusted and get rebuilt.

The trust model: whatever a build produced gets signed, so a malicious flake in a watched repo could poison
the cache for later builds. It's the same trust the pipeline already gives that repo's image.

### Why Nix rather than Dockerfiles

What it gives:

- **Reproducible:** every input is pinned (`flake.lock`, lockfile hashes), with fixed timestamps, so the same
  commit gives the same image.
- **Minimal:** the image holds only the runtime closure (no shell, package manager or base distro).
- **Granular layers:** nix2container makes one layer per store path, so an app change doesn't re-push node or
  glibc.
- **Rootless:** no user namespaces or privileges, so `tekton-ci` runs PodSecurity `restricted`.
- **Exact SBOM and patch-aware CVE checks:** sbomnix reads the real dependency graph, and vulnix knows which
  CVEs nixpkgs has patched.
- **Same toolchain locally and in CI:** the devShell, `just vulnix` and the CI build all use one pinned
  nixpkgs.

What it costs:

- **Cold builds without the cache:** the first build of a change to the dependencies compiles them all
  (~13 minutes for casasulgorgo, ~35 for kubbot's matrix-sdk). After that they come from the
  [Nix cache](#nix-cache).
- **grype false positives:** grype matches versions and can't see nixpkgs backports, hence `.grype-ignore`.
- **Fixes wait on nixpkgs:** a fix lands only once nixpkgs ships it (e.g. openssl).
- **Learning curve:** the Nix language, plus build wrappers such as `buildNpmPackage` for toolchains that
  expect network access while building.

**How dependencies are downloaded:** `npm install` doesn't run during the build. `buildNpmPackage` splits it
in two:

1. **Fetch:** a *fixed-output derivation* downloads the tarballs. Nix allows network access only for
   derivations whose output hash is known in advance. With `importNpmLock` the hashes are the lockfile's
   `integrity` fields, so a tampered or changed tarball fails the build.
2. **Build:** `npm ci` runs offline against that fetched cache, then `npm run build`.

The same holds for Go modules, Cargo crates and anything else fetched with `fetchurl`. With `sandbox = true`,
Nix blocks network access in the build step. In CI we run `sandbox = false`, so the build step *could* reach
the network, and the pod's egress policy is the fence. Reproducibility still rests on the pinned hashes.

## Vulnerability scans

`scan-image` runs grype on the pushed image, which sees OS package databases (dpkg/apk) and Nix store paths
(by name and version, blind to nixpkgs' CVE patches). That misses dependencies adapter-node bundles into
`build/` and statically linked Rust/Go binaries. `scan-source` (after `build`) closes the gap: syft catalogs the repository's lockfiles
(npm devDependencies included, since adapter-node bundles them) and grype fails the run on a fixable
vulnerability of `fail-on` severity (default high) or worse.

nix-build checks each image's runtime closure (node, glibc, …) with vulnix rather than grype: vulnix skips CVEs
that a nixpkgs patch names (`CVE-<id>.patch`), where grype's CPE matching would report nixpkgs' backports as
false positives and has no fix versions to go by. Without a `vulnix.toml` in the flake directory the result is
only printed in the log. With one, any CVE not in it fails the run, so a repo opts in once its first reports are
triaged: `vulnix -C -W vulnix.toml <image out path>` writes the current matches as a starting whitelist; give each
entry a `comment` and an `until` date so exceptions expire. vulnix downloads the NVD feeds on every run (there's
no cache volume yet), which adds a few minutes to the build.

Exceptions to both grype scans go in `.grype-ignore` at the repository root, one per line:

```
# <CVE/GHSA id> <until YYYY-MM-DD> <reason>
CVE-2026-124709 2026-12-23 openssl 3.5.10 not in nixpkgs yet
```

The scan tasks turn it into a grype config holding only those `ignore` ids, so a repo can't loosen any other
option or ignore a whole package. A malformed line, or one past its `until` date, fails the run.

## Build isolation (`tekton-ci`)

- **PodSecurity `restricted`**: every step runs non-root with RuntimeDefault seccomp, no
  capabilities and no privilege escalation (Tekton's `set-security-context` flag covers its own
  init containers). No host access, so no extra admission policy is needed.
- **Cilium**: builds reach DNS, zot, RustFS (Nix cache, port 9000) and the public internet on 443. RFC1918/CGNAT/link-local
  ranges are excluded, so a build can't reach the LAN or the nodes. Only the
  EventListeners accept ingress: `github` from the Gateway, `tekton-events` from tekton-events-controller.
- **Signing key outside**: the Chains key lives in `tekton-chains`, which no pipeline can read. The Nix
  cache's signing key is in `tekton-ci`, but only the `push-cache` step mounts it.
- **LimitRange**: default 2 CPU / 2Gi per step container, max 3 CPU / 4Gi.
- The Tekton Pruner keeps 5 successful and 5 failed runs (max 7 days). Workspace PVCs go with them.

## Debugging

- `tkn pr list -n tekton-ci`, `tkn pr logs -f -n tekton-ci <run>`
- `kubectl -n tekton-ci logs -l eventlistener=github` (accepted events; rejections only at debug level,
  so check GitHub's webhook "Recent Deliveries" response body first)
- `kubectl -n tekton-ci logs -l eventlistener=tekton-events` (CloudEvents → release runs)
- `kubectl -n tekton-chains logs deploy/tekton-chains-controller`; a signed run carries the annotation
  `chains.tekton.dev/signed: "true"`
- `flux get images all -A`

## Retries

Network-bound tasks retry up to twice on their own (`retries: 2`): `clone`, `sbom`, `scan` (grype's DB download)
and `release`. `build` and `deploy` don't: a failed compile or an unhealthy rollout fails the same way again.
`git-clone` wipes its directory first, so a retry starts clean.

To re-run a whole failed run by hand, use **Rerun** on the run in the Tekton Dashboard
(`tekton.local.casasulgorgo.net`, pocket-id login), or push again (`git commit --allow-empty`).
The dashboard is the full install, but its edit rights are limited to `tekton-ci`
(`infrastructure/controllers/tekton/patch-dashboard.yaml`) and it's only reachable through its oauth2-proxy.
