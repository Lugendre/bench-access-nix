{
  description = "Remote debug-probe + UART access deployment (Debian, systemd)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # During development, kble-nix is referenced by local path; switch to
    # github:<you>/kble-nix once published.
    kble-nix.url = "path:/home/nixos/Workspace/kble-nix";
    probe-rs-tools-nix.url = "github:Lugendre/probe-rs-tools-nix";
  };

  outputs = { self, nixpkgs, flake-utils, kble-nix, probe-rs-tools-nix }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages = {
          kble-serialport = kble-nix.packages.${system}.kble-serialport;
          probe-rs = probe-rs-tools-nix.packages.${system}.default;
        };
      });
}
