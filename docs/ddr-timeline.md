# Tang Primer 20K DDR3 読出しタイムライン

`DdrArrayTimeline` は最初の array READ 指令から 32 controller cycle を記録する。各 cycle の 32 bit word は上位から `gate[1], RBURST[2], RVALID[2], reserved[3], DQ1[8], DQ0[8], DQ8[8]` である。DQ の各 byte は 8 beat のサンプルを bit 7 から bit 0 に並べる。記録終了後に UART で `@`、256 桁の大文字 hex、LF を一度送る。`scripts/decode-ddr-timeline.py <uart.bin>` で cycle ごとの値を表示できる。

RTL は Veryl、テストベンチは SystemVerilog。`make ddr-timeline-test` は 32 cycle の順序と UART 全フレームを検証する。固定済み Gowin 環境では `DDR_ARRAY_TIMELINE=1 bash scripts/build_ddr_mpr.sh` で構築し、`scripts/test-ddr-init-board.ps1 -Mode DdrArrayTimeline` で実機測定後に LCD SoC を再ロードする。タイミング制約は setup/hold とも違反 0 を要求する。

2026-09-23 に bitstream SHA256 `5b1b2ece52481c6b567e9fdf5c16d3caa401d635765ebebf092431781c51d44e` を実機で3回ロードした。最初の取得 `logs/board/20260923-173533-DdrArrayTimeline-uart.bin` と、取得スクリプト修正後の `173804`、`173856` は完全なフレームを含む。途中の `173640`、`173717` は書込み完了後に UART バッファを破棄したため先頭64 byte が欠けた。試験スクリプトはこのモードで書込み中から受信した byte を保持するよう修正した。各回の LCD SoC 復帰検査は通過した。

| 記録 | 第1 READ gate | 第1 `RVALID=3` | 同 cycle の DQ1/DQ0/DQ8 | 第2 READ gate | 第2 `RVALID=3` | 同 cycle の DQ1/DQ0/DQ8 |
| --- | ---: | ---: | --- | ---: | ---: | --- |
| 173533 | 2 | 7 | `5A/6A/95` | 15 | 20 | `A5/95/6A` |
| 173804 | 2 | 8 | `05/06/29` | 15 | 21 | `0A/09/16` |
| 173856 | 2 | 8 | `16/1A/A5` | 15 | 21 | `29/25/5A` |

`RVALID` が立つ cycle はロード間で 1 cycle 変わり、DQ のパターンも安定しない。DQ0 と DQ1 は同一 byte lane 内でも異なる値を示す。READ 前後には `AA/55` 等のパターンが出るが、`RVALID=0` の値を RAM 読出し成功とは判定しない。現時点で DDR3 の安定した読書きは未確認であり、Linux 用 RAM としては使わない。WRITE 側の送出時刻または READ 側の DQS/サンプリング位置のどちらに問題があるかは、この記録のみでは特定できない。
