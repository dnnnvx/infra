# CI/CD

Tekton builds images, zot stores them, Tekton Chains signs them, Flux deploys them. The design follows
[Konflux](https://konflux-ci.dev) (a Tekton-based platform) at homelab scale: a build pipeline that can't sign or
release anything, provenance generated and signed outside the pipeline, and a release pipeline that trusts
signatures, not whoever triggered it. CI holds no cluster or git write credentials.
Pushes to this repository run a separate, read-only validation pipeline
([Infra validation](#infra-validation-validate-infra)).

```
git push main (Tangled) ──signed webhook──▶ ci.casasulgorgo.net ─▶ EventListener "tangled" (tekton-ci)
    interceptors: tangled (HMAC check) ─▶ cel (filter + tags)
    └▶ PipelineRun build-image: clone ─▶ build (buildkit) ─┬▶ sbom (syft + oras attach)
                                          │ push :<sha>    └▶ scan (grype, fails on fixable high/critical)
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

Images are `<project>/<image>`, where project is set in the app's Trigger (the Tangled repo itself may be called anything, e.g. `web`):
`registry.local.casasulgorgo.net/casasulgorgo/web`.

| Tag | Meaning |
|-----|---------|
| `<full commit sha>` | Immutable, one per build. Pushed by buildkit, before scans and signing |
| `latest` | Last released build of the default branch |
| `production` | What should run in production (`main` → production). Moved by release-image only |

Apps reference `…/web:production@sha256:<digest>`, and Flux rewrites the digest
(`digestReflectionPolicy: Always`). Every rollout is therefore a commit, and a
rollback is a `git revert`. Build caches go to `cache/<project>/<image>:buildcache`
so they don't clutter the real repositories.

## Where things live

| Path | What |
|------|------|
| `infrastructure/controllers/tekton/` | Tekton Pipelines, Triggers (+ core interceptors), Pruner, Chains, Dashboard (read-only, `tekton.local.casasulgorgo.net`): upstream release manifests, versions bumped by Renovate. `chains/` (release + config), `secrets-chains.yaml` (SOPS signing key, applied with the controller that mounts it), `patch-events.yaml` (CloudEvents sink) |
| `infrastructure/controllers/zot/` | zot HelmRelease, config (`values.yaml`), SOPS secrets (htpasswd, OIDC client, session keys), UI-only HTTPRoute |
| `infrastructure/configs/tekton/` | `tekton-ci` namespace and its fences, RBAC, push credentials, Chains public key (`chains.pub` → ConfigMap `chains-public-key`), webhook HMAC secret, dashboard HTTPRoute |
| `infrastructure/configs/tekton/tasks/` | one file per Task (`git-clone`, `buildkit`, `sbom`, `scan-image`, `release-image`, `flux-sync`, `validate-manifests`, `lint-tofu`, `checkov`, `trufflehog`) |
| `infrastructure/configs/tekton/pipelines/` | one file per Pipeline (`build-image`, `release-image`, `validate-infra`) |
| `infrastructure/configs/tekton/triggers/` | TriggerTemplates, EventListeners (`tangled`: public webhooks; `tekton-events`: internal CloudEvents), the `tangled` ClusterInterceptor, this repo's Trigger (`trigger-infra.yaml`), the release Trigger (`trigger-release.yaml`), webhook HTTPRoute |
| `.checkov.yaml`, `tofu/.tflint.hcl` | scanner config for `validate-infra` |
| `clusters/production/apps/<project>.yaml` | the app's Flux Kustomization `app-<project>` |
| `apps/<project>/ci.yaml` | the app's Trigger, ImageRepository/ImagePolicy per image and name-scoped `flux-sync` Role/RoleBinding |
| `apps/<project>/kustomization.yaml` | `images:` entry with the `digest:` marker Flux rewrites |
| `tofu/production/main.tf` | Talos `StaticHostConfig` pinning `registry.local.casasulgorgo.net` to the LAN Gateway, so pulls don't depend on DNS |

## Build, sign, release

**build-image** (started by the app's Trigger) clones, builds and pushes each image under its commit tag only,
then runs two tasks in parallel:

- **sbom**: syft writes an SPDX SBOM per image and oras attaches it to the image as an OCI referrer
  (`application/spdx+json`). Its blob digest is the `sboms` result.
- **scan**: grype scans the image and fails the run on vulnerabilities of severity `high` or worse that have a
  fix (`fail-on` param, `--only-fixed`). Unfixable CVEs don't block a release.

The pipeline has no signing key and never moves `latest`/`production`.

**Tekton Chains** (namespace `tekton-chains`, key in `signing-secrets`) watches PipelineRuns. When one succeeds it
signs every image named in the type-hinted `IMAGES` result and generates a SLSA v1.0 provenance for the whole run
(deep inspection: every TaskRun, its params, results and step images). Both go to zot as Sigstore bundles
referring to the image (OCI 1.1 referrers). Same choices as Konflux's Chains config, see
`infrastructure/controllers/tekton/chains/patch-chains.yaml`. Nothing goes to the public Rekor log, so verification
skips the tlog. Chains authenticates to zot with `pipeline-runner`'s `imagePullSecrets` (`registry-push`).

**release-image** is started by the `release` Trigger on the internal `tekton-events` EventListener, which receives
Tekton's own CloudEvents. A `dev.tekton.event.pipelinerun.successful.v1` event of a `build-image` run becomes a
release run with the build's `registry`, `project`, `tags`, `flux-kustomization` params and `digests` result. It:

1. waits (up to 5 min) until each digest has a Chains signature and SLSA provenance, verifying both against
   `chains.pub`;
2. moves the release tags with crane, unless the tag already points at a newer commit;
3. runs `deploy` (flux-sync, below), skipped when step 2 moved nothing.

The event isn't authenticated. That's fine: release-image only promotes digests signed by Chains, i.e. images that
a successful build-image run produced. The worst a forged event can do is re-release such an image, and even that
can't roll back: buildkit stamps every image with the label `ci.casasulgorgo.net/commit-timestamp` (committer date
from git-clone), and release-image leaves a tag alone when its current image has a later timestamp. Images without
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

Not done yet (Konflux has them): an admission policy that rejects unsigned images (Kyverno or Conforma), and
policy checks on the provenance's content (e.g. "built by build-image from a main commit").

## Flux sync (deploy task)

After the release, the optional `deploy` task (`flux-sync`, ServiceAccount `flux-sync`) skips Flux's polling:
it reconciles the ImageRepository, waits until the ImagePolicy resolves the pushed digest, runs
`ImageUpdateAutomation/apps` (the bot commit), then reconciles `app-<app>` with its source and waits for
the rollout. A failed rollout fails the release PipelineRun. Names follow a convention: ImageRepository/ImagePolicy `<project>-<image>` and Kustomization `app-<project>`.
An app may have several images: the `buildkit` task builds them one after the other and returns a
`name=digest` list, and `flux-sync` waits for every policy before the single bot commit.
A build started without `flux-kustomization` is released without the task.

Every app has its own Kustomization (`clusters/production/apps/<project>.yaml`), so the deploy task waits
for this app only: an unhealthy unrelated app doesn't fail the release.

## Adding a repo/image

1. Copy `apps/casasulgorgo/ci.yaml` into `apps/<project>/` (list it in its `kustomization.yaml`) and
   `clusters/production/apps/casasulgorgo.yaml` to `<project>.yaml` (list it in `clusters/production/apps/kustomization.yaml`).
   Replace the project name, the Tangled repository name in the Trigger's CEL filter and the image name
   (the header comment of `ci.yaml` lists every spot). For more images, add an ImageRepository/ImagePolicy pair per image, its name in the
   Role's `resourceNames`, and a `<name>,<dockerfile>,<context>` entry in the Trigger's space-separated `images` binding
   (`dockerfile` relative to `context`, `context` relative to the repo root).
2. In `apps/<project>/kustomization.yaml`, use a kustomize `images:` entry per image with a `digest:` marker
   `# {"$imagepolicy": "flux-system:<project>-<image>:digest"}` (copy casasulgorgo's).
3. On Tangled: repo **Settings → Hooks** → payload URL `https://ci.casasulgorgo.net/`, event `push`,
   secret = `tangled-webhook` value (`just edit-secret infrastructure/configs/tekton/secrets.yaml`).

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
- Results only show up in Tekton (dashboard, `tkn pr list -n tekton-ci -l ci.casasulgorgo.net/project=infra`):
  nothing reports back to Tangled.

## Webhook verification

Tangled signs the body as `X-Tangled-Signature-256: sha256=<hmac>`. That's the same
scheme as GitHub, but under a header name the built-in `github` interceptor doesn't read.
`infrastructure/configs/tekton/triggers/interceptor-tangled.yaml` runs a small custom ClusterInterceptor
([`ghcr.io/dnnnvx/tangled-interceptor`](https://github.com/dnnnvx/tangled-interceptor), a static
Rust binary) that checks it. The `cel` interceptor then filters the
event and computes the tags. Because the payload is authenticated, the Trigger takes the
clone URL, repo name and commit from it.

## Registry access

| Who | How | Rights |
|-----|-----|--------|
| Humans | `registry.local.casasulgorgo.net` UI (LAN), Pocket-ID login (`registry_admins` group = admin) | read; admins delete |
| Tekton (pipelines, Chains) | `tekton` htpasswd user, `tekton-ci/registry-push` (Chains via `pipeline-runner`'s `imagePullSecrets`) | read, create, update |
| containerd (nodes), Flux | anonymous (zot `anonymousPolicy`) | read |

Anonymous read is enabled because the kubelet's pulls don't use the Talos `RegistryAuthConfig`
(`no basic auth credentials`). zot's access control is the same for every hostname, so the whole
registry (UI included) is LAN-only: it isn't exposed on the public Gateway at all. Pushes still need
the `tekton` user. Laptops on the LAN pull from `registry.local.casasulgorgo.net` directly; for
anything else, log in with an API key created in the UI.

## Build isolation (`tekton-ci`)

Rootless BuildKit needs Unconfined seccomp/AppArmor, so the namespace runs at PodSecurity
`privileged`. What fences it in again:

- **`ValidatingAdmissionPolicy` `tekton-ci-pod-restrictions`**: no hostPath, host namespaces,
  hostPorts, privileged containers or added capabilities for anyone. Unconfined profiles
  are allowed only for pods created by the Tekton controller (TaskRuns).
- **Cilium**: builds reach DNS, zot and the public internet on 443. RFC1918/CGNAT/link-local
  ranges are excluded, so a Dockerfile `RUN` can't reach the LAN or the nodes. Only the
  EventListeners accept ingress: `tangled` from the Gateway, `tekton-events` from tekton-events-controller.
- **Signing key outside**: the Chains key lives in `tekton-chains`, which no pipeline can read.
- **LimitRange**: default 2 CPU / 2Gi per step container, max 3 CPU / 4Gi.
- The Tekton Pruner keeps 5 successful and 5 failed runs (max 7 days). Workspace PVCs go with them.

## Debugging

- `tkn pr list -n tekton-ci`, `tkn pr logs -f -n tekton-ci <run>`
- `kubectl -n tekton-ci logs -l eventlistener=tangled` (rejected webhooks show up here)
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
