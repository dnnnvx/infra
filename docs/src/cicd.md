# CI/CD

Tekton builds images, zot stores them, Flux deploys them. CI holds no cluster
or git write credentials: the only thing Tekton can do is push images.

```
git push main (Tangled) ──signed webhook──▶ ci.casasulgorgo.net ─▶ EventListener "tangled" (tekton-ci)
    interceptors: tangled (HMAC check) ─▶ cel (filter + tags)
    └▶ PipelineRun build-image: clone ─▶ buildkit (rootless)
                                            │ push <project>/<image>:<sha>, :latest, :production
                                            ▼
                         zot  (zot.zot.svc.cluster.local:5000, ClusterIP pinned by tofu)
                                            │ scan `production`, reflect its digest
Flux ImageRepository/ImagePolicy ◀──────────┘
Flux ImageUpdateAutomation ─▶ commits the new digest to apps/** on main ─▶ kustomize-controller deploys
```

## Images and tags

Images are `<project>/<image>`, where project is set in the app's Trigger (the Tangled repo itself may be called anything, e.g. `web`):
`zot.zot.svc.cluster.local:5000/casasulgorgo/web`.

| Tag | Meaning |
|-----|---------|
| `<full commit sha>` | Immutable, one per build |
| `latest` | Last build of the default branch |
| `production` | What should run in production (`main` → production) |

Apps reference `…/web:production@sha256:<digest>`, and Flux rewrites the digest
(`digestReflectionPolicy: Always`). Every rollout is therefore a commit, and a
rollback is a `git revert`. Build caches go to `cache/<project>/<image>:buildcache`
so they don't clutter the real repositories.

## Where things live

| Path | What |
|------|------|
| `infrastructure/tekton/` | Tekton Pipelines, Triggers (+ core interceptors), Pruner, Dashboard (read-only, `tekton.home`): upstream release manifests, versions bumped by Renovate |
| `infrastructure/zot/` | zot HelmRelease, config (`values.yaml`), SOPS secrets (htpasswd, OIDC client, session keys), UI-only HTTPRoute |
| `config/tekton/base/` | `tekton-ci` namespace and its fences, Tasks (`git-clone`, `buildkit`), Pipeline `build-image`, TriggerTemplate, EventListener, the `tangled` ClusterInterceptor |
| `config/tekton/overlays/production/` | Webhook HTTPRoute, push credentials, webhook HMAC secret |
| `apps/<app>/overlays/production/ci-trigger.yaml` | The app's `Trigger` (in `tekton-ci`; repo filter, image name) |
| `apps/<app>/overlays/production/image-automation.yaml` | ImageRepository + ImagePolicy for that app |
| `tofu/production/main.tf` | Talos `RegistryMirrorConfig` so containerd can pull from zot with no authorization |

## Adding a repo/image

1. Copy `apps/casasulgorgo/overlays/production/ci-trigger.yaml` into the app overlay (list it in `kustomization.yaml`), then change the repo-name filter and `image-name`.
2. In the app overlay, use a kustomize `images:` entry with a `digest:` marker
   `# {"$imagepolicy": "flux-system:<policy>:digest"}`, and add an ImageRepository + ImagePolicy (copy casasulgorgo's).
3. On Tangled: repo **Settings → Hooks** → payload URL `https://ci.casasulgorgo.net/`, event `push`,
   secret = `tangled-webhook` value (`just edit-secret config/tekton/overlays/production/secrets.yaml`).

## Webhook verification

Tangled signs the body as `X-Tangled-Signature-256: sha256=<hmac>`. That's the same
scheme as GitHub, but under a header name the built-in `github` interceptor doesn't read.
`config/tekton/base/interceptor-tangled.yaml` runs a small custom ClusterInterceptor
([`ghcr.io/dnnnvx/tangled-interceptor`](https://github.com/dnnnvx/tangled-interceptor), a static
Rust binary) that checks it. The `cel` interceptor then filters the
event and computes the tags. Because the payload is authenticated, the Trigger takes the
clone URL, repo name and commit from it.

## Registry access

| Who | How | Rights |
|-----|-----|--------|
| Humans | `registry.casasulgorgo.net` UI, Pocket-ID login (`registry_admins` group = admin) | Browse only: the Gateway bounces `/v2/<repo>/…` |
| Tekton | `tekton` htpasswd user, `tekton-ci/registry-push` | read, create, update |
| containerd (nodes), Flux | anonymous (zot `anonymousPolicy`) | read |

Anonymous read is enabled because the kubelet's pulls don't use the Talos `RegistryAuthConfig`
(`no basic auth credentials`). Pulls stay in-cluster: the Gateway bounces `/v2/<repo>/…`, and only
the UI endpoints under `/v2/_zot/` (search/metadata) are public, so repo and tag names are
visible there without logging in. Pushes still need the `tekton` user. To pull from a laptop, `kubectl -n zot port-forward svc/zot 5000`
and log in with an API key created in the UI.

## Build isolation (`tekton-ci`)

Rootless BuildKit needs Unconfined seccomp/AppArmor, so the namespace runs at PodSecurity
`privileged`. What fences it in again:

- **`ValidatingAdmissionPolicy` `tekton-ci-pod-restrictions`**: no hostPath, host namespaces,
  hostPorts, privileged containers or added capabilities for anyone. Unconfined profiles
  are allowed only for pods created by the Tekton controller (TaskRuns).
- **Cilium**: builds reach DNS, zot and the public internet on 443. RFC1918/CGNAT/link-local
  ranges are excluded, so a Dockerfile `RUN` can't reach the LAN or the nodes. Only the
  EventListener accepts ingress, and only from the Gateway.
- **LimitRange**: default 2 CPU / 2Gi per step container, max 3 CPU / 4Gi.
- The Tekton Pruner keeps 5 successful and 5 failed runs (max 7 days). Workspace PVCs go with them.

## Debugging

- `tkn pr list -n tekton-ci`, `tkn pr logs -f -n tekton-ci <run>`
- `kubectl -n tekton-ci logs -l eventlistener=tangled` (rejected webhooks show up here)
- `flux get images all -A`
