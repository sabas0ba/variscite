# Tang Primer 20K DDR3 読出しタイムライン

`DdrArrayTimeline` は最初の array READ 指令から 32 controller cycle を記録する。各 cycle の 32 bit word は上位から `gate[1], RBURST[2], RVALID[2], reserved[3], DQ1[8], DQ0[8], DQ8[8]` である。DQ の各 byte は 8 beat のサンプルを bit 7 から bit 0 に並べる。記録終了後に UART で `@`、256 桁の大文字 hex、LF を一度送る。`scripts/decode-ddr-timeline.py <uart.bin>` で cycle ごとの値を表示できる。

RTL は Veryl、テストベンチは SystemVerilog。`make ddr-timeline-test` は 32 cycle の順序と UART 全フレームを検証する。固定済み Gowin 環境では `DDR_ARRAY_TIMELINE=1 bash scripts/build_ddr_mpr.sh` で構築し、`scripts/test-ddr-init-board.ps1 -Mode DdrArrayTimeline` で実機測定後に LCD SoC を再ロードする。タイミング制約は setup/hold とも違反 0 を要求する。

2026-09-23 に bitstream SHA256 `5b1b2ece52481c6b567e9fdf5c16d3caa401d635765ebebf092431781c51d44e` を実機で3回ロードした。最初の取得 `logs/board/20260923-173533-DdrArrayTimeline-uart.bin` と、取得スクリプト修正後の `173804`、`173856` は完全なフレームを含む。途中の `173640`、`173717` は書込み完了後に UART バッファを破棄したため先頭64 byte が欠けた。試験スクリプトはこのモードで書込み中から受信した byte を保持するよう修正した。各回の LCD SoC 復帰検査は通過した。

| 記録 | 第1 READ gate | 第1 `RVALID=3` | 同 cycle の DQ1/DQ0/DQ8 | 第2 READ gate | 第2 `RVALID=3` | 同 cycle の DQ1/DQ0/DQ8 |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| 173533 | 2 | 7 | `5A/6A/95` | 15 | 20 | `A5/95/6A` |
| 173804 | 2 | 8 | `05/06/29` | 15 | 21 | `0A/09/16` |
| 173856 | 2 | 8 | `16/1A/A5` | 15 | 21 | `29/25/5A` |

`DATA_A` を書いた第1列の期待値は DQ1/DQ0/DQ8=`96/5A/A5`、その反転値 `DATA_B` を書いた第2列は `69/A5/5A` である。`RVALID` が立つ cycle はロード間で 1 cycle 変わり、その cycle のDQは3回とも期待値に一致しない。READ 前後には `AA/55` 等のパターンが出るが、`RVALID=0` の値を RAM 読出し成功とは判定しない。現時点で DDR3 の安定した読書きは未確認であり、Linux 用 RAM としては使わない。WRITE 側の送出時刻または READ 側の DQS/サンプリング位置のどちらに問題があるかは、この記録のみでは特定できない。

## 全0/全1の書込みと早期READゲート

複雑なビットパターンとの比較のため、列0へ全0、列8へ全1を書き込む `DdrArraySimpleTimeline` を追加した。`DDR_ARRAY_SIMPLE_TIMELINE=1 bash scripts/build_ddr_mpr.sh` で構築し、`scripts/test-ddr-init-board.ps1 -Mode DdrArraySimpleTimeline` で測定する。bitstream SHA256 は `688f7370b1b107de362da12493f1673b25aceda9efeb29a0584e60e0e9d23465`。`logs/board/20260923-220334-DdrArraySimpleTimeline-*`、`221210`、`222750` の3回とも、列0の `RVALID=3` がcycle 8でDQ1/DQ0/DQ8=`00/00/00`、列8の直前cycle 20で`FF/FF/FF`だった。ただし列8の `RVALID=3` が立つcycle 21では最初の2回が`0F/0F/3F`、3回目が`03/03/0F`であり、全1が有効サイクルに揃わない。記録した3 bitだけで全128 bitの一致は判定できない。

