# Radicle

A [Radicle](https://radicle.dev) seed node for publishing git repos (`apps/radicle`).

| Piece | Where |
|---|---|
| `radicle-node` (P2P, TCP 8776) | `radicle-node` Deployment, LAN-only LoadBalancer `192.168.0.203` |
| `radicle-httpd` (read-only JSON API) | same pod, public at `https://rad.marcods.dev` |
| Web explorer | `radicle-explorer` Deployment, public at `https://git.marcods.dev` |
| Images | Tangled repo `radicle-images` → `registry.local.casasulgorgo.net/radicle/{node,explorer}` |

## How it fits together

- The node is **outbound-only**: it dials the public seeds (iris, rosa) and replicates through them.
  The router doesn't forward 8776 and `node.externalAddresses` is empty, so no one on the internet can dial in.
- Only the read-only web side is public, through the Cloudflare-proxied Gateway like any other app.
  The explorer is static: visitors' browsers call `rad.marcods.dev` directly (httpd allows any CORS origin).
- There is no login. Identity is the Ed25519 key; pushes are signed by your **local** node and
  replicated. The seed has its own key, generated on first start into the PVC (`keys/radicle`, no passphrase).
  Back up the PVC if the node ID should survive.

## Publishing a repo

1. On the laptop: `rad init` in the repo (public), then `git push rad`.
2. Add `<alias> <rid>` to `apps/radicle/config/repos`. The init container runs `rad seed` for it, and httpd
   serves it under the alias: `https://git.marcods.dev/nodes/rad.marcods.dev/<alias>`.
3. At home, connect the laptop directly: `rad node connect <seed-nid>@192.168.0.203:8776`
   (the seed's NID is printed by the init container: `kubectl -n radicle logs deploy/radicle-node -c init`).

Removing a line from `repos` doesn't unseed: `kubectl -n radicle exec deploy/radicle-node -c node -- rad unseed <rid>`.

## Making P2P public

Forward TCP 8776 on the router to `192.168.0.203`, add an unproxied (DNS-only) record for it, and set
`node.externalAddresses` to `["<host>:8776"]` in `config/config.json`. This exposes the home IP.
