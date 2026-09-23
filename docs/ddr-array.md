# Tang Primer 20K DDR3 アレイ書込み・読戻し診断

`DdrArrayProbe` は DDR3 初期化後、bank 0 / row 0 を開き、column 0 と 8 に異なる BL8 パターンを書いてから同じ順序で読み戻す。2 番目の書込みデータは最初の全ビット反転である。CWL=5 の WRITE コマンドは CA slot 3、CL=6 の READ コマンドは slot 2 に出す。RTL は DQS の 1 CK プリアンブル、4 CK データバースト、1 CK ポストアンブルを指示し、DQ/DM の出力イネーブルをデータバーストの間だけ有効にする。これらの外部ピン波形はまだ直接測定していない。最後に PRE を出し、診断終了後に DRAM を RESET する。実行時間は refresh 間隔より短いが、このモジュール自体は refresh や常用メモリ制御を提供しない。

READ ゲートは暫定的に lane 0 が `RCLKSEL=0`、lane 1 が `RCLKSEL=4`、両レーンのゲート位置は同じ値に固定した。これは [READ ゲート診断](ddr-read-gate.md) の検出位置を参考にした候補であり、DQ のデータアイ校正値ではない。受信データは各レーンについて `RVALID` の直前・同時・直後の controller clock と比較する。両列で同じサイクル位置に期待する 64 bit が一致した場合のみ `A` とする。`V` は両レーンで `RVALID` を観測したが全幅の一致がない状態、`B` は `RBURST` のみ、`E` は受信不能を示す。

UART の 9 文字フレーム `SFFGGHHII` は、状態 `S`、column 0 の DQ0/DQ8 8 beat 生パターン `FF/GG`、column 8 の DQ0/DQ8 生パターン `HH/II` である。期待する DQ0/DQ8 は column 0 が `5A/A5`、column 8 が `A5/5A`。これら 2 本だけの一致は全 16 bit 幅の合格を意味しない。

固定済み Gowin コンテナで `DDR_ARRAY=1 bash scripts/build_ddr_mpr.sh` を実行して bitstream を構築し、`scripts/test-ddr-init-board.ps1 -Mode DdrArray` で実機を測定する。後者は診断結果にかかわらず既知の LCD サンプルを復元する。`make ddr-array-test` は ACT、2 WRITE、2 READ、PRE の順序、DQS/DQ 出力時刻、別列の反転値、2 回目が古い値の場合の不合格を確認する。RTL は Veryl、テストベンチは SystemVerilog である。

2026-09-23、初期フレーム版 bitstream SHA256 `f7e4dd855e734077363f74155018b422516149f361e9c5873adaf972a2179c16` の 3 回のロードでは、いずれも両レーンに `RVALID` があったが全幅一致はなかった。詳細フレームは順に `V0000005A`、`V00000A15`、`V00000205` で、生ログは `logs/board/20260923-114655-DdrArray-*`、`114743`、`114803` にある。この版の UART 先頭 4 桁は生データではなく両列の一致マスクである。

両列の生パターンを出す bitstream SHA256 `eaf701fafa18911b0d72c46fe44d8e81bb67a99111056ca290cc10e01d6742ce` を同じ基板に 3 回ロードした。定常フレームは `V00A5005A`、`V053A0A15`、`V010E0205` だった。最初のロードでは lane 1 の DQ8 が両列とも期待値 `A5/5A` に一致したが、ほかのロードでは一致しなかった。全 128 bit の一致はどのロードでも得られず、書込みタイミングと読出しゲート／データアイのどちらが主要因かは未確定である。生ログは `logs/board/20260923-120050-DdrArray-*`、`120136`、`120158` にある。全 6 回の試験後に LCD サンプル復元と UART 検査は通過した。

読出しゲートを 0–7 controller cycle で走査する `DdrArrayScanProbe` を追加した。2 列に各1回書き込んだ後、各候補で2列を読み、DQ0 と DQ8 の 8 beat パターンをそれぞれ照合する。UART フレーム `SPPQQRRSS` の `PP` は DQ0、`QQ` は DQ8 のゲート通過マスクで、下位 bit が早いゲート位置を表す。`T` は両レーンでそれぞれいずれかの候補が2列の反転パターンに一致したことを表し、全幅一致を示さない。`V`、`B`、`E` は従来と同じ受信状態を表す。固定済み Gowin コンテナでは `DDR_ARRAY_SCAN=1 bash scripts/build_ddr_mpr.sh`、実機では `scripts/test-ddr-init-board.ps1 -Mode DdrArrayScan` を用いる。`make ddr-array-gate-test` は8候補のコマンド・ゲート時刻と、DQ0/DQ8で異なる候補が通過する場合を検証する。

