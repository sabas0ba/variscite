# Tang Primer 20K: Linux、LCD コンソール、GUI

全体の現在地と実装順序はREADMEの[実装ステータス](../README.md#実装ステータス)と
[ロードマップ](../README.md#ロードマップ)を参照する。本書は設計条件と検証範囲を記録する。

## 目的と現状

既存の Veryl RV32IMA コアで NOMMU / M-mode Linux を実機起動し、800×480 LCD に
ブートログを表示した後、Linux のユーザプロセスから GUI を描画する。
RTL は DDR3 制御、LCD 読み出し、基板トップまで Veryl で実装する。

現在の実機はオンチップ RAM 32 KiB とベアメタルの矩形表示で動作している。
Linux はシミュレータ上で起動済みだが、実機のCPUからDDR3への接続、カーネル転送、
Linux用フレームバッファは未実装である。DDR3は下記の独立診断で実機検証を進めている。

## DDR基礎実装の範囲 (PR #5)

この変更の完成単位は、DDR3のPHY・初期化・受信trainingと、単独で実行できる診断である。
既存CPU/LCD SoCのメモリ構成は変更していない。合成対象はGowinプリミティブの接続まで
Verylで実装し、SVはテストベンチとVerylの生成物に限る。

| 項目 | 確認済みの範囲 | 記録 |
| --- | --- | --- |
| PHYと初期化 | 固定GOWIN環境で396/99 MHz、RESET/CKE/MR/ZQCL、PHY起動順序 | 本書、[PHY起動](ddr-phy-startup.md) |
| 読出し | lane別の拍位置trainingとburst組立、後続データで校正値を保持 | [読出しtraining](ddr-read-training.md) |
| 保持と部分書込み | 約127 msのrefresh保持、burst内全16 byte位置のDM選択を各3回実機検証 | [アレイ診断](ddr-multi-pattern.md) |
| アドレス | 23本の有効アドレスbitと公称容量末尾を含む48 burst、全96 READを3回実機検証 | [アレイ診断](ddr-multi-pattern.md) |
| CPU側の受渡し | 範囲検査・CDC・controller経由の32 word読書きを独立実機診断で確認。CPUコアは未接続 | 本書のwordポート診断、[RTL](../fpga/tang_primer_20k/ddr_word_probe.veryl) |

最新の各実機診断は配置配線のsetup/hold違反0を確認し、診断後に既知のLCD SoCへ戻して
UART検査を行った。これは限定アドレス・単一基板での確認であり、全セル走査、任意の
アドレス結合故障、データアイの余裕、温度・電圧変動に対する保証ではない。

### 検証と再現

通常CIの`verify`ジョブはCPU回帰とFPGA platform試験を実行し、DDRの単体・結合試験も含む。
`fpga-synth`と`linux-boot`はschedule／workflow_dispatch用であり、通常PRではskipされる。
GOWINでの配置配線とUSB実機試験はローカルで行い、CI成功と区別して記録する。

直近の診断を再実行する場合、固定開発コンテナ内で次を実行する。

```bash
make lint ddr-read-training-test ddr-read-assembler-test ddr-trained-array-test \
    ddr-retain-array-test ddr-refresh-array-test ddr-refresh-duration-test \
    ddr-mask-array-test ddr-address-array-test ddr-status-uart-test
```

GOWIN用コンテナの構築手順は本書の「GOWIN EDA による配置配線の検証」、診断別のbuild指定と
実機実行モードは[アレイ診断](ddr-multi-pattern.md)を参照する。実機ログとbitstreamは
git ignoreされた`logs/board/`、`sim/fpga/`に保存し、測定時のSHA256と結果を文書に残す。
これらの生成物はcloneには含まれない。実機実行には、復帰用の検証済みLCD SoC bitstreamも必要である。

### 継続作業

DDRと周辺回路の検証完了は、限定した独立診断の成功だけでは判定しない。
以下を確認し、実機とシミュレーションの証拠を区別する。

| 検証項目 | 現在の根拠と残作業 |
| --- | --- |
| 初期化・PHY起動・lane training | 単体試験と独立実機診断。PLL/DLL異常時の復帰はシミュレーション対象 |
| DDRコマンド間隔・周期refresh | controllerモデルのコマンド監視、保持診断。全容量走査中にもrefresh継続が必要 |
| 全128 MiB・全word・両極性 | 受信遅延−4 tapの比較回路で全走査一致。繰返しと隣接設定の確認中。既存設定は不一致 |
| 部分書込み・word lane・隣接word保持 | 単体・結合試験、既存DM診断とwordポート独立実機診断 |
| 範囲外・非整列・timeout・後続要求 | ポート/controller結合試験。CPUアクセス例外への変換は未実装 |
| CDCの要求保持・応答一対一・reset取消し | 3クロック比の結合試験、停止clockでのreset試験、独立実機word診断 |
| Coreを含むDDRアクセス | 未接続。AMO/分割アクセスの失敗処理、CPUからの継続アクセスが残る |
| 配置配線・実機再現性 | 各公開bitstreamの制約・setup/hold結果・SHA256・繰返し実行結果を記録する |
| 再現手順・自動試験・PR | 試験をmake/CIへ組込み、実装状態と未検証範囲をREADME・本書・PRで一致させる |

1. DDR controllerの単体・独立実機検証は下記のとおり完了した。
   応答待ち中にもrefresh期限を守ること、timeoutやreset時の扱いを検証した。
2. wordポートとCDCの独立実機診断は完了した。次はCPUアクセス例外を実装してCPUバスへ接続し、
   可変レイテンシ、byte strobe、境界アクセスを検証する。
   接続後に全容量走査と継続アクセスを実機で確認する。
3. UARTによるImage/DTB転送とCRC検査、ブートROM、実機DTSを整備し、Linuxの`/init`到達を確認する。

LCDのframebuffer/DMA、fbconによるbootlog、LinuxユーザプロセスによるGUIは、
Linux実機起動後の段階として扱う。

## 要求・応答型DDR controller (2026-10-05)

`DdrBurstController`は初期化とtrainingが完了したPHYへ、任意のBL8要求を1件ずつ発行する。
各要求の終了時にall-bank PRECHARGEし、tRP待機後に応答する。rowを開いたままにする
最適化、複数outstanding要求、CPU/DMA仲裁は含まない。既存CPUトップへの接続は未完了である。

### 接続契約

| 信号 | 意味 |
| --- | --- |
| `i_enable` | PHY初期化・trainingとPRE/tRPが完了して使用可能。解除時はDRAM/PHYも共通resetする |
| `i_req_valid` / `o_req_ready` | 同一cycleで1のとき要求を受理し、address/data/strobeを内部に保持 |
| `i_req_addr[26:0]` | 128 MiB内の相対byte address。16 byte整列必須。bank=[26:24]、row=[23:11]、burst列=[10:4] |
| `i_req_data[127:0]` / `i_req_strb[15:0]` | byte enableは正極性でPHYのDMへ反転。strobe=0はREAD、非0はWRITE |
| `o_rsp_valid` / `i_rsp_ready` | 応答受理までvalid/data/errorを保持。その間は次要求を受理しない |
| `o_rsp_data` / `o_rsp_error` | READは全128 bit、WRITEは0。非整列要求とread valid timeoutはerror=1/data=0 |
| `i_read_data` / `i_read_valid[1:0]` | training済みassemblerのlane別応答。各laneの最初のvalidだけを採用 |

CPUの絶対アドレスの範囲検査・相対化は`DdrWordPort`で行う。
`0x80000000..0x87ffffff`内のword整列要求だけを内蔵の`DdrWordCdc`へ渡し、
backendには27 bitの相対burst addressを出力する。範囲外または非整列の要求は
ローカルでready=1/error=1/data=0を返し、DDR要求を発行しない。範囲検査は上位bitを
捨てる前に行うため、`0x88000000`などがDDR先頭へaliasすることはない。
要求元は完了までvalid/address/data/strobeを保持し、同時に発行する要求は1件とする。
範囲エラーは組合せ応答で、共通reset中は抑制する。byte/halfword転送はword整列addressと
byte strobeで表現し、非整列アクセスの分割はCPU側の責務とする。
errorのCPU例外への変換は未実装である。
`DdrWordCdc`は`i_rsp_error`を応答mailboxに保持し、CPU側の`o_ready`と同時に
`o_error`へ伝える。`o_rsp_ready`は要求受理サイクルまたは応答待ち中だけ立つ。
CPUコア自体にはまだ外部メモリエラー入力がなく、timeoutを正常完了として扱う接続は行わない。
`i_enable`解除/resetは未完了要求・応答を破棄する。
独立した片側resetやDRAM内容の保持は契約に含めない。

### CDCとの結合試験

`make ddr-cdc-controller-test`は実際の`DdrWordPort`（内蔵CDC）と`DdrBurstController`を接続し、
PHYのtraining済み読出し出力だけをテストベンチで供給する。初期化完了前の要求保持、
4 word laneの抽出、片lane欠落によるtimeout/error伝達、後続正常読出し、
要求・応答の一対一対応、15種類の書込みstrobeと4 word laneの組合せ、
各部分書込み後の全4 word読戻し、要求がない期間のrefresh、READ受理後の共通resetと復帰を検査する。
`ddr-word-cdc-test`の依存先に含め、`make all`と既存CIの両方から実行する。
3種類のクロック比で、各334要求完了、resetによる1要求取消し、70要求のローカル拒否を検査する。
拒否ケースは容量直前・直後、上位5 bitの全範囲外組合せのREAD/WRITE、先頭・末尾wordの
非整列アクセスを含む。正常ケースでは相対addressのbit [26:4]と容量末尾を検査する。
結合試験はシミュレーション限定であり、CPUコアと実PHYは含まない。
strobe=0は読出しとして検証する。データモデルは1 burstに限定し、複数addressの独立した
記憶内容と物理bank/row/column commandの検査はcontroller単体試験で行う。

CPU例外接続では通常のload/store以外に分割アクセスの後半、AMOの読出し・書込み失敗も
扱う必要がある。現在のCoreはAMOの読出し時点で宛先レジスタを更新するため、
外部エラー入力を追加する際は書込み成功まで結果の確定を遅らせる変更も必要になる。
Coreは今回変更していないため、Linux起動回帰は再実行していない。

### 27 MHz wordポートの独立診断

`DdrWordProbe`は27 MHzの要求生成回路から`DdrWordPort`、`DdrWordCdc`、
99 MHzの`DdrBurstController`を経由し、32箇所へ各1 wordを書き込む。
全8 bank、32 row、4 word laneを含むaddress列を使用し、refreshを続けながら100 ms保持後、
再書込みせずに32 wordを比較する。CPUコアは含まない。training失敗、応答error、
読出し不一致のいずれかがあれば成功しない。完了・成功は同期して診断ハーネスへ返す。
独立したenableの再投入は運用せず、再初期化にはCDCとcontrollerの共通resetを用いる。

```bash
make ddr-word-probe-test
DDR_WORD=1 bash scripts/build_ddr_mpr.sh  # 固定GOWINコンテナ
```

ホストからの実行は`scripts/test-ddr-init-board.ps1 -Mode DdrWord`。
既存診断と同じく、直近3フレームの成功を確認した後、既知のLCD SoCへ復帰する。
シミュレーションでは保持時間を1,024 CPU cycleへ短縮し、正常・14番目の読出し破損・
20番目の応答欠落の3ケースを検査する。正常・異常とも32 WRITEと32 READまで継続し、
途中の異常が後続成功で消えないことを確認する。`ddr-controller-probe-test`の依存先として
既存の`make all`とCIから実行される。

この診断には専用の`ddr_word_probe.sdc`を使う。既存診断のctrl→reference一括false pathを
引き継がず、CDC・UART診断転送に30 nsの最大遅延を設定する。応答mailboxのdataはtoggleの
2段同期後まで保持され、captureまで74 ns以上ある。要求address/dataのmailboxは
99 MHz側の2段同期後まで保持され、captureまで20 ns以上あるため最大遅延を10 nsとする。
同期器初段の位相関係によるsetup検査と、ctrl→referenceの同一エッジhold検査は除外する。
mailboxの保持契約、2段目以降とDDR内部の通常検査、CDCの最大遅延検査は維持する。
制約構文は[GOWIN Design Timing Constraints（SUG940）](https://cdn.gowinsemi.com.cn/SUG940E.pdf)
の最大遅延・例外制約に基づく。

2026-10-06、lint、word診断の3ケース、既存controller診断、CDC単体とcontroller結合の
各3クロック比、controller単体、UART両形式が通過した（`sim/word-probe-final-tests.log`）。
GOWINの配置配線は専用CDC制約下でsetup/hold違反0。bitstream SHA256は
`43dba6f5125af877ed1de4b8dafee765086374659a8a73b1d124061ea0cb71d9`。
独立した書込み3回の実機診断はいずれも直近3 UARTフレームが`!A5AA5A55A`であり、
全32 wordが一致した。全回で既知LCD SoCへの復帰とUART確認も通過した。
ログは`logs/board/20261006-104734-DdrWord-*`、`104819`、`104858`。
status後の8桁はtraining値であり、word件数ではない。範囲外要求の拒否、timeoutの注入、
全容量走査、CPU命令によるアクセス、Linux実機起動はこの実機診断に含まない。

### 全128 MiBの2極性走査（調査中）

`TangDdrFullTop`は`DdrWordProbe.FULL_WORDS=33_554_432`を使用する。
全wordを昇順に`0x193a70c5 XOR word番号`で書き、100 ms保持後に逆順で全wordを比較する。
次に値を全bit反転し、同じ書込み・保持・逆順比較を繰り返す。総数は67,108,864 WRITEと
67,108,864 READ。最初のREAD失敗時だけ、書込みを挟まず同じwordを1回再読出しする。
再読出しが成功しても元の失敗は保持し、残りの全走査を継続する。
全期間で通常controllerのrefreshを継続する。

```bash
make ddr-full-probe-test
DDR_FULL=1 bash scripts/build_ddr_mpr.sh
```

ホストの`scripts/test-ddr-init-board.ps1 -Mode DdrFull`は最大300秒で実行し、
終端statusを3回受信すると早期終了する。30秒ごとにstatusを表示し、終了後LCDへ復帰する。
結果JSONは上限時間`seconds`と実測時間`elapsed_seconds`を分けて保存する。

UART形式は`!<status><failure:8hex><actual:8hex>`。failureはbit31が失敗あり、
bit30がcontroller error、bit29が反転pass、bit28がWRITE、bit[24:0]が最初の失敗word番号。
bit27は再読出しが期待値と一致、bit26は再読出しのcontroller error、bit25は再読出しが
最初の実測値と一致したことを表す。元のactualは再読出し結果で上書きしない。
byte addressは`0x80000000 + 4 * word番号`。actualはその応答の32 bit値である。
statusが処理中のRでも最初の失敗は読み取れる。失敗なしの場合、failure/actualは0である。
他の診断の8桁payloadと混同しないよう、ホストはDdrFullだけ16桁を要求する。

短縮した64 wordモデルは正常・bit破損・valid欠落・stuck addressによるaliasに加え、
再読出しのtimeout、通常pass末尾の失敗、反転pass末尾の失敗の計7ケースを検査する。
全word書込み前の読出しや、全word読戻し前の反転pass移行を禁止し、昇順WRITE・逆順READ、
byte mask、独立計算したpattern、最初の失敗位置とactualの保持を照合する。
既存の32 word診断とUARTの従来形式も回帰試験する。

2026-10-06の最初の実機試験は失敗した。SHA256
`718727881cb37f9eed05ef96fea1f095b33a85785b2afbbdb96f434aefe60891`、
ログ`logs/board/20261006-105953-DdrFull-*`。初版UARTはtraining値のみの8桁で、
90秒時点には`!V5AA5A55A`となっていた。LCD復帰は成功した。
この結果を受け、上記の最初の失敗位置・actualを出力する64 bit診断を追加した。
この既存設定の全容量試験は未合格であり、限定32 word診断の成功から全容量正常とは判定しない。
後述の受信遅延調整版とは測定結果を分けて扱う。

64 bit診断版はSHA256
`85e71c03dd6dc30fa456263fad98c277f3ea3df5acc0b3e662a225db852dff6f`。
専用CDC制約下でsetup/hold違反0、短縮走査の4ケース、最初の失敗情報照合、
既存word診断、UARTの従来2形式と64 bit形式が通過した（`sim/full-debug-tests.log`）。
実機2回は約72.6秒で走査終了し、いずれも不一致を報告した。

| 実機ログ接頭辞 | 最初の失敗byte address | 期待値 | 実測値 | 終端フレーム |
| --- | --- | --- | --- | --- |
| `20261006-110843-DdrFull` | `0x8757E754` | `0x18EF8910` | `0x18FF8910` | `!V81D5F9D518FF8910` |
| `20261006-111057-DdrFull` | `0x8757FB54` | `0x18EF8E10` | `0x18FF8E10` | `!V81D5FED518FF8E10` |

ともに通常passのREADで、controller timeoutではなくbit 20の不一致。
位置が変化するため固定アドレス故障とは断定せず、当該patternの反復アクセスと
失敗wordの再読出しで書込み側・読出し側を切り分ける。全回LCD復帰・UART確認は成功した。
初版と64 bit版のbitstreamはローカルの`logs/board-images/`にも保存している。

#### 最初の失敗wordの再読出し

再読出し版はSHA256
`2c9a9f8d4bb28cf84581ca78d46621a1645790b09897a293b140899300abcc7f`。
実機ログ`20261006-111921-DdrFull`では、通常passの`0x8757EB54`で期待値
`0x18EF8A10`に対し`0x18FF8A10`を受信したが、書込みなしの直後の再読出しは期待値に一致した。
終端フレーム`!V89D5FAD518FF8A10`のbit27が再読出し一致を示す。
この結果は当該読出しの一過性不一致を示し、固定した保存データ不良という説明だけでは足りない。
全走査の失敗判定は解除していない。所要72.616秒、LCD復帰・UART確認は成功。
7ケースのシミュレーションは`sim/full-retry-boundary-tests.log`に記録した。

受信タイミングの比較用に`TangDdrFullShiftTop`を追加し、`READ_TAPS`で
DQS受信遅延の変更段数、`READ_DECREASE`で減少方向を指定する。変更完了を待って
array trainingを開始する。PLL/DLL設定、書込み位相、396/99 MHzの周波数は変更しない。
ビルドは`DDR_FULL_SHIFT=1 bash scripts/build_ddr_mpr.sh`、実機は`-Mode DdrFullShift`。
この比較診断にも全128 MiB・2極性・最初の失敗後の再読出しを適用する。
現在の比較用topは4 tap減少を指定する。通常の`TangDdrFullTop`は変更しない。
`ddr-mpr-delay-test`は増加方向の全走査に加え、減少方向で0→−5→−2 tapとなることを
プリミティブ入力の独立したカウンタで検査する。

| 受信遅延 | 実機ログ | 結果 |
|---|---|---|
| +4 tap | `20261006-112322-DdrFullShift` | `!B0000000000000000`、training失敗 |
| +1 tap | `20261006-112707-DdrFullShift` | `!V89FFF8C498C58801`、`0x87FFE310`で期待値`0x18C58801`に対し`0x98C58801`。再読出し一致 |
| −1 tap | `20261006-113259-DdrFullShift` | `!V8885708619FF0043`、`0x8215C218`で期待値`0x19BF0043`に対し`0x19FF0043`。再読出し一致 |
| −2 tap | `20261006-113532-DdrFullShift` | `!VA97B8F7AE7FE0040`、通常pass一致。反転passの`0x85EE3DE8`で期待値`0xE7BE0040`に対し`0xE7FE0040`。再読出し一致 |
| −3 tap | `20261006-113753-DdrFullShift` | `!VA97ACF7AE7FF4040`、通常pass一致。反転passの`0x85EB3DE8`で期待値`0xE7BF4040`に対し`0xE7FF4040`。再読出し一致 |
| −4 tap | `20261006-114045-DdrFullShift` | `!A0000000000000000`、全128 MiB・両極性一致（72.604秒） |

+4 tapのSHA256は`e20c510b0ffe55348a2fa3c1750d25b5fd8039bc40cd9ffd9bd70af37a026e34`、
+1 tapは`2ce646e7cd68a166d89475588ee832a135a2907a9ce5b17fccf82db2c6252b5b`。
−1 tapは`2d219a8408895a5181d681b842e8bade364d36987bc329aef10baf2ac2789a12`。
−2 tapは`08e91c85aed4ce781b76492f91d8efa11e0cbec099f1bd510c21b282110194ee`。
−3 tapは`4842de129d9385fa138738dbb206fa892c05c9a7367c4523cff85bbeacbbb940`。
−4 tapは`a2ebd649c977b6f265f5c3c435eadb3e93949d25e69875a1efb9b513910c11fa`。
各回路ともsetup/hold違反は0件で、試験後のLCD復帰・UART確認は成功した。
−4 tapで初めて全容量走査が一致した。同一bitstreamを再書込みした
`20261006-114226-DdrFullShift`（72.597秒）と`20261006-114404-DdrFullShift`（72.603秒）も
全容量・両極性が一致し、計3回の独立起動を確認した。各回LCD復帰・UART確認も成功。
3回目は最初のFTDI reset errorを既存の再試行処理で回復してから書き込んだ。
隣接設定の比較は継続する。単一基板・室内条件であり、温度・電圧変動の検証ではない。

### コマンドとrefresh

99 MHz制御、396 MHz DDR clock、CL=6/CWL=5を使用する。WRITEはCA slot 3、他のアクセス
コマンドはslot 2で発行し、DQS preamble/data/postambleは既存診断と同じ配置を使う。
ACT後4 controller cycleでREAD/WRITEし、WRITE後10 cycleでPRECHARGE、READは12 cycleの
受信窓を終えてPRECHARGEする。両laneが揃わない場合も窓を延長せずerrorを返す。

開始時にREFRESHし、以後は前回REFから256 cycle以上経過すると、新規要求よりrefreshを
優先する。処理中の1要求はPRE/tRPまで完了してからREFへ進む。REF後は32 cycle（約323 ns）
待機する。これは[Hynix資料](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf)
page 14の1 Gbit向けIDD測定条件（nRFC=59 CK @1.875 ns等）より長く取った保守的な待機値である。
試験ではREF間隔が384 cycle（約3.879 µs）を超えないことを監視する。
未消費の応答は独立レジスタに保持し、その間もidle/REFの処理を継続する。

### 検証と実機診断

```bash
make ddr-burst-controller-test ddr-controller-probe-test
DDR_CONTROLLER=1 bash scripts/build_ddr_mpr.sh  # 固定GOWINコンテナ
```

controller単体試験では全有効アドレスbit・容量末尾、16位置のbyte strobe、非整列要求、
応答backpressure、idle中のrefresh、lane別valid、重複valid、片lane／全laneのtimeout、
要求処理中・応答保留中のresetを検査する。応答の保持、1要求1応答、CA/DQS/DMの順序・
間隔とrefresh期限をモデルで監視する。

`DdrControllerProbe`は32箇所を書き、100 ms保持してから再書込みなしで32 READを照合する。
最初のWRITE応答は1,024 cycle保留し、その間もrefreshを継続させる。
短縮した保持時間で、正常系、途中のデータ破損、valid欠落の3ケースをシミュレーションする。
`TangDdrControllerTop`は既存の2列診断でPHYをtrainingした後にcontrollerへ引き渡す。
trainingまたはcontroller照合が失敗すれば成功statusにはならない。

実機は`scripts/test-ddr-init-board.ps1 -Mode DdrController`で検査する。
合格には開始記号付きUARTフレームの直近3個がすべて`!A`で始まることを要求し、
終了後は既知のLCD SoCへ復帰する。status後の8桁はtraining診断の値であり、
controllerのREAD件数やrefresh件数ではない。

2026-10-05、lint、controller単体試験、診断3ケース、UART両形式、CDCの3クロック比、
既存trained/address/PHY起動回帰試験が通過した。ログは`sim/controller-regression.log`と
`sim/controller-final-tests.log`。新規2試験を`make all`とCIへ追加した。
実機用回路は配置配線のsetup/hold違反0、bitstream SHA256は
`169049dbbb7bcb5b09c98db7d7262f0cabe6368c4ef06b455bec862d5fbd2ca2`。
独立した実機書込み3回で全32 READが一致し、UARTは全回`!A5AA5A55A`だった。
全回LCD SoCへの復帰とUART検査も成功した。実機ログは
`logs/board/20261005-174426-DdrController-*`、174527、174548。
CPUからのアクセス、errorのCPU例外への変換、全容量走査、
LCD DMAとの仲裁と必要帯域はまだ検証していない。

## 最初の実測: DDR3 PHY のツール対応

2026-09-07、既存の固定コンテナ内で `DQS` の最小 Veryl インスタンスを合成・配置した。

```bash
bash scripts/check_ddr_toolchain.sh
```

- 対象: `GW2A-LV18PG256C8/I7`、family `GW2A-18C`
- コンテナ: `sha256:8ddc50649d4ae3fda9d5790f60ebeb7b8ee28a7dbd53f0547b4234945ffd6143`
- Veryl: v0.20.3
- Yosys: `0.68+40`, `0f2bcb94b-dirty` (固定配布バイナリの表示)
- nextpnr: `nextpnr-0.11-1-g62e659ed`
- 結果: Veryl 変換と Yosys 合成は成功。packing も成功するが、placement で失敗。

```text
ERROR: Unable to place cell 'dqs', no BELs remaining to implement cell type 'DQS'
```

3 本の I/O と DQS 1 個だけの回路で発生するため、CPU や LCD との資源競合ではない。
Yosys にプリミティブ宣言が存在することだけでは、nextpnr が配置できることを保証しない。
この結果は現在の固定ツールにおける DQS ベース PHY の制約であり、他の PHY 方式や
将来のツールで DDR3 が利用不可能であることを意味しない。

再現用 RTL は `fpga/tang_primer_20k/ddr_capability_probe.veryl`。
これは合成・配置能力の検査専用であり、クロック比やピンを DDR3 実動作用に構成していない。
ビットストリームを生成せず、基板へは書き込まない。
結果は `sim/fpga/ddr_capability/{versions,veryl,yosys,nextpnr}.log` に保存する。
終了コード非ゼロを正常な DDR3 対応として扱わず、通常の `make all` には含めない。

## 実装順序と合格条件

| 段階 | 実装 | 合格条件 |
|---|---|---|
| 1. DDR3 | PHY、初期化・校正、refresh、byte mask、CPU バスとの応答待ち | データ・アドレスの walking pattern、疑似乱数、境界、部分書き込み、refresh をまたぐ保持試験を実機で通す |
| 2. Linux 起動 | ブート ROM、UART 経由の Image/DTB 転送、CRC 検査、実機 DTS | カーネルから `/init` に到達し、UART シェル、タイマ、ユーザプロセス起動を確認 |
| 3. LCD ブートログ | DDR3 上の RGB565 フレームバッファ、LCD 読み出し DMA、ライン FIFO、Linux fbcon | UART と LCD に同じカーネルログが現れ、連続スクロールで FIFO underrun がない |
| 4. GUI | `/dev/fb0` へ描画する軽量な Linux ユーザアプリケーション | Linux プロセスとして画面・文字・操作状態を描画し、UART 入力に応答する |

最初のブート手段は既存 USB-UART を使用し、SD カードへの書き込みを前提にしない。
初期の GUI はフレームバッファへ直接描画し、追加 UI ライブラリを必要としない構成で着手する。
タッチ、USB キーボードなどの入力機器は、その後に接続構成とドライバを確認する。

## メモリと表示の設計条件

- 基板の DDR3 公称容量は 128 MiB。実機のメモリ型番・geometry と初期化条件を確認し、
  alias 検査で実容量を確定してから DTS に記述する。
- CPU は既存の NOMMU / M-mode 構成を継続する。ROM から Linux へ移る際に hartid と
  DTB アドレスを `a0` / `a1` へ渡す。
- 現在の `FpgaSoc` は固定 2 サイクル応答である。DDR3 は可変レイテンシなので、要求を
  保持して完了を待つバス接続が必要。既存ベアメタル用トップも回帰検証する。
- RGB565 の 800×480 は 768,000 byte。33 MHz の表示では、active 区間の瞬間読み出しは
  66 MB/s、1056×505 の走査全体で平均約 47.5 MB/s となる。DDR3 の CPU/DMA 仲裁と
  ライン FIFO は refresh やバンク操作による停止を含めて設計する。
- フレームバッファ領域を Linux の通常 RAM から予約し、ブートローダで表示回路を初期化する。
  Linux v6.12 の `simple-framebuffer` と fbcon を第一候補とする。
- UART の実クロックは 27 MHz。現在のシミュレータ用 DTS の 1 MHz UART 設定は流用しない。
  ブート初期は UART earlycon、fbcon 初期化後に蓄積したカーネルログを LCD に表示する。
  カーネル開始前の表示はブートローダの進捗表示として別に扱う。

## GOWIN EDA による配置配線の検証

2026-09-13、利用者の再開指示を受けて公式 Linux 教育版を専用コンテナに導入した。
`ddr_gowin_probe.veryl` の DQS、DLL、OSER4_MEM、IDES4_MEM 各 1 個を接続した
双方向 1 bit の回路について、合成・配置配線と資源の残存を確認した。
DLLSTEP の定数接続は GOWIN が拒否するため、このプローブでは実際の DLL 出力を接続する。
nextpnr 用の最小プローブとは構造が異なり、直接の同一回路比較ではない。

これは配置配線ツールの対応検査である。PCLK/FCLK は同一入力、基板ピンとタイミングは
未制約であり、DDR3 の動作周波数、タイミング収束、校正、読み書きの成立を示さない。
GOWIN は `run pnr` でビットストリームも生成するが、**このプローブは実機へ書き込まない**。
実機のベアメタル LCD ビットストリームは変更していない。

| 項目 | 固定値 |
|---|---|
| GOWIN EDA | V1.9.11.03 Education Linux |
| 公式アーカイブ SHA256 | `6fd392f7473b24d847b6f8ebdc7a185c591826ba35d8d0e517961030d446f9f7` |
| 公式公開 MD5 (取得時照合) | `d65912e3da9cdbebed92f0ccc5feb498` |
| Ubuntu ランタイム snapshot | `20260901T000000Z` |
| ランタイム依存 | `container/gowin-runtime.sha256` と `container/gowin-runtime.versions.tsv` の 56 パッケージ |
| 検証済み専用イメージ ID | `sha256:1b9cfd5aefe08b418ea5f43f5f0cf7efbd1b20c551506deac8d691bba9f2a70b` |

`container/Gowin.Containerfile` は既存の固定開発イメージを継承する。
Ubuntu パッケージは `/opt/gowin-runtime` に展開し、GOWIN プロセスだけが参照する。
Qt の `offscreen` 設定でディスプレイサーバーなしに CLI を起動する。
ベンダー同梱の旧ライブラリと新しい fontconfig の混在を避けるため、ランタイムと
Ubuntu 標準ライブラリを GOWIN 同梱ライブラリより先に探索する。
ホストへのインストール、外部ソースの RTL への取り込みは行っていない。

以下はリポジトリのルートで実行する Bash 表記。Windows では bind mount の `$PWD` を
リポジトリの絶対パスに置き換える。取得手順にはネットワークと依存追加の許可が必要。
教育版の利用条件は公式配布元で確認し、アーカイブと専用イメージは公開しない。

```bash
base=sha256:8ddc50649d4ae3fda9d5790f60ebeb7b8ee28a7dbd53f0547b4234945ffd6143
podman run --rm --pull never -v "$PWD:/work" "$base" \
  curl --fail --location --retry 2 \
  --output logs/Gowin_V1.9.11.03_Education_Linux.tar.gz \
  https://cdn.gowinsemi.com.cn/Gowin_V1.9.11.03_Education_Linux.tar.gz
podman run --rm --pull never -v "$PWD:/work" "$base" \
  bash scripts/fetch_gowin_runtime.sh
podman build --pull=never --network=none \
  --ignorefile container/gowin.containerignore \
  -f container/Gowin.Containerfile -t localhost/variscite-gowin:1.9.11.03 .
podman run --rm --pull never --network none -v "$PWD:/work" \
  localhost/variscite-gowin:1.9.11.03 bash scripts/check_ddr_gowin.sh
```

結果は `sim/fpga/ddr_gowin/` の `veryl.log`、`gowin.log`、`impl/pnr/` に保存する。
スクリプトは配置配線の完了、新しいレポート、4 種類の資源数を検査してから PASS を返す。
クロック未制約の警告はこの構造検査の制限として残し、動作タイミングの合格とは扱わない。
実機用 PHY ではクロック生成、DDR3 ピン制約、2 レーンと 16 bit の接続、初期化と
校正を実装し、実メモリの読み書き・refresh 試験を通す必要がある。

## Linux 起動に向けた接続部の実装 (2026-09-13)

DDR3 の実メモリ試験に先立ち、以下を独立した Veryl モジュールとして追加した。
まだ既存 CPU トップへ組み込んでおらず、Linux の実機起動や DDR3 の読み書きが
成立したことを示すものではない。

| モジュール | 内容 | 検証 |
|---|---|---|
| `Ddr3Startup` | RESET 保持、RESET 解除後待ち、CKE、MR2→MR3→MR1→MR0、ZQCL、完了待ち | 短縮/実時間相当の 2 設定で各 9 回の初期化。コマンド受理待ち、途中リセット、PHY readiness 喪失を検査 |
| `DdrWordCdc` | CPU 32 bit と DDR 128 bit バースト間のメールボックス CDC | 3 種類のクロック比で各149トランザクション。全16通りのbyte maskと4 word lane、遅延・同時応答、error伝達と後続正常応答、停止クロック中の共通resetを検査 |
| `TangDdrClock` | 27 MHz → PLL 396 MHz → DHCEN → CLKDIV /4 → 99 MHz | SERDES を負荷とする検証トップで GOWIN 合成・配置配線。派生クロック周期 2.525 ns / 10.101 ns の認識を確認 |

```bash
make ddr3-startup-test ddr-word-cdc-test
bash scripts/check_ddr_clock.sh  # GOWIN 専用コンテナ
```

2 種類の RTL テストは `make all` と CI の `verify` に含める。
クロック検証はベンダーツールを必要とするため CI の通常ジョブには含めない。
クロック検証トップの基板制約は基準クロックと DDR 差動クロックだけであり、
生成ビットストリームを実機へ書き込まない。396 MHz の外部メモリ I/O タイミングを
保証する検査ではない。

CDC の要求・応答ペイロードは、対応する toggle が同期先に届くまで保持する。
リセットは必ず両クロック領域に共通の非同期リセットを与え、接続先の要求/応答処理も
同時に中断する。解除はモジュール内で各クロックの 2 段 FF に同期する。
片側だけのリセットには対応しない。1 要求につき応答は 1 回、
CPU は `o_ready` を受け取るまで要求を保持する。
DDR 側の書き込みは BL8 の 128 bit に対する 16 bit byte enable で表現するため、
PHY 側で DDR3 DM のマスク極性へ反転する必要がある。32 bit 書き込みに
read-modify-write は不要である。

初期化シーケンサの既定値は 99 MHz の制御クロックを想定し、RESET を 400 µs、
解除後を 1 ms 保持する。CL=6、CWL=5、WR=6、DLL 有効/リセットの設定は
搭載チップ H5TQ1G63EFR-PBC の 396 MHz 動作範囲を満たす。
待ち時間と MR 値はパラメータ化した。
`ZQ_CYCLES` にはコマンド受理から実際の DRAM コマンド発行までの PHY 遅延も含める。
実機に適用する前に、PHY 側の発行レイテンシと校正を含む実動作を確認する。

未実装: DLL 初期化、write leveling/read calibration、通常の DRAM
コマンド発行と refresh、CPU トップへの統合、UART ブートローダ、LCD framebuffer。
実機のメモリ初期化・書き込みは実施していない。

## 搭載 DDR3 と x16 PHY の構造検査 (2026-09-21)

利用者が基板上の刻印 `SK Hynix H5TQ1G63EFR PBC` を確認した。
[SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf)
によると、1 Gbit = 128 MiB、64M×16、8 バンク、行 13 bit、列 10 bit、1.5 V である。
PBC は DDR3-1600 の速度 grade。396 MHz の CK (DDR3-792) では CL=6、CWL=5 を使用できる。
接続済み A13 はこの x16 チップでは NC なので、実際のコントローラでは 0 に固定する。

`TangDdrPhyIo` は CA/CK の OSER8、DQ/DM/DQS の OSER8_MEM、DQ の IDES8_MEM、
2 個の DQS、および SSTL15 の I/O buffer を Veryl からインスタンス化する。
CPU 側を 99 MHz、メモリ CK を 396 MHz とする 4:1 構成で、BL8 を 128 bit として扱う。
書き込み DM は active-high mask、DQ/DQS の出力 enable は active-high で受ける。

`TangDdrPhyCheck` は全ピンを
[Sipeed の基板制約](https://github.com/sipeed/TangPrimer-20K-example/blob/main/Litex/sipeed_tang_primer_20k/src/sipeed_tang_primer_20k.cst)
に配置した構造検査専用トップ。DQ の内部 VREF と DDR バンクの 1.5 V を指定する。
DLL は 396 MHz の高速クロックを入力とする。GOWIN V1.9.11.03 で合成・配置配線し、
DLL 1、DQS 2、IDES8_MEM 16、OSER8_MEM 20、OSER8 24 の残存を検査した。
STA は派生クロックを 396/99 MHz と認識し、トップ内の解析済み経路に setup/hold 違反はない。
外部 DDR3 の setup/hold、read eye、write leveling はこの構造検査で判定していない。
検査ビットストリームは任意の DDR コマンドを出すため、**実機へ書き込まない**。

```bash
podman run --rm --pull never --network none -v "$PWD:/work" \
  sha256:1b9cfd5aefe08b418ea5f43f5f0cf7efbd1b20c551506deac8d691bba9f2a70b \
  bash /work/scripts/check_ddr_phy.sh
```

### 初期化専用トップの実機確認

`TangDdrInitProbe` は接続した 16 bit PHY から RESET、CKE、MR2→MR3→MR1→MR0、
ZQCL を発行する。PLL/DLL ロックとシーケンサ完了状態を UART に送信する。
`P` は PLL 待ち、`L` は DLL 待ち、`I` は初期化中、`R` はコマンドシーケンス完了を表す。
DQ/DQS は出力無効で、メモリの書き込み・読み出しは行わない。

2026-09-21 に `scripts/build_ddr_init.sh` で生成した SRAM イメージ
SHA256 `ff4506d300ce092e6c171ae7aa966518fdc7122218df2f31f41cb56feccada44`
を実機へ一時書き込みした。COM4/115200 baud の 4 秒間で `R` を 25 回連続受信した。
これは FPGA 内の PLL/DLL ロックと初期化シーケンサ進行を示す。DDR3 側からの
応答を含まないため、実メモリの初期化成功や読み書き可能性は未判定である。
検査後は検証済み LCD サンプル SHA256
`40bac365ce8f971d240ac5aa6a2e4c69c1fff5579c6dbbb2afe4f97662b9eb0a`
を復元し、LCD サンプルの UART 回帰検査も通過した。

```powershell
scripts/test-ddr-init-board.ps1 -Suite C:/Users/sabas/repos/hello_veryl/tools/oss-cad-suite -Port COM4
```

DQS/READ ゲートの初期の実機検出結果は [DDR3 読出し DQS ゲート検証](ddr-read-gate.md) に記録した。
その後の読書き・refresh検証は下記の2026-10-05時点の結果を参照する。

MPR の既知パターンによる DQ 受信診断と配置依存の実機結果は
[DDR3 MPR 読出し診断](ddr-mpr.md) に記録した。MPR の安定受信と
当初のDRAMアレイ診断結果は以下に記録する。Linux用RAMとしての接続は未完了である。
RVALID と DQ の前後 1 controller cycle の比較は
[DDR3 MPR サイクル位置診断](ddr-mpr-align.md) に記録した。
2 列への反転パターン書込みと読戻しの初期結果は
[DDR3 アレイ書込み・読戻し診断](ddr-array.md) に記録した。

## 2026-10-05時点のDDR実機検証

VerylでPHY起動制御、lane別の拍位置training、読出し組立を実装した。
[trainingと単体・結合試験](ddr-read-training.md) および
[複数pattern・全書込み後の再読出し](ddr-multi-pattern.md) に結果を記録する。
疎な8組のbank/rowへ16 burstを書き、全書込み後の再読出しを含む32 READが
3回の独立したFPGA書込みで一致した。各回LCD SoCへの復帰も成功した。
さらにREFRESHを約3.88 µs間隔で32,768回発行し、約127 ms保持した後の
全32 READ一致も、独立した実機書込み3回で確認した。
DMによる1 byte更新もburst内の全16位置で検証し、非選択byteの保持を含む
全32 READが実機3回とも一致した。
さらにbank 3 bit・row 13 bit・burst列7 bitを個別に変え、公称128 MiBの
最後の2 burstを含む48 burstを書いた後の全96 READ一致を実機3回で確認した。
この診断は各アドレス組の間にもrefreshを発行し、UARTには明示的な開始記号を付けている。

これは限定アドレスの診断であり、全容量の全セル走査は未実施である。
次に継続的なrefreshと要求処理を仲裁するcontroller、CPUのbyte strobe変換、
応答待ちを実装して、CPUから使えるDDRメモリ制御へ接続する。
Linux実機boot、LCD上のLinux bootlog/GUIはまだ達成していない。

## 一次資料

- [Sipeed Tang Primer 20K 仕様](https://en.wiki.sipeed.com/hardware/en/tang/tang-primer-20k/primer-20k.html)
- [LiteDRAM の GW2A DDR PHY](https://github.com/enjoy-digital/litedram/blob/master/litedram/phy/gw2ddrphy.py): DQS とメモリ用 SERDES の接続例。参照のみで、依存として導入していない。
- [Tang Primer 20K 用 DDR3 コントローラ](https://github.com/nand2mario/ddr3-tang-primer-20k): Gowin ツールによる実装例。参照のみで、ソースは取り込んでいない。
- Linux v6.12 のローカル資料: `/opt/src/linux/Documentation/devicetree/bindings/display/simple-framebuffer.yaml`
- [GOWIN EDA 公式配布元](https://gowinsemi.com/en/support/home/)
- [GOWIN 教育版と公開チェックサム](https://www.gowinsemi.com.cn/software/3)
- GOWIN 同梱の一次資料: `/opt/gowin/IDE/simlib/gw2a/prim_sim.v` の DLL/DQS/SERDES 宣言
- [Ubuntu Snapshot Service](https://snapshot.ubuntu.com/)
- [Winbond W631GU6MB Rev. A03 データシート (メーカー文書、DigiKey 配布)](https://media.digikey.com/pdf/Data%20Sheets/Winbond%20PDFs/W631GU6MB_A03.pdf): 初期化の参照資料。実機の搭載型番をこの型番と断定していない。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 実際の搭載チップの容量、アドレス構成、速度 grade、MR 条件。
- [Sipeed Tang Primer 20K DDR ピン制約](https://github.com/sipeed/TangPrimer-20K-example/blob/main/Litex/sipeed_tang_primer_20k/src/sipeed_tang_primer_20k.cst): ピン、SSTL15、DQ 内部 VREF。
