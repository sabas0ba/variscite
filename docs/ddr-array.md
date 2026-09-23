# Tang Primer 20K DDR3 アレイ書込み・読戻し診断

`DdrArrayProbe` は DDR3 初期化後、bank 0 / row 0 を開き、column 0 と 8 に異なる BL8 パターンを書いてから同じ順序で読み戻す。2 番目の書込みデータは最初の全ビット反転である。CWL=5 の WRITE コマンドは CA slot 3、CL=6 の READ コマンドは slot 2 に出す。RTL は DQS の 1 CK プリアンブル、4 CK データバースト、1 CK ポストアンブルを指示し、DQ/DM の出力イネーブルをデータバーストの間だけ有効にする。これらの外部ピン波形はまだ直接測定していない。最後に PRE を出し、診断終了後に DRAM を RESET する。実行時間は refresh 間隔より短いが、このモジュール自体は refresh や常用メモリ制御を提供しない。

READ ゲートは暫定的に lane 0 が `RCLKSEL=0`、lane 1 が `RCLKSEL=4`、両レーンのゲート位置は同じ値に固定した。これは [READ ゲート診断](ddr-read-gate.md) の検出位置を参考にした候補であり、DQ のデータアイ校正値ではない。受信データは各レーンについて `RVALID` の直前・同時・直後の controller clock と比較する。両列で同じサイクル位置に期待する 64 bit が一致した場合のみ `A` とする。`V` は両レーンで `RVALID` を観測したが全幅の一致がない状態、`B` は `RBURST` のみ、`E` は受信不能を示す。

UART の 9 文字フレーム `SFFGGHHII` は、状態 `S`、column 0 の DQ0/DQ8 8 beat 生パターン `FF/GG`、column 8 の DQ0/DQ8 生パターン `HH/II` である。期待する DQ0/DQ8 は column 0 が `5A/A5`、column 8 が `A5/5A`。これら 2 本だけの一致は全 16 bit 幅の合格を意味しない。

固定済み Gowin コンテナで `DDR_ARRAY=1 bash scripts/build_ddr_mpr.sh` を実行して bitstream を構築し、`scripts/test-ddr-init-board.ps1 -Mode DdrArray` で実機を測定する。後者は診断結果にかかわらず既知の LCD サンプルを復元する。`make ddr-array-test` は ACT、2 WRITE、2 READ、PRE の順序、DQS/DQ 出力時刻、別列の反転値、2 回目が古い値の場合の不合格を確認する。RTL は Veryl、テストベンチは SystemVerilog である。

2026-09-23、初期フレーム版 bitstream SHA256 `f7e4dd855e734077363f74155018b422516149f361e9c5873adaf972a2179c16` の 3 回のロードでは、いずれも両レーンに `RVALID` があったが全幅一致はなかった。詳細フレームは順に `V0000005A`、`V00000A15`、`V00000205` で、生ログは `logs/board/20260923-114655-DdrArray-*`、`114743`、`114803` にある。この版の UART 先頭 4 桁は生データではなく両列の一致マスクである。

両列の生パターンを出す bitstream SHA256 `eaf701fafa18911b0d72c46fe44d8e81bb67a99111056ca290cc10e01d6742ce` を同じ基板に 3 回ロードした。定常フレームは `V00A5005A`、`V053A0A15`、`V010E0205` だった。最初のロードでは lane 1 の DQ8 が両列とも期待値 `A5/5A` に一致したが、ほかのロードでは一致しなかった。全 128 bit の一致はどのロードでも得られず、書込みタイミングと読出しゲート／データアイのどちらが主要因かは未確定である。生ログは `logs/board/20260923-120050-DdrArray-*`、`120136`、`120158` にある。全 6 回の試験後に LCD サンプル復元と UART 検査は通過した。

次はゲートと受信遅延を走査し、**同じ候補で**両列の反転データがそれぞれ一致する位置を探す。安定した位置が見つかってから、全 DQ bit、byte mask、アドレス alias、refresh を検証する。現段階の結果を Linux 用 RAM の設定には使用しない。

## 一次資料

- [Gowin DDR3 PHY Interface IP User Guide](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf): CWL=5 の WRITE と CL=6 の READ の CA slot 例。
- [Gowin FPGA Primitive](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf): DQS と OSER8_MEM/IDES8_MEM の信号定義。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 搭載 DDR3 の速度・タイミング仕様。
