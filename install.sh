#!/usr/bin/env bash
set -euo pipefail

# Deploy probe-rs serve + kble-serialport on a Debian host via systemd.
# Run as root. Env vars:
#   FLAKE         deployment flake ref (default: current directory)
#   TWINGATE_ADDR kble-serialport --addr bind address (default: 0.0.0.0)

PREFIX=/opt/bench-access
CONFIG_HOME=/etc/bench-access
FLAKE="${FLAKE:-$(pwd)}"
TWINGATE_ADDR="${TWINGATE_ADDR:-0.0.0.0}"
NIX_FLAGS=(--extra-experimental-features 'nix-command flakes')

if [ "$(id -u)" -ne 0 ]; then
  echo "install.sh must run as root" >&2
  exit 1
fi
if ! command -v nix >/dev/null 2>&1; then
  echo "nix is not installed or not on PATH" >&2
  exit 1
fi

mkdir -p "$PREFIX" "$CONFIG_HOME"

# Build both servers and pin them as GC-root out-links (stable ExecStart paths).
nix "${NIX_FLAGS[@]}" build "${FLAKE}#kble-serialport" --out-link "$PREFIX/kble-serialport"
nix "${NIX_FLAGS[@]}" build "${FLAKE}#probe-rs"        --out-link "$PREFIX/probe-rs"

# probe-rs server config: install once; operator edits tokens/bind before real use.
if [ ! -f "$CONFIG_HOME/.probe-rs.toml" ]; then
  install -m 600 ./config/probe-rs.toml.example "$CONFIG_HOME/.probe-rs.toml"
  echo "Installed $CONFIG_HOME/.probe-rs.toml - EDIT tokens/bind/probe-access before real use." >&2
else
  echo "$CONFIG_HOME/.probe-rs.toml already exists - left unchanged." >&2
fi

# udev rules for debug probes.
install -m 644 ./udev/69-probe-rs.rules /etc/udev/rules.d/69-probe-rs.rules
udevadm control --reload
udevadm trigger

# systemd unit templates: substitute placeholders and install.
sed -e "s#@KBLE@#$PREFIX/kble-serialport/bin/kble-serialport#g" \
    -e "s#@ADDR@#$TWINGATE_ADDR#g" \
    ./systemd/kble-serialport.service > /etc/systemd/system/kble-serialport.service
sed -e "s#@PROBE_RS@#$PREFIX/probe-rs/bin/probe-rs#g" \
    -e "s#@HOME@#$CONFIG_HOME#g" \
    ./systemd/probe-rs-serve.service > /etc/systemd/system/probe-rs-serve.service

systemctl daemon-reload
systemctl enable --now kble-serialport.service probe-rs-serve.service
systemctl status --no-pager kble-serialport.service probe-rs-serve.service || true
