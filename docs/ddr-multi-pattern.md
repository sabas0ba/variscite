# 複数pattern・bank/rowのDDR診断

要求・応答型controllerおよび27 MHz wordポート・CDC経由の独立実機診断は、
[Linux/LCD実装計画の検証記録](tang-linux-lcd.md#27-mhz-wordポートの独立診断)を参照する。

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

## Refreshを継続した保持試験

`DdrArrayRefresh` はretain診断の2つのpassの間にREFRESH期間を挿入する。
全bankをPRECHARGEして既存のtRP待機を終えた後、384 controller cycleごとに
32,768回のREFRESHを発行する。最後のREFRESH後も384 cycle待ってからACTIVATEする。
99 MHzでは間隔3.8788 µs、保持期間127.1001 msとなる。保持期間中のWRITE、
DQ/DQSの駆動、ODT、終了によるDRAM resetは行わない。

[SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf)
のPDF page 1と10は、通常温度範囲のrefresh間隔7.8 µs、拡張温度範囲3.9 µsを示す。
page 14のIDD測定条件は1 GbitのnRFCを59 CK（tCK=1.875 ns）、88 CK（1.25 ns）等とする。
本診断はREF後3.8788 µsの全期間を待機し、これらの測定条件より十分長く確保する。
この表を汎用controllerのtRFC最小値規定として扱ってはいない。
REF commandの符号はpage 22の測定シーケンス（CS/RAS/CAS/WE = 0/0/0/1）とも照合した。

```bash
make ddr-refresh-array-test ddr-refresh-duration-test
DDR_ARRAY_REFRESH=1 bash scripts/build_ddr_mpr.sh
```

実機測定は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayRefresh` を使い、
全32 READ一致を表すUART status `A` を要求する。短縮試験では4回のREFRESHで
既存の7ケースと保持中のbit破損を検査する。別の正常系試験では実機と同じ32,768回を
発行し、カウンタの桁境界、総待機期間、最終REF後の待機を検証する。
テストベンチはREFRESHの回数・間隔、全bank閉鎖とtRP、保持中のバス非駆動、
再書込み禁止、保持後の一致判定を監視する。DRAMセルの物理的な電荷減衰はモデル化しない。

対象はretain診断と同じ16 burstに限る。全容量、温度・電圧変動、連続CPUアクセスと
refreshの仲裁を保証する試験ではない。

2026-10-05、lint、保持試験8ケース、32,768回の発行試験、既存retain/multi/trained/
array/aligned-scan回帰試験が通過した（`sim/refresh-regression.log`）。実機と同じ設定の
シミュレーションは12,583,593 controller cycle、16 WRITE/32 READ/32,768 REFだった。
配置配線のsetup/hold違反は0。bitstream SHA256は
`65b2f51742d4c3df2797cacf0884c6fec28db7ad904f5d7dec0d21a8f0c0bd72`。
独立した実機書込み3回でUARTは全回`A95A56AA5`となり、全32 READが一致した。
各回ともLCD SoCへの復帰・UART検査も成功した。ログは
`logs/board/20261005-153443-DdrArrayRefresh-*`、153606、153624。

### 保存済みPDFの再読取り

資料のSHA256は `9da32b94e76f6bf98848e8eb703fc0b008b282ffed6adc8a506572ad217cb9b4`。
`scripts/read-reference-pdf.sh` は任意の資料読取り用であり、通常のbuild/CIには不要である。
利用者承認のもとpypdf 6.19.0のwheelを`logs/pdf-tools/`へ取得し、SHA256
`7e5d6e730e7dae87d560a2cee218b852f6498c8be61966f3cd02ead971e48d14`を検証して
固定開発コンテナ内のPythonから直接読む。pip installやホスト環境変更は行わない。
取得済みならネットワークを無効にして再実行できる。

```bash
bash scripts/read-reference-pdf.sh logs/ddr-reference/sk_hynix.pdf logs/ddr-reference/sk_hynix-plain.txt --plain
```

出力には原本のSHA256とPDF page番号を含む。回転表は既定のlayout抽出では欠落するため
`--plain`を使い、数値の単位と列見出しを合わせて確認する。

## DMによる部分書込み

`DdrArrayMask` はmulti診断の各bank/row組で、2列の全byte書込み・読戻しを行った後、
同じ2列へDMでbyteを選択して再書込みし、全128 bitを再照合する。
DQには元データの全bit反転を出し、DMで選択した1 byteだけを更新する。
他の15 byteは元の値を保持しなければ合格しない。最初の読戻しでtrainingを終え、
その拍位置を部分書込み後の読戻しでも使用する。初期読戻しの失敗は再書込みでも消去しない。

組番号0..7に対し、列0ではbyte 0..7、列8ではbyte 8..15を順に選択する。
byte番号は`DQ[8*b +: 8]`の順であり、これにより両lane・8 beatの全16位置を通す。
全32 WRITE/32 READ、8 ACT/PRE、761 controller cycle（99 MHzで約7.69 µs）で終了する。
この診断自体はrefreshを発行しない。

```bash
make ddr-mask-array-test
DDR_ARRAY_MASK=1 bash scripts/build_ddr_mpr.sh
```

実機には `scripts/test-ddr-init-board.ps1 -Mode DdrArrayMask` を用いる。
合格には全読出し一致のUART status `A` が必要である。テストベンチは実際に出力された
DMをbyteごとに適用するモデルを使い、WRITE/READのbank/column、更新byteの全位置到達、
初期値と反転値、コマンド回数を別途検査する。中間の1組に対するDM無視、更新禁止、
lane入替え、beat位置ずれ、および初期読戻し・部分書込み後の読戻しのbit破損を注入し、
後続の正常結果で失敗が隠れないことを確認する。
初期読戻しの失敗判定は比較結果を登録した次のcycleで更新し、128 bit比較から
失敗フラグまでの組合せ経路を分割する。

この試験はDMの1 byte選択を検証する。任意の複数byte mask、CPUのアドレスとbyte strobeの
変換、CPUバス接続、全容量の健全性は別途検証が必要である。

2026-10-05、lint、7ケースの部分書込み試験、refresh（短縮版と32,768回の実時間版）/
retain/multi/trained/array/aligned-scan回帰試験が通過した（`sim/mask-regression.log`）。
配置配線のsetup/hold違反は0。bitstream SHA256は
`da6b1836509b5d4e630311cd1bc58661a205dbe9bf3002942088e6436fb98106`。
独立した実機書込み3回はいずれも全32 READが一致し、UARTは`A9DA5EAA5`となった。
全回LCD SoC復帰・UART検査も成功した。ログは
`logs/board/20261005-160812-DdrArrayMask-*`、163217、163236。

## アドレスbitと容量末尾の再照合

`DdrArrayAddress` は24組のbank/row/columnに48 burstを書き、直後の読戻しに加え、
全書込み後に再書込みなしで全組を照合する。全96 READが一致した場合のみ成功とする。
各burstには異なるpatternを与え、途中の失敗は後続の一致で消去しない。

[SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf)
PDF page 9のx16列は8 bank、row A0..A12、column A0..A9を示す。
この診断の組合せは以下であり、各組の列CとC+8をBL8で扱う。

| 組 | bank | row | 列C |
| --- | --- | --- | --- |
| 0 | 0 | 0 | 0 |
| 1..3 | 1、2、4 | 0 | 0 |
| 4..16 | 0 | 1、2、4、…、4096 | 0 |
| 17..22 | 0 | 0 | 16、32、64、128、256、512 |
| 23 | 7 | 8191 | 1008 |

bank 3 bit、row 13 bit、burst列7 bit（column A3..A9）を個別に変える。
最終組の列1008と1016は、公称128 MiBの最後の2 burstに相当する。
column A0..A2はBL8内の拍であり、非整列開始列はこの診断の対象外である。

長時間の無refresh区間を作らないよう、各組のall-bank PRECHARGEとtRP待機後に
REFRESHを発行する。REF後は256 controller cycle（99 MHzで約2.586 µs）待機する。
以後の短い読書きシーケンスを含めてもREF間隔は384 cycle（約3.879 µs）以内に収まる。
最後の組では再REFせず診断を終了し、既存の処理でDRAMをresetする。
全体は48 WRITE、96 READ、48 ACT/PRE、47 REF、14,073 cycle（約142.15 µs）となる。
これは要求処理を仲裁する汎用controllerではなく、固定シーケンスの診断である。

```bash
make ddr-address-array-test
DDR_ARRAY_ADDRESS=1 bash scripts/build_ddr_mpr.sh
```

実機測定は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayAddress` を使う。
この診断のUARTは`!`、status 1文字、16進数8桁の形式であり、直近3個の完全な
フレームがすべて`!A`で始まることを合格条件とする。デバッグ値に`A`/`B`/`E`が
含まれてもstatusと誤認しないよう、開始記号を必須とする。受信は8秒間行う。
従来診断のUART形式は維持し、両形式を`make ddr-status-uart-test`で検証する。
テストベンチはACTで開いたbank/rowとREAD/WRITEのcolumnから実際の格納先を計算し、
疎な連想配列へデータを保存する。transaction番号を格納先の代用にはしない。
正常系、23 bitそれぞれの切断によるalias、検証passでのvalid欠落とbit破損、
初回trainingの破損を含む27ケースを検証する。
列A3以外のaliasでは初回の即時読戻しが成功し、全書込み後の照合で失敗することも検査する。
加えてREFの期限、PRE/tRP、REF後の待機、bus非駆動、再書込み禁止、patternの一意性、
各コマンドのアドレスと回数を監視する。

成功しても全容量の全セルを走査したことにはならない。任意のアドレスbit間の結合故障、
非整列burst、長期保持、温度・電圧変動に対する動作保証は別途検証が必要である。

2026-10-05、27ケースのアドレス診断、既存mask/refresh/retain/multi/trained/array/
aligned-scan回帰試験、lintとUART両形式の試験が通過した。
ログは`sim/address-regression.log`、`sim/address-uart-test.log`。
最終bitstreamはsetup/hold違反0、SHA256
`7c255b03cc55815a5a6566c3aca716860dc0322aec4c7431aa750a463fcff27d`。
独立した実機書込み3回で全96 READが一致し、UARTは全回`!AE37A1C85`だった。
全回LCD SoCへの復帰・UART検査も成功した。実機ログは
`logs/board/20261005-170745-DdrArrayAddress-*`、170805、170826。
