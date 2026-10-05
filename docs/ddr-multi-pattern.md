# 複数pattern・bank/rowのDDR診断

`DdrArrayMulti` は起動時の拍位置trainingを1回行い、その結果を保持したまま8組のbank/rowで2列ずつ書込み・読戻しする。組合せは `(bank,row)=(0,0)..(7,7)`、列は0と8。最初の組だけ既知training patternを使い、以後は32 bitのseedを更新し、回転と反転で128 bitへ展開する。各組の列8は列0の全bit反転である。

各組の全幅一致を検査し、一度でも不一致やvalid欠落があれば失敗を保持する。後続の成功で消去しない。各組の終了時にall-bank PRECHARGEを発行し、tRP待機後に次のACTIVATEへ進む。既定の単発診断とscan診断の動作は変更しない。

```bash
make ddr-multi-array-test ddr-trained-array-test ddr-array-test ddr-array-aligned-scan-test
DDR_ARRAY_MULTI=1 bash scripts/build_ddr_mpr.sh
```

実機には `scripts/test-ddr-init-board.ps1 -Mode DdrArrayMulti` を用いる。合格には通常のarray診断と同じUART status `A` が必要である。

結合試験では生成されたWRITE dataをモデルへ保存して読み戻し、bank/row/column、patternの更新と反転、16 WRITE/16 READ、全組でtraining位置を保持することを検証する。初回の古い列データ、不正training、中間組のbit反転、中間組のvalid欠落を注入し、最終組が成功しても合格しないことを確認する。

この試験は短い8組で終了する。refresh保持、byte mask、全アドレスbit、全組を書いた後の再照合は含まない。特にbank/rowを一組ずつ書いて直後に読むため、異なる組同士のaliasをこの結果から否定できない。

2026-09-26、lint、上記4試験、配置配線（setup/hold違反0）を通過した。bitstream SHA256 `079a10f2073b5f230954be1e60e35fe914fb74a0f7a8abeb225031d5d773b76a` の実機3回はいずれも `A95A56AA5` で全組合格。全回LCD SoC復帰・UART検査も通過した。

実機ログは logs/board/20260926-180818-DdrArrayMulti-*、180906、180944。

## 全書込み後の再照合とalias検出

`DdrArrayRetain` は8組への書込みと直後の読戻しを終えた後、書込みを行わずに全組を再読出しする。trainingで決めた拍位置は両passで保持する。最終判定には全32 READの一致が必要であり、途中の失敗は保持する。

bankとrowを独立に検査できるよう、組合せを次へ変更する。各組の列は0と8である。

| 組 | bank | row |
| ---: | ---: | ---: |
| 0 | 0 | 0 |
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 4 | 0 |
| 4 | 0 | 1 |
| 5 | 0 | 2 |
| 6 | 0 | 4 |
| 7 | 0 | 8 |

```bash
make ddr-retain-array-test
DDR_ARRAY_RETAIN=1 bash scripts/build_ddr_mpr.sh
```

実機測定は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayRetain` を使う。合格にはUART status `A` が必要である。試験は正常、古い列データ、不正training、中間組のbit反転、valid欠落、bank alias、row aliasの7ケースを含む。aliasケースは直後の読戻しでは成功し、全書込み後の再読出しで失敗することも確認する。

診断は16 WRITE/32 READ、681 controller cycle（99 MHzで約6.88 µs）で終了する。短時間の再照合であり、refresh保持試験ではない。検査対象は上記の疎なアドレス集合に限られ、全row/column bitや全容量の健全性を保証しない。

2026-10-05、lintと7ケースの結合試験、配置配線（setup/hold違反0）を通過した。bitstream SHA256は `82c280478ba265e587bf8c454acc9b83298df96a36c26b1e151d5b6f4872ae62`。実機では独立した3回の書込みで全32 READが一致し、UART statusは全回 `A95A56AA5` となった。全回LCD SoCへの復帰とUART検査も通過した。ログは `sim/retain-alias-test.log`、構築結果は `sim/fpga/ddr_array_retain/` にある。

実機ログは logs/board/20261005-145629-DdrArrayRetain-*、145910、145956。既存のmulti/trained/array/aligned-scan回帰試験も通過した（sim/retain-regression.log）。
