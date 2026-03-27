# Debugging

## Network policy drops (Hubble)

Hubble is the Cilium observability layer. It records every flow in and out of every pod.

### Setup

```bash
# Port-forward the Hubble relay (run once per session)
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Use hubble from the nix dev shell
hubble observe --server localhost:4245 --help
```

### Common queries

```bash
# Watch all drops cluster-wide (live)
hubble observe --server localhost:4245 --type drop --follow

# Last 50 drops, no noise
hubble observe --server localhost:4245 --type drop --last 50 \
  | grep -v "ICMPv6\|RouterSolicit\|L2 proto\|Stale"

# Drops in a specific namespace
hubble observe --server localhost:4245 --namespace adguard-home --type drop --last 20

# All flows between two namespaces
hubble observe --server localhost:4245 \
  --from-namespace home-assistant --to-namespace adguard-home --last 30

# Filter by port
hubble observe --server localhost:4245 --namespace adguard-home --port 53 --follow
```

### Reading the output

```
Mar 25 22:18:20: 10.244.2.107:49794 (remote-node) <> adguard-home/adguard-home-0:3000 Policy denied DROPPED
```

| Field | Meaning |
|-------|---------|
| `remote-node` | Traffic from another node's host/Cilium-internal network |
| `world` | Traffic from outside the cluster |
| `ingress` | Cilium Gateway Envoy proxy |
| `host` | Local node's host network |
| `ID:1234` | Cilium numeric identity for a pod |
| `<>` | Direction unknown (before policy verdict) |
| `->` | Ingress to pod |
| `<-` | Egress from pod |

---

## Cilium BPF policy inspection

Check what rules are actually compiled into the BPF dataplane for an endpoint — this is what Cilium *actually enforces*, not just what the YAML says.

```bash
# Find the Cilium pod on the node where the target pod runs
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

# List endpoints on that node
kubectl exec -n kube-system <cilium-pod> -- cilium endpoint list

# Get the compiled BPF policy for endpoint ID 134
kubectl exec -n kube-system <cilium-pod> -- cilium bpf policy get 134

# Filter for a specific port
kubectl exec -n kube-system <cilium-pod> -- cilium bpf policy get 134 | grep "3000"

# Dump all policy rules Cilium knows about (cluster-wide)
kubectl exec -n kube-system <cilium-pod> -- cilium policy get
```

### Gotchas

- **`fromEntities: remote-node` on custom ports**: This entity compiles correctly for port 53 when included via `fromEntities: cluster`, but does **not** compile into the BPF policy when specified alone with a custom port (`toPorts: [3000]`). Use `fromEntities: cluster` instead and accept the broader scope.

- **`fromCIDR` does not match managed endpoints**: Cilium applies identity-based matching for all in-cluster endpoints (pods, nodes). A `fromCIDR: 10.244.0.0/16` rule will **not** match a pod at `10.244.x.x` because Cilium resolves it to an identity first, bypassing the CIDR check. CIDR rules only work for truly external/unmanaged IPs.

- **L2 announcement node mismatch**: With `externalTrafficPolicy: Local`, traffic for a LoadBalancer IP is dropped if the L2 announcement is held by a different node than the one running the pod. Check with:

  ```bash
  kubectl get leases -n kube-system | grep cilium-l2announce
  kubectl get pods -n <namespace> -o wide   # compare node
  ```

---

## DNS debugging

```bash
# Test DNS from inside the cluster (no policy constraints on default ns)
kubectl run -it --rm dns-test --image=busybox --restart=Never -n default \
  -- nslookup ha.home 192.168.0.201

# Test a custom DNS server directly (bypasses OS resolver)
dig ha.home @192.168.0.201

# Test the macOS OS resolver (what curl/browsers use)
dscacheutil -q host -a name ha.home

# Show all macOS resolver config (check for search domain issues)
scutil --dns

# Flush macOS DNS cache
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# Fix .home resolution when macOS appends the search domain (search domain = "home")
# macOS router DHCP sets search domain "home", causing ha.home → ha.home.home lookup
sudo mkdir -p /etc/resolver
echo "nameserver 192.168.0.201" | sudo tee /etc/resolver/home

# Check what port AdGuard is listening on inside the pod
kubectl exec -n adguard-home adguard-home-0 -- ss -ulnp | grep 53
```

