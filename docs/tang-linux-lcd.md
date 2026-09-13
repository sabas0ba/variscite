# Tang Primer 20K: Linux、LCD コンソール、GUI

## 目的と現状

既存の Veryl RV32IMA コアで NOMMU / M-mode Linux を実機起動し、800×480 LCD に
ブートログを表示した後、Linux のユーザプロセスから GUI を描画する。
RTL は DDR3 制御、LCD 読み出し、基板トップまで Veryl で実装する。

現在の実機はオンチップ RAM 32 KiB とベアメタルの矩形表示で動作している。
Linux はシミュレータ上で起動済みだが、実機の DDR3、カーネル転送、フレームバッファは
未実装である。本書と capability probe の追加だけで Linux が実機起動するわけではない。

## 最初の実測: DDR3 PHY のツール対応

2026-09-07、既存の固定コンテナ内で `DQS` の最小 Veryl インスタンスを合成・配置した。

```bash
bash scripts/check_ddr_toolchain.sh
```

- 対象: `GW2A-LV18PG256C8/I7`、family `GW2A-18C`
- コンテナ: `sha256:8ddc50649d4ae3fda9d5790f60ebeb7b8ee28a7dbd53f0547b4234945ffd6143`
- Veryl: v0.20.3
- Yosys: `0.68+40`, `0f2bcb94b-dirty` (固定配布バイナリの表示)
- nextpnr: `nextpnr-0.11-1-g62e659ed`
- 結果: Veryl 変換と Yosys 合成は成功。packing も成功するが、placement で失敗。

```text
ERROR: Unable to place cell 'dqs', no BELs remaining to implement cell type 'DQS'
```

3 本の I/O と DQS 1 個だけの回路で発生するため、CPU や LCD との資源競合ではない。
Yosys にプリミティブ宣言が存在することだけでは、nextpnr が配置できることを保証しない。
この結果は現在の固定ツールにおける DQS ベース PHY の制約であり、他の PHY 方式や
将来のツールで DDR3 が利用不可能であることを意味しない。

再現用 RTL は `fpga/tang_primer_20k/ddr_capability_probe.veryl`。
これは合成・配置能力の検査専用であり、クロック比やピンを DDR3 実動作用に構成していない。
ビットストリームを生成せず、基板へは書き込まない。
結果は `sim/fpga/ddr_capability/{versions,veryl,yosys,nextpnr}.log` に保存する。
終了コード非ゼロを正常な DDR3 対応として扱わず、通常の `make all` には含めない。

## 実装順序と合格条件

| 段階 | 実装 | 合格条件 |
|---|---|---|
| 1. DDR3 | PHY、初期化・校正、refresh、byte mask、CPU バスとの応答待ち | データ・アドレスの walking pattern、疑似乱数、境界、部分書き込み、refresh をまたぐ保持試験を実機で通す |
| 2. Linux 起動 | ブート ROM、UART 経由の Image/DTB 転送、CRC 検査、実機 DTS | カーネルから `/init` に到達し、UART シェル、タイマ、ユーザプロセス起動を確認 |
| 3. LCD ブートログ | DDR3 上の RGB565 フレームバッファ、LCD 読み出し DMA、ライン FIFO、Linux fbcon | UART と LCD に同じカーネルログが現れ、連続スクロールで FIFO underrun がない |
| 4. GUI | `/dev/fb0` へ描画する軽量な Linux ユーザアプリケーション | Linux プロセスとして画面・文字・操作状態を描画し、UART 入力に応答する |

最初のブート手段は既存 USB-UART を使用し、SD カードへの書き込みを前提にしない。
初期の GUI はフレームバッファへ直接描画し、追加 UI ライブラリを必要としない構成で着手する。
タッチ、USB キーボードなどの入力機器は、その後に接続構成とドライバを確認する。

## メモリと表示の設計条件

- 基板の DDR3 公称容量は 128 MiB。実機のメモリ型番・geometry と初期化条件を確認し、
  alias 検査で実容量を確定してから DTS に記述する。
- CPU は既存の NOMMU / M-mode 構成を継続する。ROM から Linux へ移る際に hartid と
  DTB アドレスを `a0` / `a1` へ渡す。
- 現在の `FpgaSoc` は固定 2 サイクル応答である。DDR3 は可変レイテンシなので、要求を
  保持して完了を待つバス接続が必要。既存ベアメタル用トップも回帰検証する。
- RGB565 の 800×480 は 768,000 byte。33 MHz の表示では、active 区間の瞬間読み出しは
  66 MB/s、1056×505 の走査全体で平均約 47.5 MB/s となる。DDR3 の CPU/DMA 仲裁と
  ライン FIFO は refresh やバンク操作による停止を含めて設計する。
