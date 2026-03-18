# Storage (Piraeus/LINSTOR)

Piraeus provides distributed storage via LINSTOR + DRBD, backed by the Talos nodes' local disks.

## Storage classes

| Class          | Pool          | Replicas | Nodes         | Use case                        |
|----------------|---------------|----------|---------------|---------------------------------|
| `piraeus`      | `file-thin`   | 2        | nuc-103/104   | Default — replicated app data   |
| `piraeus-hdd`  | `lvm-thin-hdd`| 1        | nuc-102 only  | Bulk data — recordings, logs    |

- **`piraeus`**: File-backed thin provisioning on NVMe/eMMC. 2 replicas across nuc-103 and nuc-104 via DRBD. No LVM needed — LINSTOR creates sparse files under `/var/lib/linstor-pool/` on the OS disk. Good for databases, app state, anything that needs redundancy.
- **`piraeus-hdd`**: LVM thin provisioning on the 500GB HDD in nuc-102. Single replica (no replication). Uses a dedicated LVM Volume Group on the raw block device (`/dev/sda`), giving the HDD its own I/O path separate from the NVMe boot disk. Meant for large, replaceable data like NVR recordings.

## Pool configuration (GitOps)

Both pools are declared as `LinstorSatelliteConfiguration` CRDs in `config/piraeus/`:
- `storage-pool.yaml` — `file-thin` pool, applied to nodes with label `cluster.casasulgorgo.net/storage: local`
- `storage-pool-hdd.yaml` — `lvm-thin-hdd` pool, applied to nodes with label `cluster.casasulgorgo.net/storage: hdd`

The node labels are set by Tofu via the Talos machine config.

## HDD pool prerequisites (nuc-102)

The HDD pool requires the `dm_thin_pool` kernel module, loaded via the Talos machine config in `tofu/homelab/main.tf` → `extra_config_patches`. If the module is missing (`modprobe: FATAL: Module dm-thin-pool not found`), add it to the kernel modules list and run `tofu apply`.

The VG `linstor-hdd-vg` and thin pool `linstor-hdd-thinpool` are created automatically by the `LinstorSatelliteConfiguration` when the satellite pod starts with the correct kernel module and node label.

If the thin pool needs to be recreated manually:

```bash
# Check pool status
kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor storage-pool list -n nuc-102

# Create the thin pool (from the satellite pod)
kubectl exec -n piraeus-datastore linstor-satellite.nuc-102-<suffix> -c linstor-satellite -- \
  lvcreate -l 100%FREE -T linstor-hdd-vg/linstor-hdd-thinpool

# Restart CSI controller to publish capacity (if scheduler shows "not enough storage")
kubectl rollout restart deployment/linstor-csi-controller -n piraeus-datastore
```

## Useful LINSTOR commands

```bash
# All commands run inside the linstor-controller pod
alias linstor='kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor'

linstor storage-pool list              # Pool status per node
linstor volume list                    # All volumes and their locations
linstor resource list                  # DRBD resources and sync status
```
