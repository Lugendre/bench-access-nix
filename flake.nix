{
  description = "Remote debug-probe + UART access deployment (Debian, systemd)";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    kble-nix.url = "github:Lugendre/kble-nix";
    probe-rs-tools-nix.url = "github:Lugendre/probe-rs-tools-nix";
  };

  outputs = { self, flake-utils, kble-nix, probe-rs-tools-nix }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system: {
      packages = {
        kble-serialport = kble-nix.packages.${system}.kble-serialport;
        probe-rs = probe-rs-tools-nix.packages.${system}.default;
      };
    });
}