比較用の `DdrArrayEarlyTimeline` は、同じ書込み内容でREADゲートだけを1 controller cycle早める。`DDR_ARRAY_EARLY_TIMELINE=1 bash scripts/build_ddr_mpr.sh` と `-Mode DdrArrayEarlyTimeline` を使う。bitstream SHA256 は `688386cba015395c1334f17cefab46e2495392396b2a9fef4e83bf1f65d1fdb7`。`logs/board/20260923-231844-DdrArrayEarlyTimeline-*` と `232048` の2回は同一の32 cycle記録だった。ゲートはcycle 2から1へ移ったが、`RBURST`は全cycleで0となり、列0/列8の `RVALID=3` はそれぞれcycle 10–12と23–25で3 cycle連続した。有効サイクルで列8の全1は得られない。早期ゲートは今回の安定した受信位置ではない。途中のFTDIリセット失敗2回では診断bitstreamをロードできなかったため測定に含めない。成功した各測定後のLCD SoC復帰検査は通過した。

`make lint ddr-array-test ddr-array-simple-test ddr-array-early-test ddr-array-gate-test ddr-array-early-scan-test ddr-array-same-test ddr-timeline-test` と、2つのbitstreamの配置配線・setup/hold検証は通過した。次は128 bit全体の一致をREADの各cycleで確認し、WRITEがDRAMに保持されたかと `RVALID` のずれを分離する必要がある。

## 全128 bitの一致フラグ

`DdrArrayFullTimeline` は全0/全1の書込みと通常ゲートを使い、UART wordの既存reserved 3 bitを上位から `all_zero`、`lane0_all_one`、`lane1_all_one` に置き換える。`all_zero` は全128 bitが0の場合だけ1、各laneの `all_one` はそのlaneの64 bitがすべて1の場合だけ1である。両laneの `all_one` が1なら全128 bitが1となる。フラグとDQパターンは同じcontroller cycleから記録する。期待値比較を有効にしない他のtimelineモードではこの3 bitを引き続き0に固定する。

`DDR_ARRAY_FULL_TIMELINE=1 bash scripts/build_ddr_mpr.sh` と `scripts/test-ddr-init-board.ps1 -Mode DdrArrayFullTimeline` を使う。デコーダは `zero`、`one0`、`one1` 列にフラグを表示する。旧モードの0は判定無効を意味するので、旧bitstreamのログから全幅不一致を推定しない。`make ddr-full-timeline-test` は全0、全1、片laneだけの全1、DQ15またはDQ0の1bit不一致をUARTフレーム全体で検証する。

2026-09-26にVeryl lint、既存timeline試験、新しい全幅試験、配置配線・setup/hold検証を通過した。bitstream SHA256は `4af9977423d16f86b7b61a2dd91a70e36603a98d7061195377c018fe7ddb8121`。初回実機試行はJTAG検出時の `usb bulk read failed` により書込み前に失敗し、その後のLCD SoC復帰試行もJTAG検出時に失敗した。ログは `logs/board/20260926-110359-DdrArrayFullTimeline-*` と同試行のLCD SoCログに保存した。WindowsはFTDIとCOM4を認識しているが、全幅の実機データは未取得である。

USB再接続後の再試行 `logs/board/20260926-112659-DdrArrayFullTimeline-*` は `device not found` で書込み前に失敗した。その時点のWindows接続済み機器一覧にはFTDIが存在せず、JTAG用USBと電源の確認待ちとなった。この試行のLCD SoC復帰検出も失敗しており、実機データと現在のLCD表示は未確認である。

利用者によるケーブル・接続ポート・電源の変更後、FTDI、JTAG Debugger、COM4の列挙が復旧した。Zadigによるドライバ変更は行っていない。同じ全幅診断bitstreamを3回ロードし、`logs/board/20260926-114150-DdrArrayFullTimeline-*`、`120035`、`120732` に完全なUART記録を取得した。各回のLCD SoC復帰とUART検査も通過した。

| 記録 | 列0の `RVALID=3` cycle | その時点の全128 bit零一致 | 列8の `RVALID=3` cycle | その時点のlane0/lane1全1一致 |
| --- | ---: | --- | ---: | --- |
| 114150 | 8 | 1 | 21 | 0/1 |
| 120035 | 7 | 1 | 20 | 1/1 |
| 120732 | 7 | 1 | 20 | 1/1 |

列8のcycle 20では3回とも両laneの全1一致が得られた。初回だけ `RVALID` がcycle 21へ遅れ、その時点ではlane0のDQ1/DQ0が`3F/3F`に変化していた。後の2回は全32 cycle記録が同じだった。全幅の全0/全1パターンを観測できたが、有効位置がロード間で変わり、列0の全0はアイドル値とも一致するため、これだけで安定したDDR3 RAM動作とは判定しない。複雑なパターンと反復読書き、起動時の受信位置校正が引き続き必要である。

