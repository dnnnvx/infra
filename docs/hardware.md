# Hardware

| Node    | CPU          | Role          | IP            | Storage                              |
|---------|--------------|---------------|---------------|--------------------------------------|
| nuc-101 | Celeron J3455| Control plane | 192.168.0.101 | —                                    |
| nuc-102 | i3-7100U     | Worker        | 192.168.0.102 | 500GB HDD (system disk, no pool)     |
| nuc-103 | J5005        | Worker        | 192.168.0.103 | ~110GB file-thin (piraeus)           |
| nuc-104 | J5005        | Worker        | 192.168.0.104 | ~110GB file-thin (piraeus)           |

- **VIP**: `192.168.0.100`
- **Gateway LB**: `192.168.0.200`
- **AdGuard DNS**: `192.168.0.201`

## Known issue: nuc-102 won't cold boot Talos from its NVMe

nuc-102 (NUC7i3BNH) hangs on the Talos splash screen after a real restart when Talos is installed on its
Samsung PM961 NVMe (`MZVLW256HEHP`, sold as `MZ-VLW2560`). It looks fine until then, because the reboot after
the install probably goes through kexec and skips the firmware, and booting from USB also works. With no
network it can't be reached, so it seems to need re-adding every time.

Installed on the 2.5" HDD with the NVMe taken out, it survived a `talosctl` reboot and a forced power-off
(2026-10-31), so `install_disk` is `/dev/sda` and the NVMe is on the shelf. Disconnecting the HDD didn't help.
The root cause is unconfirmed: the drive's SMART data was never read, and the M.2 slot wasn't tested
separately. The same drive shows the same hang in Talos issues
[#14146](https://github.com/siderolabs/talos/issues/14146) and
[#14490](https://github.com/siderolabs/talos/issues/14490), both open with no fix when this was written.

- Don't buy another PM961 (`PM961`, `MZ-VLW…`, `MZVLW…`).
- Before going back to the NVMe or adding another M.2 drive, test with a throwaway install and a forced
  power-off, with the HDD out. A different model isn't proven to work. Retest the PM961 after a Talos 1.14 upgrade.
- The bay and the M.2 slot are the only drive connectors, so an M.2 system disk would free the HDD for bulk storage.
