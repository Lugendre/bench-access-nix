# bench-access-nix

Twingate越しに、Debianベンチホストのデバッグプローブ（probe-rs）と UART（kble-serialport）をローカルから双方向利用するためのデプロイ。

入力 flake: `kble-nix`（kble-serialport）と `probe-rs-tools-nix`（github:Lugendre/probe-rs-tools-nix、remote feature 付き probe-rs）。バージョンは `flake.lock` でピン解決されます。

## リモート（Debian, root）でのセットアップ

前提: Debian ホストに **Nix（flake 機能有効）がインストール済み**であること（`install.sh` が `nix build` を実行するため必須）。

> **注意（`sudo` と PATH）**: `install.sh` は root 実行前提ですが、`sudo` 経由の非ログインシェルは `/etc/profile.d/nix.sh` を読まず、さらに `sudo` の `secure_path` で PATH が最小化されるため、**Nix が入っていても `nix` が PATH に無く**、`install.sh` が冒頭で `nix is not installed or not on PATH` と表示して停止することがあります（`ssh host 'cmd'` / `ssh -t host 'cmd'` も非ログインシェルなので同様）。下記のように **Nix daemon profile を source してから** 実行してください。

```bash
git clone <repo-url> && cd bench-access-nix
# sudo 経由では nix が PATH に無いことが多いため、daemon profile を source してから実行する
# （source 先は Determinate / マルチユーザ標準パス。環境により異なる場合あり。
#   binary は /nix/var/nix/profiles/default/bin/nix）
# Twingate 到達 IF の IP を指定（取得できなければ 0.0.0.0 のまま + host firewall）
sudo bash -c '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && TWINGATE_ADDR=100.x.y.z ./install.sh'
```

> 既に root シェルにいて `nix` が PATH 上にある場合は、従来どおり `TWINGATE_ADDR=100.x.y.z ./install.sh` で構いません。

`install.sh` は両サーバを `nix build` して `/opt/bench-access` に GC root として固定し、`/etc/bench-access/.probe-rs.toml`・udev ルール・systemd ユニットを設置して有効化します。

初回は **`/etc/bench-access/.probe-rs.toml` を編集**してください（`[server]` の `address`/`port`、`[[server.users]]` の `token`/`access`）。`token` は任意の秘密文字列でよく、例えば `openssl rand -hex 32` で生成します（例ファイルのプレースホルダも同趣旨なので必ず置き換えること）。編集後に再起動:

```bash
sudo systemctl restart probe-rs-serve.service
```

サービスは `Restart=always` かつ `enable` 済みなので、クラッシュ・再起動後も自動復帰します。状態確認:

```bash
systemctl status probe-rs-serve.service kble-serialport.service
```

## ローカル（各 consumer）からの接続

`<host>` は Twingate 到達名/IP。ローカル側の前提ツール: シリアル利用には **websocat**（PTY を生やす手順では追加で **socat**）、プローブ利用には **probe-rs** が必要。

### デバッグプローブ（probe-rs）

bind/port/token は **リモートの `/etc/bench-access/.probe-rs.toml`** で設定済み（既定 port 3000）。クライアント:

```bash
probe-rs list --host ws://<host>:3000 --token <tok>
probe-rs run app.elf --chip <CHIP> --probe <VID:PID:Serial> --host ws://<host>:3000 --token <tok>
probe-rs attach --chip <CHIP> --probe <VID:PID:Serial> --host ws://<host>:3000 --token <tok>
```

`--probe` に渡す `<VID:PID:Serial>` は、上の `probe-rs list --host ... --token ...` の出力に表示されるので、そこからコピーします。

GDB/DAP はリモート非対応（probe-rs serve の制約）。必要ならローカルで別途。

### シリアル（websocat ベースの各用途）

`?port=` は必ず `/dev/serial/by-id/...`（USBシリアルの `/dev/ttyUSB*` 番号は挿し直しで入れ替わるため）。`<id>` はリモートで `ls /dev/serial/by-id/` を実行して確認します。URL は `&` を含むので**クォート必須**。

```bash
# 端末で直接 / パイプ越し（同一コマンド）
# 端末で実行すれば対話的に入出力でき、stdin/stdout をパイプすれば
# Claude Code やスクリプトからプログラム的に読み書きできる。
websocat -b "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"

# アプリ（ローカル TCP 化）: 5000 は例。空きポートを選ぶ
websocat -b tcp-l:127.0.0.1:5000 "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"
# → 既存アプリは localhost:5000 へ接続
```

screen/minicom で開きたい場合は、websocat の stdio を **socat** で安定した PTY シンボリックリンクに橋渡しします（websocat 単体には固定パスを与える PTY 機能はないため）。`socat` の `pty,link=` が割り当てた pts への symlink を `/tmp/uart` に作るので、それを別端末で開きます:

```bash
socat -d -d pty,link=/tmp/uart,raw,echo=0 \
  system:'websocat -b "ws://<host>:9600/open?port=/dev/serial/by-id/<id>&baudrate=115200"'
# 別端末で:
screen /tmp/uart 115200
```

任意パラメータ: `&databits=8&flowcontrol=none&parity=none&stopbits=1`（既定値）。

## セキュリティ / 注意

- kble-serialport は**無認証**で、到達できれば任意パスのデバイスを開ける。**`:9600` を外部公開しない**こと（Twingate ACL で到達者を限定、必要なら host firewall 併用）。
- probe-rs serve はトークン認証あり・TLS検証なし。Twingate 内に閉じる。
- デバイスは**排他**（同時1クライアント）。同じポートを同時に複数 consumer で掴むことはできない。
- `--port`(kble の TCP待受) と `?port=`(デバイスパス) は別物。probe-rs の bind/port は `.probe-rs.toml` 側。

## 非rootで運用したい場合（任意・ハードニング）

1. 専用ユーザ `bench` を作成する。
2. `bench` を `dialout`（シリアル）・`plugdev`（プローブ）グループに追加する。
3. 両ユニット（`kble-serialport.service` / `probe-rs-serve.service`）に `User=bench` と `SupplementaryGroups=dialout plugdev` を加える。
4. `HOME` を `bench` のホームに合わせ、`.probe-rs.toml` をそのユーザ配下に置く。

同梱の udev ルールは `GROUP="plugdev"` + `TAG+="uaccess"` でプローブへのアクセスを与えます。
