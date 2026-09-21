{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  # talosctl pinned to 1.13.9, to stay in step with the Talos cluster (v1.13.10).
  # `talosctl upgrade-k8s` validates the Kubernetes upgrade path against a table
  # compiled into the client, so a client older than the cluster rejects valid
  # upgrades ("unsupported upgrade path 1.35->1.36"). Bump this pin whenever the
  # cluster's Talos minor changes.
  #
  # A branch like nixos-unstable would not pin anything — it resolves to whatever
  # unstable is at lock time and moves on every `nix flake update`. Pin the
  # nixpkgs *revision* that carries the version you want. nixpkgs has no 1.13.10;
  # it went 1.13.9 -> 1.14.0, so 1.13.9 is the closest match.
  # Find revisions with: gh api "repos/NixOS/nixpkgs/commits?path=pkgs/by-name/ta/talosctl/package.nix"
  inputs.nixpkgs-talos.url = "github:NixOS/nixpkgs/93d692653558285e225d3b577e02e7c019b75caf";

  outputs = {
    self,
    nixpkgs,
    nixpkgs-talos,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config = {allowUnfree = true;};
        };
        # Shadows pkgs.talosctl below: a let binding takes precedence over `with`,
        # so the package list keeps reading `talosctl` unchanged.
        talosctl = nixpkgs-talos.legacyPackages.${system}.talosctl;
      in {
        devShells.default = pkgs.mkShell {
          __darwinAllowLocalNetworking = true;
          shellHook = ''
            # exec kubie ctx homelab -n flux-system
          '';
          packages = with pkgs; [
            (writeShellScriptBin "k" ''exec kubectl "$@"'')
            opentofu
            kubectl
            k9s
            kubie
            talosctl
            kubernetes-helm
            kustomize
            kubeconform
            nmap
            just
            fluxcd
            yq-go
            sops
            age
            mdbook
            renovate
          ];
        };
      }
    );
}