- フレームバッファ領域を Linux の通常 RAM から予約し、ブートローダで表示回路を初期化する。
  Linux v6.12 の `simple-framebuffer` と fbcon を第一候補とする。
- UART の実クロックは 27 MHz。現在のシミュレータ用 DTS の 1 MHz UART 設定は流用しない。
  ブート初期は UART earlycon、fbcon 初期化後に蓄積したカーネルログを LCD に表示する。
  カーネル開始前の表示はブートローダの進捗表示として別に扱う。

## GOWIN EDA による配置配線の検証

2026-09-13、利用者の再開指示を受けて公式 Linux 教育版を専用コンテナに導入した。
`ddr_gowin_probe.veryl` の DQS、DLL、OSER4_MEM、IDES4_MEM 各 1 個を接続した
双方向 1 bit の回路について、合成・配置配線と資源の残存を確認した。
DLLSTEP の定数接続は GOWIN が拒否するため、このプローブでは実際の DLL 出力を接続する。
nextpnr 用の最小プローブとは構造が異なり、直接の同一回路比較ではない。

これは配置配線ツールの対応検査である。PCLK/FCLK は同一入力、基板ピンとタイミングは
未制約であり、DDR3 の動作周波数、タイミング収束、校正、読み書きの成立を示さない。
GOWIN は `run pnr` でビットストリームも生成するが、**このプローブは実機へ書き込まない**。
実機のベアメタル LCD ビットストリームは変更していない。

| 項目 | 固定値 |
|---|---|
| GOWIN EDA | V1.9.11.03 Education Linux |
| 公式アーカイブ SHA256 | `6fd392f7473b24d847b6f8ebdc7a185c591826ba35d8d0e517961030d446f9f7` |
| 公式公開 MD5 (取得時照合) | `d65912e3da9cdbebed92f0ccc5feb498` |
| Ubuntu ランタイム snapshot | `20260901T000000Z` |
| ランタイム依存 | `container/gowin-runtime.sha256` と `container/gowin-runtime.versions.tsv` の 56 パッケージ |
| 検証済み専用イメージ ID | `sha256:1b9cfd5aefe08b418ea5f43f5f0cf7efbd1b20c551506deac8d691bba9f2a70b` |

`container/Gowin.Containerfile` は既存の固定開発イメージを継承する。
Ubuntu パッケージは `/opt/gowin-runtime` に展開し、GOWIN プロセスだけが参照する。
Qt の `offscreen` 設定でディスプレイサーバーなしに CLI を起動する。
ベンダー同梱の旧ライブラリと新しい fontconfig の混在を避けるため、ランタイムと
Ubuntu 標準ライブラリを GOWIN 同梱ライブラリより先に探索する。
ホストへのインストール、外部ソースの RTL への取り込みは行っていない。

以下はリポジトリのルートで実行する Bash 表記。Windows では bind mount の `$PWD` を
リポジトリの絶対パスに置き換える。取得手順にはネットワークと依存追加の許可が必要。
教育版の利用条件は公式配布元で確認し、アーカイブと専用イメージは公開しない。

```bash
base=sha256:8ddc50649d4ae3fda9d5790f60ebeb7b8ee28a7dbd53f0547b4234945ffd6143
podman run --rm --pull never -v "$PWD:/work" "$base" \
  curl --fail --location --retry 2 \
  --output logs/Gowin_V1.9.11.03_Education_Linux.tar.gz \
  https://cdn.gowinsemi.com.cn/Gowin_V1.9.11.03_Education_Linux.tar.gz
podman run --rm --pull never -v "$PWD:/work" "$base" \
  bash scripts/fetch_gowin_runtime.sh
podman build --pull=never --network=none \
  --ignorefile container/gowin.containerignore \
  -f container/Gowin.Containerfile -t localhost/variscite-gowin:1.9.11.03 .
podman run --rm --pull never --network none -v "$PWD:/work" \
  localhost/variscite-gowin:1.9.11.03 bash scripts/check_ddr_gowin.sh
```

結果は `sim/fpga/ddr_gowin/` の `veryl.log`、`gowin.log`、`impl/pnr/` に保存する。
スクリプトは配置配線の完了、新しいレポート、4 種類の資源数を検査してから PASS を返す。
クロック未制約の警告はこの構造検査の制限として残し、動作タイミングの合格とは扱わない。
実機用 PHY ではクロック生成、DDR3 ピン制約、2 レーンと 16 bit の接続、初期化と
校正を実装し、実メモリの読み書き・refresh 試験を通す必要がある。

