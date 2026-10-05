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
| CPU側の受渡し | `DdrWordCdc`の32/128 bit変換とクロック間要求・応答をシミュレーションで検証 | 本書の初期化・CDCの検証記録、[RTL](../fpga/tang_primer_20k/ddr_word_cdc.veryl) |

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

1. DDR controllerの単体・独立実機検証は下記のとおり完了した。
   応答待ち中にもrefresh期限を守ること、timeoutやreset時の扱いを検証した。
2. `DdrWordCdc`とCPUバスへ接続し、可変レイテンシ、byte strobe、境界アクセスを検証する。
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

CPUの絶対アドレスの範囲検査・相対化、errorのCPU例外への変換は接続側で実装する。
`DdrWordCdc`は`i_rsp_error`を応答mailboxに保持し、CPU側の`o_ready`と同時に
`o_error`へ伝える。`o_rsp_ready`は要求受理サイクルまたは応答待ち中だけ立つ。
CPUコア自体にはまだ外部メモリエラー入力がなく、timeoutを正常完了として扱う接続は行わない。
`i_enable`解除/resetは未完了要求・応答を破棄する。
独立した片側resetやDRAM内容の保持は契約に含めない。

### CDCとの結合試験

`make ddr-cdc-controller-test`は実際の`DdrWordCdc`と`DdrBurstController`を接続し、
PHYのtraining済み読出し出力だけをテストベンチで供給する。初期化完了前の要求保持、
4 word laneの抽出、片lane欠落によるtimeout/error伝達、後続正常読出し、
要求・応答の一対一対応、15種類の書込みstrobeと4 word laneの組合せ、
各部分書込み後の全4 word読戻し、要求がない期間のrefresh、READ受理後の共通resetと復帰を検査する。
`ddr-word-cdc-test`の依存先に含め、`make all`と既存CIの両方から実行する。
結合試験はシミュレーション限定であり、CPUコア、アドレス範囲検査、実PHYは含まない。
strobe=0は読出しとして検証する。メモリモデルは1 burstに限定し、容量境界やbank切替は
controller単体試験の対象とする。

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