## 複雑な書込みパターンとの全幅比較

`DdrArrayExpectedTimeline` は通常の `DATA_A` / `DATA_B` を列0 / 列8へ書き込み、reserved 3 bitを `all_match`、`lane0_match`、`lane1_match` に置き換える。期待値は `DdrArrayProbe` の出力を使い、各READ指令から対応するサンプル状態の終了まで列の値を選ぶ。lane0は各16 bit beatの下位8 bit、lane1は上位8 bitであり、それぞれ64 bit全体を比較する。一致フラグは `RVALID` と独立して記録するため、読出し成功の判定では有効フラグも確認する。

構築は `DDR_ARRAY_EXPECTED_TIMELINE=1 bash scripts/build_ddr_mpr.sh`、実機取得は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayExpectedTimeline`、デコードは `scripts/decode-ddr-timeline.py --expected <uart.bin>` を使う。`make ddr-expected-timeline-test` は2つの複雑な期待値、片laneの1 bit不一致、lane全体の不一致、別列の古い値、記録後の入力変更を検証する。既存array試験もREADゲート時の期待値選択を検証する。CIのFPGA試験へ新規試験を追加した。

2026-09-26に `make lint ddr-expected-timeline-test ddr-timeline-test ddr-full-timeline-test ddr-array-test ddr-array-simple-test ddr-array-early-test ddr-array-gate-test ddr-array-early-scan-test ddr-array-same-test` と配置配線を通過した。setup/hold違反は0。bitstream SHA256は `87887198f1d5e0305a460d485873f8b0d3c20cc2a6f6eefc9b4dc2ea18547fa7`。

| 記録 | 列0の `RVALID=3` cycle | 全幅/lane0/lane1一致 | DQ1/DQ0/DQ8 | 列8の `RVALID=3` cycle | 全幅/lane0/lane1一致 | DQ1/DQ0/DQ8 |
| --- | ---: | --- | --- | ---: | --- | --- |
| 160540 | 7 | 0/0/0 | `5A/6A/95` | 20 | 0/0/0 | `A5/95/6A` |
| 160616 | 8 | 0/0/1 | `16/1A/A5` | 21 | 0/0/1 | `29/25/5A` |
| 160651 | 7 | 0/0/0 | `5A/6A/95` | 20 | 0/0/0 | `A5/95/6A` |

ログは `logs/board/20260926-160540-DdrArrayExpectedTimeline-*`、`160616`、`160651`。初回のFTDI初期化は一度失敗したが、スクリプトの再試行でロードできた。3回とも完全なUARTフレームを取得し、測定後の既知LCD SoC復帰とUART検査も通過した。初回と3回目の32 wordは同一だった。

全32 cycleで全幅一致とlane0一致は一度も得られない。一方、2回目は異なる2列の複雑なパターンがlane1の64 bit全体で有効cycleに一致した。この観測はlane1の書込み・保持・読出し経路が少なくともこの条件で機能することを支持するが、安定動作やlane0の故障原因までは確定しない。有効位置の起動間変動が残るため、次はレーンごとのDQS捕捉位置・beat整列・有効判定とWRITE送出の確認を行う。Linux用RAMとして使える段階には達していない。

## 両レーンのRCLKSELを4にした比較

`DdrArrayProbe.READ_SEL` と親の `ARRAY_READ_SEL` で各laneのRCLKSELを指定できるようにした。下位3 bitがlane0、上位3 bitがlane1で、既定値 `6'h20` は従来の0/4を維持する。新しい `DdrArrayPhaseTimeline` は `6'h24`、すなわち4/4を使う。論理上の変更はlane0のRCLKSELのみで、書込みパターン、コマンド時刻、READゲート時刻、期待値比較は前節と同じである。別の配置配線結果となるため、実機差をRCLKSELだけの効果と断定しない。

[Gowin FPGA Primitive User Guide のDQS仕様](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf) はRCLKSELを読出しクロック源と極性の制御と定義する。この比較は手動の候補評価であり、起動時校正を実装したものではない。

構築は `DDR_ARRAY_PHASE_TIMELINE=1 bash scripts/build_ddr_mpr.sh`、実機取得は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayPhaseTimeline` を使う。デコードは前節と同じ `--expected` を指定する。`make ddr-array-phase-test` は変更した選択値でコマンド時刻、2パターン、古い値の拒否を検証する。Veryl lint、同試験、既定値のarray試験、gate scan試験、expected timeline試験は通過した。配置配線後のsetup/hold違反は0。bitstream SHA256は `e27aeb17c6d66f54f3a2d7b9d9eddae48449ae166662c76438a29fa96833d2ba`。

