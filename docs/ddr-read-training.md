# DDR読出しの拍位置決定と組立

`DdrReadAssembler` はlaneごとに保存したoffsetから8 byteを選び、元のx16 beat順へ戻す。
静的設定では前cycle/current cycleの16 byteとoffset 0〜8を使う。
動的training設定では3 wordの24 byteとoffset 0〜16を使い、RVALIDの次cycleにまたがる
patternも組み立てる。各laneは入力validで更新し、出力validは1 cycle遅延する。
期待値との比較はこの回路には含めない。

`DdrArrayAssembled` は両laneをoffset 6に固定する比較用診断である。明示的PHY起動、DLL約68度、RCLKSEL 4/4、READ時HOLDなしを使用する。構築は `DDR_ARRAY_ASSEMBLED=1 bash scripts/build_ddr_mpr.sh`。

固定offset版はlint、単体試験、配置配線（setup/hold違反0）を通過したが、bitstream SHA256 `3e9d32e919696d4411b432c560a0f4f04008d4c3936fce3c5454fedc3b821cfc` の実機2回は `V6A95956A` で不合格となった。ログは `20260926-174919-DdrArrayAssembled-*`、`175034`。両回LCD SoC復帰・UART検査は成功した。

[全幅記録版](ddr-raw-burst.md) の同一bitstreamではoffset 6が3回再現したが、別回路の配置配線結果へそのまま適用できなかった。これらの比較だけで変動原因を配置配線と断定はしない。固定値の変更を繰り返す代わりに、起動時のtrainingを追加する。

`DdrReadTraining` はREAD列0の期間だけtrainingを許可する。各laneの最初のRVALIDを
受理した次cycleに、前・当該・次cycleの3 wordで64 bitの既知patternをoffset 0〜16と比較する。
比較maskとoffset選択を2段で登録し、最小の一致offsetをlane別5 bitで保持する。
組立側へはdataを2 cycle、validを3 cycle遅延して渡す。組立内部の履歴を含む3 word窓と
校正の窓を揃え、raw RVALIDから組立出力までの遅延は合計4 cycleとする。
一致しないlaneも試行済みにし、resetまで再探索しない。通常読出しは保存したoffsetを用い、
payloadによって位置を変えない。training用列0の一致だけを独立したメモリ検証とは扱わず、
列8の反転patternの照合も必要とする。

`DdrArrayTrained` はこのtrainingと組立を有効にする。構築は `DDR_ARRAY_TRAINED=1 bash scripts/build_ddr_mpr.sh`、実機測定は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayTrained`。通常のarray判定と同様、合格にはUARTの `A` が必要で、frame受信だけでは合格にしない。

```bash
make ddr-read-assembler-test ddr-read-training-test ddr-trained-array-test ddr-array-test
```

試験は動的設定の全17 offset、laneごとの異なるoffset/valid時刻、reset、validなしの保持、
training後の任意payload、再training禁止、片laneの不正patternと拒否、training許可なしの拒否を含む。
324 MHzの実機で観測した重複prefixと、末尾2 beatが次cycleへまたがる配置（offset 10）も再現する。
RVALID受理直後にtraining許可が下がっても、受理済みの照合を完了することを検査する。
offset範囲は静的設定0〜8、動的設定0〜16を接続元が保証する。
これは拍位置の組立であり、DQS/DQのアナログ位相余裕を校正するものではない。

結合試験はPHYのREAD後8 cycle応答とlane別offset 6/8を再現し、追加したpipelineを含めたarray照合、古い列データの拒否、training不正の拒否を確認する。最初の組合せ実装はsetup違反279 endpointで実機へ書き込まず、pipeline化後はsetup/hold違反0となった。

2026-09-26、pipeline化したtraining版のbitstream SHA256 `d1072a1df007e87528798092aa01f04440dc8b893fcb60af8dde48a9e0155f8a` は3回の独立したFPGA書込みで全幅照合に合格した。UARTは各回 `AA5A55AA5`（先頭のAが合格status）。全回LCD SoC復帰・UART検査を通過した。3回目はFTDI初期化の再試行で回復した。これはtraining列0と反転pattern列8の検証であり、複数bank/row、refresh保持、汎用メモリコントローラ、Linux bootの検証はまだ含まない。

対応ログは "20260926-180105-DdrArrayTrained-*"、"180140"、"180236"。
