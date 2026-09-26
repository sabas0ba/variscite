# DDR全幅読出しデータの記録

`DdrRawBurstCapture` は2回のREADそれぞれについて、最初のlane RVALIDを含む前後3 controller cycleの128 bitを保存する。既存の `DdrTimelineUart` により `@`、32個の32 bit hex word、LFを送る。両列の記録が揃った後はメモリを変更しない。先行列の応答がない場合は完了を通知しない。

各列の16 wordは次の構成とする。

| 相対word | 内容 |
| --- | --- |
| 0–3 | RVALID直前の128 bit、下位32 bitから |
| 4–7 | 最初にいずれかのlane RVALIDが立ったcycleの128 bit |
| 8–11 | 直後の128 bit |
| 12–14 | 各cycleの `{19'b0, elapsed[7:0], gate, burst[1:0], valid[1:0]}` |
| 15 | 予約、0 |

elapsedはREADからの経過controller cycleで、255で飽和する。lane間のRVALIDの差が大きい場合は、後着laneの全データが3 cycleに収まる保証はない。UART frameの受信成功はDDRデータ一致を意味しない。

`DdrArrayRawBurst` は明示的PHY起動、DLL 90度、RCLKSEL 4/4、READごとのHOLDなしで2列を読み出す。`DdrArrayRawScaled` はDLLをCODESCAL=101の約68度へ変更する。DLL変更は読出し側だけでなく書込み側の位相にも影響するため、この比較だけで故障を読出し/書込みの片側へ限定しない。

```bash
DDR_ARRAY_RAW_BURST=1 bash scripts/build_ddr_mpr.sh
DDR_ARRAY_RAW_SCALED=1 bash scripts/build_ddr_mpr.sh
make ddr-raw-burst-test
python3 scripts/decode-ddr-raw-burst.py logs/board/<capture>-uart.bin
```

実機測定には `scripts/test-ddr-init-board.ps1 -Mode DdrArrayRawBurst` または `DdrArrayRawScaled` を用いる。各回の測定後はLCD SoCへ復帰してUART検査する。

試験は全32 wordのデータ/付随情報、READ前の余分なRVALID、両列完了までの待機、完了後の書換え禁止、reset、先行列の欠落を検証する。

2026-09-26、90度版はlint、単体試験、配置配線（setup/hold違反0）を通過した。bitstream SHA256 `e49c2a3f9c68c6ef8dd1aee4c4c7b13038ed0e4dd6bdb75cf0384fb903983d1a`、ログ `20260926-173932-DdrArrayRawBurst-*`、`174017` は同じ全幅データを得た。2回目はFTDI初期化の再試行後に成功した。LCD復帰は両回成功した。

| 列 | 期待値（beat 0から） | RVALID時の実測 |
| --- | --- | --- |
| 0 | 0FF0 F00F 6996 9669 3CC3 C33C 5AA5 A55A | 0FF0 6816 6996 3C43 3CC3 5A25 5AA5 A55A |
| 8 | F00F 0FF0 9669 6996 C33C 3CC3 A55A 5AA5 | F00F 96E9 9669 C33C C33C A5DA A55A 5AA5 |

両列とも偶数beatは一致し、beat 1/3/5は不一致、beat 7は一致する。3 cycle内の全lane 64 bitの連続一致はない。単純なbeat位置補正では解消せず、位相依存を調べる。

68度版は配置配線（setup/hold違反0）を通過し、bitstream SHA256 `71ce32b393f7e045e8237afc3c9e46a24faa4ce06429edab5255ae9a432ddb28` の独立した3回の書込み・測定で、両列・両laneがoffset 6で全幅一致した。ログは `20260926-174240-DdrArrayRawScaled-*`、`174316`、`174406`。3回目はFTDI初期化の再試行後に成功した。全回LCD SoC復帰・UART検査は成功した。

RVALIDはREAD後8 controller cycleで両lane同時。前cycleの末尾2 beatとRVALID cycleの先頭6 beatを結合すると期待値になる。これは2列・固定pattern・短時間の診断であり、任意アドレスや長時間のメモリ健全性、Linux起動を確認したものではない。また別bitstream間の比較には配置配線差も含まれる。次は内容に依存しない固定offsetの組立回路と、追加patternを使う反復試験で確認する。
