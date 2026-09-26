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

`DdrArrayTrace` は走査を行った後、最後のゲート候補における column 0 の DQ0/DQ8 と column 8 の DQ0/DQ8 の4つの生パターンを UART に出す。反転データ bitstream SHA256 `e143d5a8043168a6f02c300366c0da02df427e357a8faee9a52a8e1d28e9e02f` を2回ロードすると、両回とも `V80404056` だった。最後の候補では column 0 が `80/40`、column 8 が `40/56` で、期待する `5A/A5`、`A5/5A` とは異なる。ログは `logs/board/20260923-164343-DdrArrayTrace-*`、`164421`。両回とも LCD 復元は通過した。この出力は最後の候補だけであり、他の候補の生パターンを示さない。

`DdrArrayMatch` は各候補で期待する DQ0/DQ8 が一致したかを、column 0 の2レーン、column 8 の2レーンの順に独立した4マスクで出す。`DDR_ARRAY_MATCH=1 bash scripts/build_ddr_mpr.sh` で構築し、`-Mode DdrArrayMatch` で測定する。bitstream SHA256 `47868936e02f5edb75a1e78dd79320360c1b4d76ff64e2e3f16e001377fc2822` の3回のロードでは `V00000000`、`V0000FEFF`、`V00000000` だった。2回目だけ column 8 で多数の一致候補を観測した。`FE/FF` は同一の候補で両レーンが一致したことや、column 0 との整合を示さない。ロード間で結果が変わるため、データアイまたは書込み位相の安定値は決められない。ログは `logs/board/20260923-164906-DdrArrayMatch-*`、`164957`、`165041`。初回のJTAGログには FTDI reset 警告があるが、bitstream ロード、UART取得、LCD復元は完了した。3回とも LCD 復元のUART検査は通過した。

次の切り分けには、DQS/DQ/CA の外部波形または FPGA 内部の送受信時刻を同じロード中に観測し、WRITE の CWL 位相と READ の RVALID/IDES8_MEM 出力の対応を確定する必要がある。現在のマスクを校正値に用いない。

外部測定器がないため、`DdrArrayFlags` は DQS primitive の `RFLAG`/`WFLAG` を controller clock で累積し、`RVALID` を観測した最初と最後の `RPOINT`、書込みバースト時の最後の `WPOINT` を UART で報告する。フレーム `SFFRRWWPP` で、`FF` の bit 0–1 が lane 0/1 の `RFLAG`、bit 2–3 が lane 0/1 の `WFLAG`、`RR` と `PP` はそれぞれ最後と最初の `RPOINT` を2レーン各3 bitで格納し、`WW` は最後の `WPOINT` である。`DDR_ARRAY_FLAGS=1 bash scripts/build_ddr_mpr.sh` で構築し、`-Mode DdrArrayFlags` で測定する。[Gowin FPGA Primitive User Guide](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf) は `RFLAG`/`WFLAG` を FIFO の under-flow/over-flow の margin flag と説明する。controller clock より短いパルスは本診断では捕捉できない。

bitstream SHA256 `963c6f7444c0a42a6675b1ae406ccfa360f905b2f5635c08cec91ecc15d2e513` の3回のロード結果は `V001B002D`、`V002D002D`、`V002D002D` だった。全回で観測した FIFO flag は0、最初の RPOINT は両レーンとも5。最後の RPOINT は初回のみ両レーンとも3で、残り2回は5だった。WPOINT の取得値は0。値の変動は FIFO pointer の状態差を示すが、正常な進行かデータ不一致の原因かは未確定である。ログは `logs/board/20260923-171818-DdrArrayFlags-*`、`171854`、`171930` にあり、各回の LCD サンプル復元と UART 検査は通過した。`RFLAG`/`WFLAG` が0であることから受信データの正しさは推定しない。

安定したゲート位置が見つかってから受信遅延を走査し、全 DQ bit、byte mask、アドレス alias、refresh を検証する。現段階の結果を Linux 用 RAM の設定には使用しない。

## 2026-09-26: 全幅での受信選択走査

`DdrArrayPhaseScan` はREADゲートを通常の位置に固定し、RCLKSEL=0–7を同一起動中に走査する。各候補で列0/8を読み、各laneの64 bit全体が両列で同じRVALID相対位置（直前・同時・直後）に一致した場合だけ合格マスクへ記録する。従来の `DdrArrayScan` はDQ0/DQ8とゲート位置を評価するモードとして維持する。

