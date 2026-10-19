# Security

## Pod Security Standards

All workloads target the Kubernetes `restricted` Pod Security Standard. The following security context is applied to every app deployment.

### Full restricted (stateless/standard apps)

Used for: `norish`, `silverbullet`, `gatus`

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

1. Create `apps/<name>/ciliumnetworkpolicy.yaml`
2. Allow DNS egress + gateway ingress as a minimum
3. Add cross-namespace rules for postgres, valkey, etc. as needed
4. Add it to `apps/<name>/kustomization.yaml` resources

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

## Future improvements

- **Runtime security with [Tetragon](https://tetragon.io):** eBPF observability (and optional
  enforcement) through `TracingPolicy` resources, e.g. credential changes, kernel module loads,
  `mount`/`ptrace` calls, writes to sensitive files. Start observe-only (`action: Post`) and narrow
  noisy hooks (`tcp_connect`, `cap_capable`) with selectors. It runs from the Cilium Helm repo and
  needs `/sys/kernel/tracing` mounted plus `kernel.kptr_restrict = 1` on Talos (currently `2`, see
  `tofu/modules/talos/nodes.tf`).
