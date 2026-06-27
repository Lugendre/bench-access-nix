# bench-access-nix

Twingate越しに、Debianベンチホストのデバッグプローブ（probe-rs）と UART（kble-serialport）をローカルから双方向利用するためのデプロイ。

入力 flake: `kble-nix`（kble-serialport）と `probe-rs-tools-nix`（remote feature 付き probe-rs）。

## リモート（Debian, root）でのセットアップ

```bash
git clone <this repo> && cd bench-access-nix
# Twingate 到達 IF の IP を指定（取得できなければ 0.0.0.0 のまま + host firewall）
sudo TWINGATE_ADDR=100.x.y.z ./install.sh
```

`install.sh` は両サーバを `nix build` して `/opt/bench-access` に GC root として固定し、`/etc/bench-access/.probe-rs.toml`・udev ルール・systemd ユニットを設置して有効化します。

初回は **`/etc/bench-access/.probe-rs.toml` を編集**してください（`[server]` の `address`/`port`、`[[server.users]]` の `token`/`access`）。編集後に再起動:

```bash
sudo systemctl restart probe-rs-serve.service
```

サービスは `Restart=always` かつ `enable` 済みなので、クラッシュ・再起動後も自動復帰します。状態確認:

```bash
systemctl status probe-rs-serve.service kble-serialport.service
```

## ローカル（各 consumer）からの接続

`<host>` は Twingate 到達名/IP。

### デバッグプローブ（probe-rs）

bind/port/token は **リモートの `/etc/bench-access/.probe-rs.toml`** で設定済み（既定 port 3000）。クライアント:

```bash
probe-rs list --host ws://<host>:3000 --token <tok>
probe-rs run app.elf --chip <CHIP> --probe <VID:PID:Serial> --host ws://<host>:3000 --token <tok>
probe-rs attach --chip <CHIP> --probe <VID:PID:Serial> --host ws://<host>:3000 --token <tok>
```

GDB/DAP はリモート非対応（probe-rs serve の制約）。必要ならローカルで別途。

### シリアル（websocat 一本で3用途）

`?port=` は必ず `/dev/serial/by-id/...`（USBシリアルの番号は挿し直しで入れ替わるため）。URL は `&` を含むので**クォート必須**。

```bash
# 人間（端末で直接）
websocat -b "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"

# 人間（screen/minicom で開く: ローカル PTY を生やす）
websocat -b pty:/tmp/uart "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200" &
screen /tmp/uart 115200

# アプリ（ローカル TCP 化）
websocat -b tcp-l:127.0.0.1:5000 "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"
# → 既存アプリは localhost:5000 へ接続

# Claude Code / スクリプト（stdin/stdout パイプ）
websocat -b "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"
```

任意パラメータ: `&databits=8&flowcontrol=none&parity=none&stopbits=1`（既定値）。

## セキュリティ / 注意

- kble-serialport は**無認証**で、到達できれば任意パスのデバイスを開ける。**`:9600` を外部公開しない**こと（Twingate ACL で到達者を限定、必要なら host firewall 併用）。
- probe-rs serve はトークン認証あり・TLS検証なし。Twingate 内に閉じる。
- デバイスは**排他**（同時1クライアント）。同じポートを同時に複数 consumer で掴むことはできない。
- `--port`(kble の TCP待受) と `?port=`(デバイスパス) は別物。probe-rs の bind/port は `.probe-rs.toml` 側。

## 非rootで運用したい場合（任意・ハードニング）

専用ユーザ `bench` を作り `dialout`(シリアル)・`plugdev`(プローブ) に追加し、両ユニットに `User=bench` と `SupplementaryGroups=dialout plugdev` を加える。同梱 udev ルールは `GROUP="plugdev"` + `TAG+="uaccess"` でアクセスを与える。`HOME` も `bench` のホームに合わせ、`.probe-rs.toml` をそこへ置く。