構築は `DDR_ARRAY_PHASE_SCAN=1 bash scripts/build_ddr_mpr.sh`、実機取得は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayPhaseScan`。UARTは `SMMNNCCDD` で、`MM`/`NN` がlane0/1の全幅合格位相マスク、`CC`/`DD` は同じRVALID相対cycleで列ごとのDQ0/DQ8が変化した位相マスクである。後半2 byteは全幅の正しさを示さない。実機スクリプトのpassedは完了フレーム取得を意味し、`T` 以外はDDR読出し合格ではない。

`make lint ddr-array-phase-scan-test ddr-array-gate-test ddr-array-same-test ddr-array-early-scan-test ddr-array-test` は通過した。新規試験は16 READの順序・固定ゲート・8選択値、レーンごとの異なる合格位相、古い列データとDQ7/DQ15の1 bit誤りの拒否を確認する。配置配線後のsetup/hold違反は0。

bitstream SHA256 `98f72456eedcd26d576fae6a4355f99876f8b6c816d6c539bf9ec49501aec612` の3回の実機結果は全て `V00000000`。ログは `logs/board/20260926-165320-DdrArrayPhaseScan-*`、`165349`、`165438`。各回のLCD SoC復帰とUART検査は通過した。いずれも全幅で使える受信選択は得られなかった。RCLKSEL単独の走査では解消しておらず、PHY起動とREAD時のクロック制御、DLLの位相条件も確認対象である。

## READごとのHOLD停止の比較

`DdrArrayContinuousScan` は全幅位相走査と同じ手順で `READ_HOLD=0` とし、READ指令時のDQS HOLDを無効にする。既定値1は従来動作を維持する。Gowin同梱 `prim_sim.v` のDQSモデルではHOLDが内部高速クロックを停止するため、その影響を比較する。`DDR_ARRAY_CONTINUOUS_SCAN=1 bash scripts/build_ddr_mpr.sh` と `-Mode DdrArrayContinuousScan` を使う。`make ddr-array-continuous-test` は全READでHOLDが0であることと、従来の指令順序・位相選択・全幅比較を検証する。lint、既定のphase/gate scan試験、配置配線（setup/hold違反0）は通過した。

bitstream SHA256 `aa913f89f1235bf67d75158f867879b4166c215b84208f7358ff6c07d10f7875` の初回試行 `20260926-165912` はFTDI USB reset失敗により書込み前に失敗した。LCD復帰は再試行で成功し、USB列挙も正常だった。その後 `logs/board/20260926-165954-DdrArrayContinuousScan-*`、`170021`、`170054` で順に `V00002802`、`V00002802`、`V0000A002` を取得した。全回LCD SoC復帰とUART検査を通過した。列ごとのDQ変化を観測したが、全幅合格マスクは両laneとも0であり、HOLD停止の除去だけでは読出しを安定化できていない。

## DLL 90度設定の比較

`DdrArrayQuarterScan` はHOLD無効の位相走査に `DLL_QUARTER=1` を設定する。これはDLLの `SCAL_EN="false"` を選ぶ比較であり、既定の `SCAL_EN="true", CODESCAL="101"` は維持する。Gowin Primitive仕様のDLL属性表では前者が90°、後者が68°である。書込みと読出しの両方がDLLSTEPを使用するため、受信側だけの変更ではない。`DDR_ARRAY_QUARTER_SCAN=1 bash scripts/build_ddr_mpr.sh` と `-Mode DdrArrayQuarterScan` を使う。

Veryl lintと配置配線（setup/hold違反0）を通過したbitstream SHA256 `2e3f655306b59f18600243ac53eeaef1f8100791afc1321c46c54f193176774e` を3回ロードした。`logs/board/20260926-170258-DdrArrayQuarterScan-*`、`170325`、`170413` の結果は `V0000A00A`、`V0000A00A`、`V0000A80A`。列ごとの変化はあるが全幅合格候補は0。各回のLCD SoC復帰・UART検査は通過した。DLL設定の変更だけでは安定化していない。

## 位相とbeat位置の組合せ探索

`DdrArrayAlignedScan` はHOLD無効・90度DLL・全8 RCLKSEL走査の各READで、隣接cycleの全幅beat整列も同時に評価する。レーンごとに、現在または直前のRVALIDが立つ窓で一致した開始位置を蓄積し、両列の位置マスクの共通部分がある場合だけ合格とする。UARTの最初の2 byteはこの基準の位相マスクである。同じRVALID相対cycleまで保証するものではなく、運用時の読出しlatencyや補正値を確定する試験ではない。

`DDR_ARRAY_ALIGNED_SCAN=1 bash scripts/build_ddr_mpr.sh` と `-Mode DdrArrayAlignedScan` を使う。`DdrBurstAlignment` はtimelineとarrayで共有する独立Verylモジュールへ移した。`make ddr-array-aligned-scan-test` は2 beatずれた2 word、隠れた1 bit誤り、古い列値を検証し、列ごとに異なるbeat位置で一致する場合は拒否する。lint、continuous/phase/gate/same/early-scan/array/alignment/expected-timelineの回帰試験も通過した。配置配線後のsetup/hold違反は0。

bitstream SHA256 `4bd52c906207c636f9df915b4e26ccd730806efefcb32a0fde197249e1ea5015` の実機結果は3回とも `V00002828`。ログは `logs/board/20260926-170809-DdrArrayAlignedScan-*`、`170836`、`170933`。初回FTDI初期化の再試行後、全回で記録取得とLCD復帰・UART検査を通過した。組合せ探索でも合格候補はないため、これを校正済みPHYとして扱わない。次の確認対象はPHY起動時のDLL/高速クロック/分周器の制御順序である。

## 一次資料

- [Gowin DDR3 PHY Interface IP User Guide](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf): CWL=5 の WRITE と CL=6 の READ の CA slot 例。
- [Gowin FPGA Primitive](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf): DQS と OSER8_MEM/IDES8_MEM の信号定義。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 搭載 DDR3 の速度・タイミング仕様。
