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

## ツール選択が必要な項目

DQS を利用する DDR3 PHY の実装例は Gowin の配置配線ツールを使用している。
まず公式 GOWIN EDA の Linux 版をプロジェクト専用コンテナで利用し、Veryl が生成した SV を
入力して DDR3 の合成・配置を確認する案を候補とする。
ホストへグローバルに導入せず、アーカイブのバージョンと SHA256 を固定する。
配布アーカイブの取得・新規ツール導入は、利用者の依存追加に関する規約に従って事前確認する。

オープンソースツールのみを継続する場合は、DQS/メモリ用 SERDES の対応拡張、または
別 PHY の成立性検証が先行課題になる。現時点ではその実現性・実機タイミングは未確認。

## 一次資料

- [Sipeed Tang Primer 20K 仕様](https://en.wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html)
- [LiteDRAM の GW2A DDR PHY](https://github.com/enjoy-digital/litedram/blob/master/litedram/phy/gw2ddrphy.py): DQS とメモリ用 SERDES の接続例。参照のみで、依存として導入していない。
- [Tang Primer 20K 用 DDR3 コントローラ](https://github.com/nand2mario/ddr3-tang-primer-20k): Gowin ツールによる実装例。参照のみで、ソースは取り込んでいない。
- Linux v6.12 のローカル資料: `/opt/src/linux/Documentation/devicetree/bindings/display/simple-framebuffer.yaml`
- [GOWIN EDA 公式配布元](https://gowinsemi.com/en/support/home/)
