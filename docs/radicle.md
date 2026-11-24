# Radicle

A [Radicle](https://radicle.dev) seed node for publishing git repos (`apps/radicle`).

| Piece | Where |
|---|---|
| `radicle-node` (P2P, TCP 8776) | `radicle-node` Deployment, LAN-only LoadBalancer `192.168.0.203` |
| `radicle-httpd` (read-only JSON API) | same pod, public at `https://rad.marcods.dev` |
| Web explorer | `radicle-explorer` Deployment, public at `https://git.marcods.dev` |
| Images | [`dnnnvx/radicle-images`](https://github.com/dnnnvx/radicle-images) → `ghcr.io/dnnnvx/radicle-{node,httpd,explorer}:<x.y.z>` (upstream versions; a daily job there builds new releases after checking their signatures). Renovate bumps the tags here |

## How it fits together

- The node is **outbound-only**: it dials the public seeds (iris, rosa) and replicates through them.
  The router doesn't forward 8776 and `node.externalAddresses` is empty, so no one on the internet can dial in.
- Only the read-only web side is public, through the Cloudflare-proxied Gateway like any other app.
  The explorer is static: visitors' browsers call `rad.marcods.dev` directly (httpd allows any CORS origin).
- There is no login. Identity is the Ed25519 key; pushes are signed by your **local** node and
  replicated. The seed has its own key, generated on first start into the PVC (`keys/radicle`, no passphrase).
  Back up the PVC if the node ID should survive.

## Identities

Two keys, never shared:

| Key | Where | Purpose |
|---|---|---|
| Personal | laptop, `~/.radicle/keys/`, passphrase-protected | owns and signs your repos (`rad self --did`) |
| Seed | the PVC, unencrypted so the node starts unattended | identifies the server only |

Don't sign with the seed key or copy it to a laptop. Two nodes with one Node ID break routing, and a
key that sits unencrypted on a cluster volume shouldn't own anything. Radicle keys can't be rotated:
back up `~/.radicle/keys/`, because losing the key or its passphrase loses control of every repo it published.
## Public repos only

Radicle's node-to-node protocol is currently broken for private repos
([disclosure, 2026-09-23](https://radicle.dev/2026/09/23/disclosure-of-vulnerability-in-network-protocol)).
Traffic isn't encrypted, and a peer can claim someone else's Node ID in the handshake, so an on-path
attacker can read a private repo or fetch it by posing as an allow-listed peer. Every release so far is
affected. The fix will be a breaking major release that moves the transport to iroh, and old and new
nodes won't talk to each other. Public repos are fine: their content is public anyway, and signed refs
still catch tampering, so code and identities can't be forged.

Until a fixed release:

- **Never `rad init --private`.** Keep private code on Tangled or GitHub.
- The seed already only serves what's listed in `config/repos` (`seedingPolicy` is `block`).
- nixpkgs marks `radicle-node` insecure for this reason. `~/.config/nix/flake.nix` permits exactly `radicle-node-1.10.3`:
  a newer release that's still flagged fails evaluation again, as a reminder to re-check this section.
- When the fixed major ships: bump the seed and the laptop together (they can't talk across versions),
  drop `permittedInsecurePackages`, and update this section.

## Publishing a repo

1. On the laptop, with the local node running (`rad node start`): `rad init` in the repo (public, never
   `--private`). This copies it into `~/.radicle/storage` and announces it. Later, `git push rad` updates that
   local copy, and the node announces the new refs.
2. Add `<alias> <rid>` (the RID comes from `rad .`) to `apps/radicle/config/repos` and push. The ConfigMap
   hash changes, so the pod restarts, the init container runs `rad seed`, and httpd serves the repo under its
   alias: `https://git.marcods.dev/nodes/rad.marcods.dev/<alias>`.
3. Get the code onto the seed. If it isn't there yet, run
   `kubectl -n radicle exec deploy/radicle-node -c node -- rad sync --fetch <rid>`.

Neither the laptop nor the seed accepts connections from the internet, so away from home they never talk
directly. The copy goes through the bootstrap seeds instead: iris and rosa seed every public repo, so it
travels laptop → iris/rosa → seed. At home, `rad node connect <seed-nid>@192.168.0.203:8776` gives a direct
path. That's faster and doesn't depend on a third party. Connections work both ways, so the seed fetches
over the one the laptop opened. The seed's NID is printed by the init container:
`kubectl -n radicle logs deploy/radicle-node -c init`.

Removing a line from `repos` doesn't stop seeding it. Block it by hand:
`kubectl -n radicle exec deploy/radicle-node -c node -- rad block <rid>`. Upstream recommends `block` over
`unseed`, because unseeding falls back to the default policy, which would keep serving the repo if the default
ever becomes `allow`.

## Making P2P public

Forward TCP 8776 on the router to `192.168.0.203`, add an unproxied (DNS-only) record for it, and set
`node.externalAddresses` to `["<host>:8776"]` in `config/config.json`. This exposes the home IP.