走査 bitstream SHA256 `128d51adac3e55f6b9d94f591a18d7579f900fac08e82e4b823c667ea2266eea` は配置配線・タイミング検査を通過した。ただし 2026-09-23 の実機ロードは2回とも FTDI の `usb bulk read failed` で失敗し、UART は0 byteだった。LCDサンプルへの復帰試行も同じUSBエラーで失敗したため、現在の表示状態は未確認である。記録は `logs/board/20260923-144812-DdrArrayScan-*`、`20260923-145051-DdrArrayScan-*`、`20260923-144916-LcdSoc-*`、`20260923-145150-LcdSoc-*` にある。USB/JTAG が復旧した後に測定を再開する。

USB 再接続後、同じ bitstream を3回ロードできた。いずれも定常フレームは `V00002956` で、期待パターンの通過マスクは両レーンで `00`、最後の DQ0/DQ8 生パターンは `29/56` だった。`RVALID` は両レーンで観測した。これだけでは、2列の値が同一か、異なる値を誤った位相で受信したか区別できない。記録は `logs/board/20260923-161749-DdrArrayScan-*`、`161836`、`161918` にある。3回とも LCD サンプル復元と UART 検査は通過した。

この区別のため走査版の後続フレームでは、`RR/SS` を DQ0/DQ8 の**2列変化マスク**に変更した。各 bit は同一候補・同一相対サイクルで両列に `RVALID` があり、観測した8 beat値が異なった場合だけ立つ。変化だけでは書込み値の正しさは証明できない。以前の生パターン版と bitstream SHA256 で識別する。

2列変化マスク版の反転データ bitstream は初回 SHA256 `128d51adac3e55f6b9d94f591a18d7579f900fac08e82e4b823c667ea2266eea` とは異なる。2026-09-23 の2回のロードでは `V0000FFFF` が繰り返された。先頭4桁 `0000` は期待する反転値への一致候補なし、末尾 `FFFF` は両レーンの全8候補で2列の生パターンが異なることを表す。ログは `logs/board/20260923-162415-DdrArrayScan-*` と `162503`。いずれもLCD復元は通過した。

対照試験 `TangDdrArraySameProbe` は両列に同じ `DATA_A` を書く。`DDR_ARRAY_SAME=1 bash scripts/build_ddr_mpr.sh` で構築し、`-Mode DdrArraySame` で測定する。`make ddr-array-same-test` は同一値の書込み、ゲート候補の一致、2列変化マスクが0であることを検証する。実機 bitstream SHA256 `7f9e363b0294c44a29d66e1ba3505150bd849e915a1a1b90eb23cc517dcf1047` の3回のロードでは、`V00000202`、`TFCFD0002`、`TFCFD0002` だった。2回目以降は期待する DQ0/DQ8 が多くの候補で一致したが、候補1では2列の観測値が異なり、対照試験の完全一致判定は不合格である。ログは `logs/board/20260923-162936-DdrArraySame-*`、`163015`、`163107`。各回とも LCD 復元は通過した。

現行 RTL で再構築した反転データ bitstream SHA256 `276d71af8ef69c803fa1d6c8e50f3ba27b5d3b7964e906ce4a1e67869227b620` も `V0000FFFF` となり、LCD 復元は通過した。ログは `logs/board/20260923-163222-DdrArrayScan-*`。同一値と反転値の比較は、書込み値の差が読出し値に反映されている可能性を示す。ただし、対照試験自体がロードごとに `V` と `T` に変動し、期待パターンへの安定した一致がないため、書込み経路や読出しデータアイの合格とは判定しない。

安定したゲート位置が見つかってから受信遅延を走査し、全 DQ bit、byte mask、アドレス alias、refresh を検証する。現段階の結果を Linux 用 RAM の設定には使用しない。

## 一次資料

- [Gowin DDR3 PHY Interface IP User Guide](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf): CWL=5 の WRITE と CL=6 の READ の CA slot 例。
- [Gowin FPGA Primitive](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf): DQS と OSER8_MEM/IDES8_MEM の信号定義。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 搭載 DDR3 の速度・タイミング仕様。
