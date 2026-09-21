# Tang Primer 20K DDR3 読出し DQS ゲート検証

対象は基板上の SK hynix H5TQ1G63EFR-PBC (x16, 128 MiB) である。Linux 起動に必要な DDR3 読み書き検証のうち、ここでは READ に対する DQS バースト検出だけを扱う。

`DdrReadGateSweep` は JEDEC 初期化完了後に bank 0 / row 0 を ACT し、各バイトレーンの DQS 受信選択位相と READ ゲート位置を 32 通り走査する。READ 間隔は 13 個の 99 MHz コントローラクロックで、全走査は 430 クロック未満である。最後に PRE を発行し、診断が終わると DRAM RESET をアサートする。`RBURST` を観測したレーンを独立して記録する。`G` は両レーンを検出したこと、`E` は少なくとも一方が未検出であることを UART に繰り返し送る。どちらもデータ値の正しさを示さない。

RTL は Veryl の `fpga/tang_primer_20k/ddr_read_gate_sweep.veryl` と `ddr_read_probe.veryl` に置く。SystemVerilog はテストベンチだけに使用する。`make ddr-read-gate-test` は別々のレーン位相、32 通りのタイムアウト、enable 喪失、ACT/READ/PRE の順序を確認する。`scripts/build_ddr_read.sh` は固定済み Gowin コンテナで合成と配置配線を行い、DDR ピン、PLL/DLL/DQS 個数、クロック周期、内部セットアップ・ホールドを検査する。DQS プリミティブの HOLD 入力には内部の高速クロック同期段があるため、この 2 ピンだけを STA のコントローラクロック起点の経路から除外する。外部 DDR3 の入出力タイミングは別途測定を要する。

2026-09-21、`ddr_read.fs` SHA256 `8c8d9d5eadb15c19edeaaeab0ef928c1d32395fa59d2102d66644b546eb0f298` を接続中の Tang Primer 20K に SRAM ロードした。COM4 / 115200 baud の 4 秒取得で、直前の LCD デモから残った出力の末尾に `P` と `G` の連続を確認した。2 回目の自動判定は合格した。生ログと判定 JSON は `logs/board/20260921-170427-DdrRead-*` にある。試験後、既知の LCD デモ SHA256 `40bac365ce8f971d240ac5aa6a2e4c69c1fff5579c6dbbb2afe4f97662b9eb0a` を復帰させ、UART 動作判定が通った。

CL=6/AL=0 の診断コマンドを serializer slot 2 に配置した再試験でも、
SHA256 `5994f6c407814272765311a7ed795d730f26f873af5248864a719465e910befe`
で `G` と LCD 復元を確認した。ログは `logs/board/20260921-230233-DdrRead-*`。
このスロットは [Gowin DDR3 PHY Interface IP User Guide の READ タイミング例](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf)
を参考にした。カスタム PHY での最適スロットを証明するものではない。

再試験には、まず固定済み Gowin コンテナで `bash scripts/build_ddr_read.sh` を実行し、Windows ホストで以下を実行する。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-ddr-init-board.ps1 `
  -Suite C:/Users/sabas/repos/hello_veryl/tools/oss-cad-suite -Port COM4 -Mode DdrRead
```

次段階は、受信した DQ のデータアイ調整、書込みタイミング調整、書込み読戻しとアドレス alias、refresh 保持試験である。現時点では DDR3 を Linux の RAM として利用できない。

アレイ書込み・読戻し診断で使うゲート設定を観測できるよう、UART を `SLLUU` の 5 文字フレームに変更した。`S` は従来の状態、`LL` と `UU` はそれぞれ lane 0/1 で最初に `RBURST` を検出した 6-bit phase の 16 進数表示である。`G` は DQS の検出のみを示し、DQ データの正しさは示さない。

2026-09-22 の再試験では bitstream SHA256 `5ba918eae8267a6e88e5ac4b88b3daff4c7b90d0934bebe48adcb435f42a069f` を同一基板へ 4 回ロードした。定常フレームは順に `G0004`、`G0004`、`G0004`、`G0000` だった。lane 0 の最初の検出 phase は `00`、lane 1 は `04` または `00` で、再ロード間に変動した。4 回とも診断 UART と LCD サンプル復元の判定は通過した。生ログは `logs/board/20260922-005556-DdrRead-*`、`005613`、`005642`、`005659` にある。この phase は `RBURST` の最初の検出位置であり、データアイや DRAM アレイ読出しの合格位置ではない。
