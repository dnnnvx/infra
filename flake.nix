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
          packages = with pkgs; [
            opentofu
            k9s
            kubie
            talosctl
            kubernetes-helm
            nmap
            just
            fluxcd
            yq-go
          ];
        };
      }
    );
}
