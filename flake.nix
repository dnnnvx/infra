{
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config = {allowUnfree = true;};
        };
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
          ];
        };
      }
    );
}
