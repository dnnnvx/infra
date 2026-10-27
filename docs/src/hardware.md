# Hardware

| Node    | CPU          | Role          | IP            | Storage                              |
|---------|--------------|---------------|---------------|--------------------------------------|
| nuc-101 | Celeron J3455| Control plane | 192.168.0.101 | —                                    |
| nuc-102 | i3-7100U     | (removed)     | 192.168.0.102 | 256GB NVMe + 500GB HDD (unused)      |
| nuc-103 | J5005        | Worker        | 192.168.0.103 | ~110GB file-thin (piraeus)           |
| nuc-104 | J5005        | Worker        | 192.168.0.104 | ~110GB file-thin (piraeus)           |

- **VIP**: `192.168.0.100`
- **Gateway LB**: `192.168.0.200`
- **AdGuard DNS**: `192.168.0.201`