### macOS .home not resolving in browser

Firefox has its own DNS-over-HTTPS stack that ignores the OS resolver:
- **about:preferences** → Network Settings → uncheck "Enable DNS over HTTPS"
- Or add `.home` to `network.trr.excluded-domains` in `about:config`

If `dig` works but `curl` doesn't, the OS resolver is the issue — create `/etc/resolver/home` as above.

---

## Connectivity testing

```bash
# HTTP connectivity from inside a pod (no image pull policy issues)
kubectl run -it --rm curl-test --image=curlimages/curl --restart=Never -n default \
  -- curl -sv http://192.168.0.200 -H "Host: ha.home" --max-time 5

# From a pod in the same namespace
kubectl exec -n home-assistant deployment/home-assistant \
  -- wget -O- --timeout=5 http://adguard-home.adguard-home.svc.cluster.local:3000

# Check service endpoints are populated
kubectl get endpoints <service> -n <namespace>

# Verify LoadBalancer IP assignment
kubectl get svc -n <namespace>
```

---

## Logs

```bash
# Tail logs for a deployment
kubectl logs -n <namespace> deployment/<name> --follow

# Last N lines
kubectl logs -n <namespace> deployment/<name> --tail=50

# Since a duration (useful after a restart)
kubectl logs -n <namespace> deployment/<name> --since=5m

# Previous container (if pod restarted)
kubectl logs -n <namespace> <pod> --previous

# Filter for errors
kubectl logs -n <namespace> deployment/<name> --since=10m \
  | grep -i "error\|warning\|failed"
```

---

## Pod & resource inspection

```bash
# Describe a pod (events, resource limits, mounts)
kubectl describe pod -n <namespace> <pod>

# Check why a pod isn't starting
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top pods -n <namespace>

# Exec into a running pod
kubectl exec -it -n <namespace> deployment/<name> -- sh

# Check what's listening inside a pod
kubectl exec -n <namespace> <pod> -- ss -tlnp
kubectl exec -n <namespace> <pod> -- ss -ulnp   # UDP

# Check mounts and volumes
kubectl exec -n <namespace> <pod> -- df -h
kubectl exec -n <namespace> <pod> -- ls -la /data
```

---

## Flux

```bash
# Overall sync status
flux get all -n flux-system

# Force a reconciliation
flux reconcile kustomization apps --with-source

# Watch events for a specific kustomization
kubectl describe kustomization apps -n flux-system

# Check if a HelmRelease is stuck
flux get helmreleases -A
kubectl describe helmrelease <name> -n <namespace>
```

---

## Cilium L2 / LoadBalancer

```bash
# Check which node is announcing a LoadBalancer IP
kubectl get leases -n kube-system | grep cilium-l2announce

# Full details (includes holder node)
kubectl get leases -n kube-system -o json \
  | jq '.items[] | select(.metadata.name | startswith("cilium-l2announce")) | {name: .metadata.name, holder: .spec.holderIdentity}'

# Check node's Cilium internal IP (used for cross-node SNAT)
kubectl get ciliumnode <node-name> -o jsonpath='{.spec.addresses}' | python3 -m json.tool
```

---

## CNPG (Postgres)

```bash
# Check cluster health
kubectl get cluster -n cnpg-system

# Check pods
kubectl get pods -n cnpg-system

# Connect as superuser (for admin SQL)
kubectl exec -it -n cnpg-system \
  $(kubectl get pods -n cnpg-system -l cnpg.io/instanceRole=primary -o name | head -1) \
  -- psql -U postgres

# Check init Job logs
kubectl logs -n cnpg-system job/init-db

# Re-run init Job (has kustomize force annotation — just apply)
flux reconcile kustomization config --with-source
```