2026-09-26の3回の実機取得結果は以下のとおり。全回でUART全フレームと測定後のLCD SoC復帰・UART検査を通過した。

| 記録 | 列0の `RVALID=3` cycle | 全幅/lane0/lane1一致 | DQ1/DQ0/DQ8 | 列8の `RVALID=3` cycle | 全幅/lane0/lane1一致 | DQ1/DQ0/DQ8 |
| --- | ---: | --- | --- | ---: | --- | --- |
| 162624 | 8 | 0/0/0 | `25/16/29` | 21 | 0/0/0 | `1A/29/16` |
| 162702 | 8 | 1/1/1 | `96/5A/A5` | 21 | 1/1/1 | `69/A5/5A` |
| 162757 | 7 | 0/0/0 | `5A/6A/95` | 20 | 0/0/0 | `A5/95/6A` |

ログは `logs/board/20260926-162624-DdrArrayPhaseTimeline-*`、`162702`、`162757`。2回目で異なる2列の複雑なパターンが全128 bitで有効cycleに一致した。一方、残り2回では全32 cycleでどちらのlaneも一致しないため、この固定設定を安定動作の校正値として採用しない。

3回目の列0ではcycle 7と8のDQ1が`5A/02`、DQ0が`6A/01`、DQ8が`95/02`だった。連続する2 cycleを後の値が上位になるよう連結して2 bit右へ移動すると、それぞれ期待値`96/5A/A5`を得る。列8でも同じ操作で`69/A5/5A`となる。この3本の観測はデータがcontroller cycle境界をまたぐbeat整列の問題を示唆するが、未記録のDQを含む全幅の補正可能性は未確認である。次は連続cycleの全128 bitを使ったレーン別の整列診断と、再起動後も成立する校正を検証する。refresh、アドレスalias、長時間反復試験、Linux実機bootは未達である。

## 隣接cycleの全幅整列診断

`DdrBurstAlignment` は直前・現在の128 bit wordをレーンごとに分離し、連続する16 beatのうち開始位置0–7から8 beatを取り出して期待する64 bitと照合する。結果はレーンごとに8 bitの一致位置マスクとなる。これは観測回路であり、受信データの補正や合格位置の自動選択は行わない。

`DdrArrayAlignTimeline` は4/4の受信選択を使い、32 bit記録を `{gate, burst[1:0], valid[1:0], direct_match[2:0], reserved[5:0], previous_valid[1:0], lane1_offsets[7:0], lane0_offsets[7:0]}` とする。bit nは直前cycleのbeat nを先頭にした一致を表す。現在cycleそのものの一致は従来の `direct_match` に残す。`DDR_ARRAY_ALIGN_TIMELINE=1 bash scripts/build_ddr_mpr.sh`、`-Mode DdrArrayAlignTimeline`、デコーダの `--alignment` を使用する。

`make ddr-alignment-test` は両列のパターン、全8位置、異なるレーン位置、観測DQ0/DQ8以外の1 bit誤り、別列の古い値、reset、保存した前回/今回validを検証する。Veryl lint、同試験と既存のexpected/full/UART timeline試験は通過した。配置配線後のsetup/hold違反は0。

bitstream SHA256 `ad0072c2b33673fae87e8323ede320b4bd6cbdf95961eae9c1512d1118dcc101` を2026-09-26に3回ロードした。`logs/board/20260926-164758-DdrArrayAlignTimeline-*`、`164830`、`164903` の全32 cycleで直接一致・整列一致は全て0だった。初回と3回目は両レーンのvalidがcycle 8/21に立った。2回目はlane0が8/21、lane1が10–12/23–25に立ち、RBURSTはlane0のみだった。初回FTDI初期化の再試行を経て3回とも記録を取得し、LCD SoC復帰・UART検査も通過した。

このbitstreamで単純な隣接cycleの並べ替えによる回復は得られていない。前節の成功bitstreamと配置配線が異なるため、以前の成功・不一致データに対する全幅の再構成可否をこの結果だけで断定しない。受信バースト検出自体の起動間変動もあり、固定RCLKSELの候補評価を同一起動中の走査へ進める。
