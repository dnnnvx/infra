# Security [disabled]

## Runtime Security (Tetragon)

[Tetragon](https://tetragon.io) provides eBPF-based runtime security observability. It runs as a DaemonSet in `kube-system` and applies `TracingPolicy` resources that hook into the Linux kernel to observe (and optionally enforce) security-relevant events.

### Deployment

- HelmRelease: `infrastructure/tetragon/` (depends on Cilium, uses `cilium` HelmRepository)
- Helm values: `clusters/homelab/values/tetragon.yaml`
- Policies: `config/tetragon/`

Key values configured:

| Value | Setting | Reason |
|---|---|---|
| `enableProcessCred` | `true` | Include uid/gid/capabilities in all events |
| `enableProcessNs` | `true` | Include Linux namespace info in events |
| `clusterName` | `homelab` | Tags all events with cluster name |
| `exportFilename` | `""` | No on-disk log file; use `tetra` CLI |
| `grpc.address` | `0.0.0.0:54321` | Reachable for `tetra getevents` |
| `extraHostPathMounts` | `/sys/kernel/tracing` | Required on Talos Linux |

### Active policies

All policies are **observe-only** (`action: Post`). No enforcement is applied until behavior is well understood.

| File | What it detects |
|---|---|
| `privileges-raise.yaml` | `commit_creds` — any credential change in a container. Rate-limited 1/min. (`override_creds`/`revert_creds` omitted — inlined in Talos kernel) |
| `modules.yaml` | Kernel module auto-load requests, file reads for module loading, module init and unload |
| `sys-mount.yaml` | Any `mount()` syscall (source + target path logged) |
| `sys-ptrace.yaml` | Any `ptrace()` call (request type + target pid logged) |
| `sensitive-files.yaml` | Writes and truncations to `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, `/etc/ssh/` |

### Disabled policies (`.disabled` files)

Kept in `config/tetragon/` as commented-out YAML for future reference:

| File | Why disabled |
|---|---|
| `tcp-connect.yaml.disabled` | Very high volume — every outbound TCP connection from every pod. Enable once you have a log aggregator (Vector, Loki) to absorb the load, or add `matchBinaries` / `matchNamespaces` selectors to narrow scope |
| `creds-capability-usage.yaml.disabled` | Medium volume — `cap_capable` fires on every capability check during normal operation. Enable with tight selectors if investigating a specific workload |

### Commands

```bash
# List all policies and their load state
kubectl exec -n kube-system ds/tetragon -c tetragon -- tetra tracingpolicy list

# Stream all events
kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents

# Filter to a specific namespace
kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents --namespace default

# Only kprobe events (policy hits)
kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents --output json \
  | jq 'select(.process_kprobe != null)'

# Compact view: policy name + binary + args
kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents --output json \
  | jq -c 'select(.process_kprobe != null) | {policy: .process_kprobe.policy_name, binary: .process_kprobe.process.binary, args: .process_kprobe.args}'

# Stream events from a specific pod
kubectl exec -it -n kube-system ds/tetragon -c tetragon -- tetra getevents \
  --pod-name <pod> --namespace <ns>

# Check raw pod logs (mixes operational + event output)
kubectl logs -n kube-system ds/tetragon -c tetragon -f

# Verify kptr_restrict is 1 on all nodes (required for kprobe symbol resolution)
talosctl read /proc/sys/kernel/kptr_restrict -n 192.168.0.101,192.168.0.102,192.168.0.103,192.168.0.104

# Restart Tetragon (e.g. after sysctl changes)
kubectl rollout restart ds/tetragon -n kube-system
kubectl rollout status ds/tetragon -n kube-system
```

### Escalating a policy to enforcement

To move a policy from observe to enforce, replace `action: Post` with `action: Sigkill` (kills the process) or `action: Override` with `argError: -1` (returns EPERM to the syscall). Test in a non-production namespace first using `matchNamespaces` selectors.

---

## Pod Security Standards

All workloads target the Kubernetes `restricted` Pod Security Standard. The following security context is applied to every app deployment.

### Full restricted (stateless/standard apps)

Used for: `norish`, `jotty`, `gatus`

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

### Partial (apps requiring root)

Used for: `home-assistant`, `lightnvr` — these need root for hardware/device access.

```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

> `runAsNonRoot` is intentionally omitted. Add it back if the image ever supports non-root.

### su-exec / privilege dropping apps

Used for: `pocket-id` — uses `su-exec` internally to drop privileges after startup. Drop all capabilities then add back only what `su-exec` needs.

```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["SETUID", "SETGID", "CHOWN"]
```

### Port 53 (DNS services)

Used for: `adguard-home` — needs `NET_BIND_SERVICE` to bind to port 53.

```yaml
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          add: ["NET_BIND_SERVICE"]
```

## Kyverno Policy Engine

[Kyverno](https://kyverno.io) runs as an admission controller and background scanner, enforcing and auditing policies across the cluster. All policies run in **Audit** mode — violations are reported but workloads are not blocked. Enforce mode can be enabled per-policy once violations are resolved.

### Deployment

- HelmRelease: `infrastructure/kyverno/` + `infrastructure/policy-reporter/`
- Helm values: `clusters/homelab/values/kyverno.yaml`, `clusters/homelab/values/policy-reporter.yaml`
- Custom policies: `policies/kyverno/`
- Upstream policies: synced from `github.com/kyverno/policies` via Flux Kustomizations in `policies/`
- UI: `kyverno.home` (Policy Reporter)

### Upstream policies (via GitRepository)

Pulled from `github.com/kyverno/policies`, applied as individual Flux Kustomizations:

| Kustomization | Path | What it covers |
|---|---|---|
| `kyverno-pss` | `pod-security/restricted` | Full Kubernetes Pod Security Standards restricted profile |
| `kyverno-bp-*` | `best-practices/*` | Deprecated API checks, CRI socket mounts, default namespace, latest tag, drop-all caps, labels, resource limits, probes, read-only rootfs, NodePort, externalIPs, namespace quotas |
| `kyverno-flux-*` | `flux/*` | Flux image signature verification (Cosign), Git repository source validation |
| `kyverno-cm-*` | `cert-manager/*` | Certificate duration limits |

### Custom policies

| Policy | What it checks |
|---|---|
| `require-cilium-network-policy` | Every namespace must have at least one `CiliumNetworkPolicy` |
| `disallow-extra-mutable-tags` | Rejects image tags: `edge`, `stable`, `dev`, `master`, `main` (upstream handles `latest`) |
| `verify-flux-sources` | GitRepositories must be on github.com or tangled.org; HelmRepositories must use known registries |
| `cert-manager-restrict-issuer` | Certificates for `*.casasulgorgo.net` must use the `letsencrypt-prod` ClusterIssuer |

### Exceptions

`policies/kyverno/exceptions.yaml` — `piraeus-datastore` is fully exempt from PSS policies (storage daemons require elevated privileges).

### Testing policies locally

```bash
just test-policies   # runs kyverno test policies/kyverno/
```

Each custom policy has a `.kyverno-test/` directory with pass/fail fixtures. API call context (e.g. `cnpCount`) is mocked via `values.yaml`.

### Policy Reporter

Aggregates policy results and sends Telegram notifications for violations at `warning` severity or above. Reports are visible at `kyverno.home`.

---

## Pod Security Admission (PSA)

All namespaces are labeled with PSA `warn` and `audit` mode to surface violations without blocking workloads. Once all images are confirmed compliant, enforce mode can be enabled per namespace.

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

Apps that require root (home-assistant uses `hostNetwork`, pocket-id uses `su-exec`) use `privileged` or `baseline` enforce levels set explicitly on their namespace.

To move a namespace from warn to enforce, change `warn` → `enforce` after confirming no PSA warnings appear in events:

```bash
kubectl get events -n <namespace> --field-selector reason=FailedCreate
```

## Secrets

Secrets are encrypted at rest using [SOPS](https://github.com/getsops/sops) with an age key. See [Secrets](./secrets.md) for details.

## Network Policies

All namespaces have a `CiliumNetworkPolicy` with `endpointSelector: {}` (applies to all pods) providing default-deny ingress and egress, with explicit allow rules for only what each app needs.

### Key rules

- **DNS egress** — every namespace allows egress to `kube-system/kube-dns` on UDP/TCP 53
- **Gateway ingress** — apps with an HTTPRoute allow `fromEntities: [ingress]` (Cilium's reserved entity for the Envoy proxy). A standard `namespaceSelector: {}` does **not** cover Gateway traffic
- **Cross-namespace egress** — apps explicitly allow egress to the namespaces they need.

### Adding a new app

1. Create `apps/<name>/overlays/homelab/networkpolicy.yaml`
2. Allow DNS egress + gateway ingress as a minimum
3. Add cross-namespace rules for postgres, valkey, etc. as needed
4. Add to the overlay `kustomization.yaml` resources

### Pattern reference

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default
  namespace: myapp
spec:
  endpointSelector: {}
  ingress:
    - fromEntities:
        - ingress
  egress:
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            io.kubernetes.pod.namespace: cnpg-system
      toPorts:
        - ports:
            - port: "5432"
              protocol: TCP
```
