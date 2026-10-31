# Storage (Piraeus/LINSTOR)

Piraeus provides distributed storage via LINSTOR + DRBD, backed by the Talos nodes' local disks.

## Storage classes

| Class          | Pool          | Replicas | Nodes         | Use case                        |
|----------------|---------------|----------|---------------|---------------------------------|
| `piraeus`      | `file-thin`   | 2        | nuc-103/104   | Default — replicated app data   |
| `piraeus-scratch` | `file-thin` | 1      | nuc-103/104   | Throwaway — CI workspaces       |

- **`piraeus`**: File-backed thin provisioning on the nodes' SATA SSDs. 2 replicas across nuc-103 and nuc-104 via DRBD. No LVM needed — LINSTOR creates sparse files under `/var/lib/linstor-pool/` on the OS disk. Good for databases, app state, anything that needs redundancy.
- **`piraeus-hdd`** (LVM thin pool on nuc-102's HDD) was removed; `storage-pool-hdd.yaml` and
  `storage-class-hdd.yaml` are in git history. The disabled `lightnvr` app still asks for it. nuc-102 is back, but
  the HDD is now its system disk (see [Hardware](hardware.md)) and the old volume group was erased, so it has no pool.
  A bulk class would be a one-replica pool on that disk, with only one copy of the data: back up anything that
  can't be downloaded again.

## Volume snapshots

`infrastructure/controllers/snapshot-controller` (kube-system) installs the VolumeSnapshot CRDs and the
snapshot-controller; LINSTOR's csi-snapshotter sidecar takes the snapshots. `VolumeSnapshotClass` `piraeus`
(default, `deletionPolicy: Delete`) works because `file-thin` is a thin pool. Snapshots stay on the same nodes as the
volume, so they are not a backup.

## Pool configuration (GitOps)

The pool is declared as a `LinstorSatelliteConfiguration` CRD in `infrastructure/configs/piraeus/`:
- `storage-pool.yaml` — `file-thin` pool, applied to nodes with label `cluster.casasulgorgo.net/storage: local`

The node labels are set by Tofu via the Talos machine config.

`satellite-heap.yaml` caps the satellite JVM on the control plane (diskless tie-breaker) at `-Xmx256m`;
the image default is `-Xmx2G`.

## Useful LINSTOR commands

```bash
# All commands run inside the linstor-controller pod
alias linstor='kubectl exec -n piraeus-datastore deploy/linstor-controller -- linstor'

linstor storage-pool list              # Pool status per node
linstor volume list                    # All volumes and their locations
linstor resource list                  # DRBD resources and sync status
```
