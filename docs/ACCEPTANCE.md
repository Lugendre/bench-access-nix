# 受け入れ確認手順

本デプロイ（bench-access-nix）が仕様どおり動くことの確認手順と、これまでの確認結果。

## 開発環境で確認済み（ローカル）

### ビルド・構文・スキーマ
- `nix build .#kble-serialport` 成功（`kble-serialport` バイナリ生成）。
- `nix build .#probe-rs`（probe-rs-tools 0.31, remote feature）成功し、`probe-rs serve --help` が `serve` サブコマンドを表示（remote feature が有効である証拠）。
- systemd ユニットの `systemd-analyze verify` はプレースホルダ `@…@` 由来の警告のみ（構文エラーなし）。
- `install.sh` の `bash -n` 構文 OK。
- `config/probe-rs.toml.example` の TOML 妥当性、`[server]`/`[[server.users]]`/`access` スキーマが probe-rs v0.31 ソースと一致。

### 機能スモークテスト（実機なし・ローカル実行・PASS）
- **kble-serialport（UART⇄WS 双方向）**: `socat` の pty ペアを仮想シリアルに見立て、`kble-serialport --addr 127.0.0.1 --port 19600` を起動。`websocat` で `ws://127.0.0.1:19600/open?port=<pty>&baudrate=115200` に接続し、双方向のバイト疎通を実測（WS→シリアル: `PING_FROM_WS`、シリアル→WS: `PONG_FROM_SERIAL` を実バイトで確認。WebSocket Upgrade 101 成功、エラーログなし）。
- **probe-rs serve（認証つきリモート）**: テスト用 `.probe-rs.toml`（`[server] address="127.0.0.1" port=13000` + `[[server.users]]` token）で起動し `127.0.0.1:13000` を LISTEN。`probe-rs list --host ws://127.0.0.1:13000 --token <tok>` が接続・認証に成功して応答（実機なしのため `No debug probes were found`）。不正トークンはサーバ側で `Client failed to authenticate` として拒否されることも確認。

> 注: 上記スモークテストは WSL2 開発環境でのローカル機能確認。実プローブ/実 UART の疎通と Twingate 越しの到達制御は、下記の実機確認が必要。

## 実機での受け入れ確認（Debian ホスト=root / ローカル=各 consumer）

事前に `sudo TWINGATE_ADDR=<ip> ./install.sh` を実行し、`/etc/bench-access/.probe-rs.toml` を編集（token/bind/probe-access）して `sudo systemctl restart probe-rs-serve.service` 済みであること。

### 1. 常駐と自動復帰（§9-3）

リモート（Debian）で:

```bash
systemctl is-active probe-rs-serve.service kble-serialport.service   # 期待: 両方 active
sudo systemctl kill -s SIGKILL kble-serialport.service
sleep 3
systemctl is-active kble-serialport.service                          # 期待: active（自動復帰）
```

ホスト再起動後も両サービスが自動起動していること（`enable` 済み）も確認する。

### 2. プローブ列挙（§9-4）

ローカルで:

```bash
probe-rs list --host ws://<host>:3000 --token <tok>
```

期待: リモートに接続されたデバッグプローブが列挙される。

### 3. UART 双方向（§9-5, §9-6）

ローカルで対象デバイスへ送受信:

```bash
websocat -b "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"
```

期待: 双方向に送受信できる。USB シリアルを抜き差ししても、同じ `by-id` パスで同一デバイスに再接続できることも確認する。

## 結果の記録

各項目の結果（OK/NG とログ要点）を、確認時に本ファイルへ追記して記録する。