## Linux 起動に向けた接続部の実装 (2026-09-13)

DDR3 の実メモリ試験に先立ち、以下を独立した Veryl モジュールとして追加した。
まだ既存 CPU トップへ組み込んでおらず、Linux の実機起動や DDR3 の読み書きが
成立したことを示すものではない。

| モジュール | 内容 | 検証 |
|---|---|---|
| `Ddr3Startup` | RESET 保持、RESET 解除後待ち、CKE、MR2→MR3→MR1→MR0、ZQCL、完了待ち | 短縮/実時間相当の 2 設定で各 9 回の初期化。コマンド受理待ち、途中リセット、PHY readiness 喪失を検査 |
| `DdrWordCdc` | CPU 32 bit と DDR 128 bit バースト間のメールボックス CDC | 3 種類のクロック比で各 133 トランザクション。全 16 通りの byte mask と 4 word lane、遅延応答、同時応答、停止クロック中の共通リセットを検査 |
| `TangDdrClock` | 27 MHz → PLL 396 MHz → DHCEN → CLKDIV /4 → 99 MHz | SERDES を負荷とする検証トップで GOWIN 合成・配置配線。派生クロック周期 2.525 ns / 10.101 ns の認識を確認 |

```bash
make ddr3-startup-test ddr-word-cdc-test
bash scripts/check_ddr_clock.sh  # GOWIN 専用コンテナ
```

2 種類の RTL テストは `make all` と CI の `verify` に含める。
クロック検証はベンダーツールを必要とするため CI の通常ジョブには含めない。
クロック検証トップの基板制約は基準クロックと DDR 差動クロックだけであり、
生成ビットストリームを実機へ書き込まない。396 MHz の外部メモリ I/O タイミングを
保証する検査ではない。

CDC の要求・応答ペイロードは、対応する toggle が同期先に届くまで保持する。
リセットは必ず両クロック領域に共通の非同期リセットを与え、接続先の要求/応答処理も
同時に中断する。解除はモジュール内で各クロックの 2 段 FF に同期する。
片側だけのリセットには対応しない。1 要求につき応答は 1 回、
CPU は `o_ready` を受け取るまで要求を保持する。
DDR 側の書き込みは BL8 の 128 bit に対する 16 bit byte enable で表現するため、
PHY 側で DDR3 DM のマスク極性へ反転する必要がある。32 bit 書き込みに
read-modify-write は不要である。

初期化シーケンサの既定値は 99 MHz の制御クロックを想定し、RESET を 200 µs、
解除後を 500 µs 保持する。CL=6、CWL=5、WR=6、DLL 有効/リセットの設定は
型番確定前の候補である。待ち時間と MR 値はパラメータ化した。
`ZQ_CYCLES` にはコマンド受理から実際の DRAM コマンド発行までの PHY 遅延も含める。
実機に適用する前に、搭載チップの型番・速度 grade・電圧とデータシートで確認する。

未実装: 16 bit PHY、DLL 初期化、write leveling/read calibration、通常の DRAM
コマンド発行と refresh、CPU トップへの統合、UART ブートローダ、LCD framebuffer。
搭載 DDR3 の型番を利用者へ確認中であり、実機のメモリ初期化・書き込みは実施していない。

## 一次資料

- [Sipeed Tang Primer 20K 仕様](https://en.wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html)
- [LiteDRAM の GW2A DDR PHY](https://github.com/enjoy-digital/litedram/blob/master/litedram/phy/gw2ddrphy.py): DQS とメモリ用 SERDES の接続例。参照のみで、依存として導入していない。
- [Tang Primer 20K 用 DDR3 コントローラ](https://github.com/nand2mario/ddr3-tang-primer-20k): Gowin ツールによる実装例。参照のみで、ソースは取り込んでいない。
- Linux v6.12 のローカル資料: `/opt/src/linux/Documentation/devicetree/bindings/display/simple-framebuffer.yaml`
- [GOWIN EDA 公式配布元](https://gowinsemi.com/en/support/home/)
- [GOWIN 教育版と公開チェックサム](https://www.gowinsemi.com.cn/software/3)
- GOWIN 同梱の一次資料: `/opt/gowin/IDE/simlib/gw2a/prim_sim.v` の DLL/DQS/SERDES 宣言
- [Ubuntu Snapshot Service](https://snapshot.ubuntu.com/)
- [Winbond W631GU6MB Rev. A03 データシート (メーカー文書、DigiKey 配布)](https://media.digikey.com/pdf/Data%20Sheets/Winbond%20PDFs/W631GU6MB_A03.pdf): 初期化の参照資料。実機の搭載型番をこの型番と断定していない。
