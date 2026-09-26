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
