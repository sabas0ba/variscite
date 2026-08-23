# rv32ima_veryl

Veryl による RV32IMA_Zicsr コア (M/U-mode、PMP、NOMMU) と、その割り込みコントローラ
(CLINT / PLIC) を含む SoC の実装と検証環境。riscv-tests の全件通過、Spike との
コシミュレーション一致、Verilator シミュレーション上での Linux 起動とユーザ
アプリケーションの実行までを含む。

## 構成

- コア: マルチサイクル (fetch / execute / mem_access / mem_access2 / amo_write /
  divide)、単一 32bit メモリポート (valid/ready、wstrb=0 で read)
- RV32I 全命令、M (MUL/DIV 系)、A (LR/SC, AMO 9 種)、Zicsr
- M 拡張の乗算は単一サイクルの組合せ回路である (FPGA では DSP に載るため fabric を
  消費しない)。除算は逐次で、復元法 1 ステップ/サイクルの 33 サイクルを要する。
  符号付きオペランドは絶対値に還元するため、DIV/DIVU/REM/REMU は 33bit の減算器を
  1 個だけ共用する。ゼロ除算と INT_MIN / -1 の符号付きオーバーフローは反復せず
  1 サイクルで確定する
- 特権: M-mode と U-mode。mstatus.MPP、mcounteren によるカウンタ許可、CSR の特権
  チェック、U-mode からの特権命令の不正命令例外
- PMP: 16 エントリ。OFF/TOR/NA4/NAPOT、R/W/X、L bit (ロック時は M-mode にも適用し、
  当該 cfg と address の書き込みを凍結)。非マッチ時は M-mode 許可 / U-mode 拒否
- 割り込み: machine timer / software / external (PLIC 経由)。mie/mip、mstatus.MIE、
  mtvec の direct / vectored 両モード、M-mode 未満では MIE に依らず受理
- CLINT: msip と mtime / mtimecmp (64bit)。mtime は SoC の `i_mtime_tick` で歩進する
  ため、コアクロックではなくプラットフォームの実時間基準で数える
- PLIC: 1 コンテキスト (hart 0 の M-mode)、レベルトリガのソース 1..SRC_COUNT。
  priority / pending / enable / threshold / claim / complete を実装。claim から
  completion までゲートウェイがソースを保留するため、線を上げ続けるデバイスでも
  ハンドラ 1 回につき 1 度だけ割り込む
- 例外: 不正命令、ecall (M/U で cause 11/8)、ebreak、フェッチミスアライン、
  命令/ロード/ストアのアクセスフォルト (cause 1/5/7)
- データアクセスのミスアラインはハードウェアで処理 (2 サイクルに分割)。分割された
  両ワードの PMP を発行前に検査するため、フォルト時に部分完了しない

```
src/rv_pkg.veryl   共通定義 (リセットベクタ、misa、特権レベル、AluOp)
src/alu.veryl      ALU
src/core.veryl     コア本体 (FSM、CSR、特権、PMP、例外/割り込み、LR/SC)
src/clint.veryl    CLINT (msip、mtime / mtimecmp)
src/plic.veryl     PLIC (1 コンテキスト、レベルトリガ SRC_COUNT ソース)
src/soc.veryl      最上位。コアの単一メモリポートを分岐し、CLINT / PLIC 窓への
                   アクセスを SoC 内で完結させ、残りを外部ポートへ通す
src/tests.veryl    veryl test 用組込テスト (test_alu, test_core_smoke,
                   test_clint, test_clint_wide, test_plic, test_soc_decode)
tb/tb_plic_multi.sv 複数ソース構成の PLIC テストベンチ (make plic-multi-test)
tb/tb_core.cpp     Verilator テストベンチ。ブート ROM / RAM / 16550A UART /
                   SYSCON、HTIF tohost 判定、トレース、VCD、カバレッジ
tests/*.S          directed テスト (カバレッジ補完、割り込み、U-mode、PMP、
                   CLINT / PLIC レジスタ)
linux/             Linux ブート一式 (DTS、ビルドスクリプト)
linux/user/        freestanding ユーザランド (シェル、donut、mandelbrot)
scripts/           テスト実行・コシミュレーション・Linux 起動スクリプト
third_party/riscv-tests  (git 管理外) リビジョン固定で取得
```

## メモリマップ

CLINT と PLIC は RTL (`src/soc.veryl` が内部で応答) にあり、コアのメモリポートには
現れない。残りはテストベンチが提供する。

| アドレス | 内容 | 実装 |
|---|---|---|
| `0x0000_1000` | ブート ROM。a0=hartid, a1=DTB を設定し RAM へジャンプ | tb |
| `0x0000_2000` | DTB | tb |
| `0x0c00_0000` | PLIC (4MiB 窓。1 ソース = UART、1 コンテキスト) | RTL |
| `0x1000_0000` | 16550A UART (reg-shift=2, reg-io-width=4) | tb |
| `0x1100_0000` | CLINT (64KiB 窓。msip / mtimecmp / mtime) | RTL |
| `0x1110_0000` | SYSCON (0x5555 = poweroff, 0x7777 = reboot) | tb |
| `0x8000_0000` | RAM (`+ramsize_mb`、既定 4MiB) | tb |

PLIC のレジスタ配置は PLIC 仕様どおり (`0x000000 + 4*id` priority、`0x001000`
pending、`0x002000` enable、`0x200000` threshold、`0x200004` claim/complete)。
priority と threshold は 3bit の WARL (`PRIO_BITS`)、enable は実装済みソースの
ビットのみ書ける。CLINT は `0x0000` msip、`0x4000/0x4004` mtimecmp、
`0xbff8/0xbffc` mtime (read only)。

## ツールチェーン

コンテナ環境 (Ubuntu 24.04) で検証済みの固定バージョン。GitHub リリースから取得し
SHA256 を検証している。

| ツール | バージョン | 取得元 / SHA256 |
|---|---|---|
| Veryl | v0.20.3 | veryl-lang/veryl `veryl-x86_64-linux.zip` sha256:8e4f36919dcb676afa037867dd80e98172e2d19487825423f1fdedd1e87e9ab7 |
| Verilator | 5.051 (oss-cad-suite 2026-08-10) | YosysHQ/oss-cad-suite-build `oss-cad-suite-linux-x64-20260810.tgz` sha256:4d1137c56eaa7f2fadce7dd7f79b614cc5f7862684bcbe79765bb9a1f9037db0 |
| riscv-none-elf-gcc | 15.2.0-1 (xPack) | xpack-dev-tools/riscv-none-elf-gcc-xpack `...linux-x64.tar.gz` sha256:aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 |
| flex | 2.6.4 (カーネルビルド用) | westes/flex sha256:e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995 |
| dtc | ディストリの device-tree-compiler (無ければ dgibson/dtc 5ec18c3 = v1.7.2) | Spike のビルドと実行が要求する |
| Spike | 16c0b60 (riscv-isa-sim) | riscv-software-src/riscv-isa-sim |
| riscv-tests | 447a5fcb8253627ddb5f6a226f64e43463afcdd5 (env: 6de71edb) | riscv-software-src/riscv-tests |
| Linux | v6.12 (tag adc218676) | torvalds/linux |

`flake.nix` に nix devShell の定義を置くが、本セッションの検証環境には nix が
無いため未評価である。検証済み環境は上記の固定バイナリ構成とする。

## ビルドと検証

```bash
make all         # 下記のうち Linux 以外を全て実行する (CI と同じ内容)
make lint        # veryl fmt --check && veryl check
make veryl-test  # veryl 組込テスト (6 本)
make plic-multi-test # 複数ソース PLIC テストベンチ (単独ビルド)
make tb          # veryl build + Verilator ビルド (--coverage --trace)
make tb-fast     # 計装なしの高速モデル (Linux ブート用)
make isa-build   # riscv-tests (rv32ui/um/ua/mi の -p 76 本) をビルド
make run-isa     # 全 ISA テスト実行 -> logs/isa/summary.txt
make cov-test    # directed テスト (tests/*.S)
make coverage    # カバレッジ集計 -> logs/cov/summary.txt, logs/cov/annotated/
make cov-check   # カバレッジが規定の予算内かを判定 (超過で失敗)
make cosim       # Spike とのトレース照合 -> logs/cosim/summary.txt
make linux-build # Linux カーネル / ユーザランド / DTB のビルド
make linux-boot  # Linux 起動 (バッチ入力で mandel/donut/poweroff)
```

ツールチェーンと外部ソース (riscv-tests、Linux) は次で導入する。`/opt` と
`/usr/local/bin` に書き込み Spike をソースビルドするため、コンテナ内で実行すること。

```bash
WITH_SOURCES=1 scripts/setup_toolchain.sh
```

riscv-tests のみ手動で取得する場合 (リビジョンは上表に固定):

```bash
git clone --recurse-submodules https://github.com/riscv-software-src/riscv-tests \
    third_party/riscv-tests
git -C third_party/riscv-tests checkout 447a5fcb8253627ddb5f6a226f64e43463afcdd5
```

単体実行とログ:

```bash
scripts/run_isa.sh rv32ui-p-add               # logs/isa/ に .out / .trace.log
scripts/run_isa.sh rv32mi-p-csr +trace=w.vcd  # VCD 波形出力
scripts/run_linux.sh                          # 端末から対話的に Linux を起動
scripts/cosim.py <elf> <dut-trace> --spike-log <path>   # 単体のトレース照合
```

## CI

`.github/workflows/ci.yml` が push と pull request で `verify` ジョブを回す。
内容は `make all` と同じ (lint / veryl-test / plic-multi-test / tb / isa-build /
run-isa / cov-test / cov-check / cosim) で、`logs/` を artifact として残す。

ツールチェーンは `$HOME/toolchain` に入れて cache する。
`scripts/setup_toolchain.sh` は導入済みのものを飛ばすため、cache がヒットすれば
再取得もビルドも起きない。cache キーはスクリプト自身のハッシュなので、固定
バージョンを変えれば自動で作り直される。

Linux ブートはカーネルビルドと 8e8 サイクル級の実行で桁違いに長いため、`verify`
とは分け、週次スケジュールと `workflow_dispatch` でのみ回す `linux-boot` ジョブに
してある。

### カバレッジの予算

`scripts/cov_check.sh` は未到達点の数を metric ごとの予算と比較し、超過したら
失敗する。予算は README のこの下の「カバレッジ基準と除外理由」で構造的到達不能と
説明している点の数と一致させてある。新しく未到達を作った場合は、テストで到達させる
か、到達不能である根拠を README に追記した上で同じコミットで予算を上げること。

## veryl test と Verilator の多重トップ

`veryl test` は設計一式をテストベンチと一緒に Verilator へ渡すため、どこからも
インスタンス化されていない設計モジュールが追加のトップになる。トップが複数ある
状態では `rv32ima_Plic` の特殊化が 1 回しか行われず、`SRC_COUNT` を上書きした
テストベンチが黙ってプラットフォームの値 (1) で動いてしまう。

このため複数ソース構成のテストだけは `src/tests.veryl` に置かず、
`tb/tb_plic_multi.sv` として `--top-module` を明示し必要なファイルだけを渡して
単独でビルドする (`make plic-multi-test`)。上書きが効いていることは、
4 ソース構成でしか成立しない enable マスク `0x1e` の検査で担保している。

## Spike コシミュレーション

本コアのリタイアトレースと Spike の実行ログは同一の行形式であり、
`scripts/cosim.py` が両者を正規化して命令列を照合する。Spike はトラップした命令も
ログに出力するため、例外行の `epc` が直前命令の PC と一致する場合のみその命令を
除去する (命令アクセスフォルトは分岐先に対して報告されるため、分岐自体はリタイア
済みとして残す)。テストベンチは tohost 書き込みで即座に停止するのに対し Spike は
ハーネスの待機ループを回り続けるため、DUT 側が短いことは許容し、長い場合のみ
不一致とする。

Spike には `--isa=rv32ima_zicsr_zicntr_zifencei_zicclsm --priv=mu` を与える。
Zicclsm はミスアラインアクセスをハードウェアで完了させる指定で、これが無いと
Spike 側だけがトラップして全ミスアラインテストで差分が出る。

除外しているものと理由:

- `rv32mi-p-breakpoint` — Spike は任意拡張である Sdtrig のトリガを実装するが本コアは
  実装しない (tselect が非ゼロを返す)。両者とも仕様上正しく、経路が分岐する
- `coverage_boost` — 実装定義の WARL マスクを検査し、かつ wfi を実行する
  (割り込み源の無い Spike は wfi で停止しない)
- `irq_test`、`clint_plic_test` — 本プラットフォーム固有の CLINT / PLIC を直接操作
  する。Spike は別のプラットフォームをモデル化しており、これらのアドレスに同じ
  デバイスは無い

## Linux ブートとユーザアプリケーション

NOMMU / M-mode カーネル (RV32, binfmt_elf_fdpic) を `linux/build_linux.sh` で
ソースからビルドする。ユーザランドは libc を用いない freestanding 実装で、
`/init` が簡易シェル、`/bin/donut` と `/bin/mandelbrot` を別プロセスとして
`clone(CLONE_VM|CLONE_VFORK)` + `execve` で起動する。

```bash
LINUX_SRC=$HOME/src/linux make linux-build
make linux-boot          # バッチ入力で mandel / donut / poweroff を実行
scripts/run_linux.sh     # 端末から対話的に操作
```

シェルのコマンド: `donut` `mandel` `help` `poweroff` `reboot`

FPU が無いため donut / mandelbrot はいずれも Q16.16 固定小数点で実装している
(`linux/user/fixed.h`)。sin は象限還元と 5 次テイラー展開、32x32→64 の乗算は
mul/mulh の明示記述、除算は 32bit に収める形で、libgcc も libm も使用しない。

シミュレーション上での実測 (Verilator、計装なし、1 コア):

| 項目 | 値 |
|---|---|
| ブート〜ユーザ空間到達 | 約 6.5e7 サイクル |
| mandelbrot + donut + poweroff まで | 1.0e9 サイクル / 3.6e8 命令 |
| 実行速度 | 約 6 Mcycles/s (約 2.3 MIPS) |

`make linux-boot` の総サイクル数は run ごとに数 % ぶれる。バッチ入力が実時間の
sleep で与えられるため、シェルが次のコマンドを待って回すアイドルループの長さが
run ごとに変わるためである。

除算を逐次化する前の同じ測定は 8.2e8 サイクル / 3.2e8 命令であった。donut と
mandelbrot は Q16.16 の除算を含むため、除算 1 命令あたり 33 サイクルという代償が
ここに現れる。命令数の増加は、実行が長くかかることでアイドルループの回転数が
増えたためである。

### mtimediv について

`+mtimediv` は mtime 1 カウントあたりのコアサイクル数を指定する。DTS の
`timebase-frequency = 1000000` と HZ=100 のため、タイマ tick 周期は 10000 mtime
カウントである。`mtimediv=1` ではこれが 10000 サイクルとなり tick ハンドラの
実行コストを下回るため、カーネルがタイマ割り込み処理で livelock し、起動が
進まなくなる。`mtimediv=64` (tick あたり 64 万サイクル) を既定とする。

### ユーザランドが PIE である必要性

`binfmt_elf_fdpic` はエントリ再配置を `e_entry != 0` の場合のみ行う
(`fs/binfmt_elf_fdpic.c`)。このため各バイナリは VMA 0 ではなく `0x1000` を基点に
リンクし、ELF ヘッダの `e_type` を ET_DYN へ書き換えている (bare-metal ld に
`-pie` が無いため)。さらに C コードは `-fPIE -mno-relax -msmall-data-limit=0` で
コンパイルし、全参照を pc 相対 (auipc 基準) に保つ。絶対アドレス指定や gp 相対
指定が混入すると、ロード先が異なるため動作しない。

## 検証結果

- riscv-tests: rv32ui 42 / rv32um 8 / rv32ua 10 / rv32mi 16 の全 76 本 PASS
- directed テスト 5 本 PASS (coverage_boost / irq_test / umode_test / pmp_test /
  clint_plic_test)
- veryl test: 6 本 PASS (組込 SV テストベンチ)。加えて複数ソース PLIC の
  テストベンチ 1 本 (`make plic-multi-test`)
- Spike コシミュレーション: 77 件で命令列完全一致、4 件 SKIP (breakpoint と
  プラットフォーム依存の directed テスト 3 本)
- Linux v6.12 (rv32 NOMMU): ユーザ空間到達、シェル、別プロセスでの
  mandelbrot / donut 実行、syscon 経由の poweroff まで確認。タイマ tick と UART の
  外部割り込みはいずれも RTL の CLINT / PLIC 経由である
- カバレッジ (riscv-tests 76 本 + directed 5 本の合算):
  line 98.6% (280/284)、branch 98.6% (142/144)、expr 94.7% (230/243)、
  toggle 73.4% (5685/7750)

### カバレッジ基準と除外理由

line の未到達 4 箇所 (branch は 2 箇所) は構造的到達不能であり、これを除くと到達可能
行は全て実行済みである。

1. `alu_op` の case default: funct3 は 3bit 全 8 値を列挙済み。網羅性要件のための
   防御的 default。
2. `md_res` の case default: 同上。
3. `amo_result` の default 節: q_amo_op が AMO RMW 以外の値になるのは LR/SC/load/
   store の発行時のみで、その場合 `amo_result` は消費されない (q_is_amo=1 は正規
   RMW funct5 を含意する)。
4. `always_ff` の state case default: 到達可能な状態は 5 値のみ。3bit エンコードの
   残余に対する防御的回復。

expr の未到達には上記に加え、PLIC の claim 選択 `eligible[i+1] && prio[i] > claim_best`
で「eligible だが優先度が現最良を超えない」組合せが 1 点残る。`SRC_COUNT = 1` では
ループが 1 回しか回らず `claim_best` は常に 0、eligible は `prio > threshold >= 0` を
含意するため、この組合せは構造的に生じない。複数ソース構成では到達する。

toggle の残余 (約 2100/7750 点) は次の構造的要因によるもので、機能の未検証を
示さない。

- WARL で 0 固定のビット: mie (0x888 以外)、mcounteren (下位 3bit 以外)、
  pmpcfg の予約ビット、mstatus の予約ビット、csr_uimm 上位 27bit、cause の上位ビット、
  PLIC の priority / threshold の上位 29bit (`PRIO_BITS = 3`)、pending / enable /
  claimed のうち実装済みソース以外のビット、CLINT の mtime / mtimecmp 上位ワード
- メモリマップ由来の定数: テストベンチの RAM 配置により pc / メモリアドレス系の
  bit30:22 が常時 0
- 命令フォーマット由来の定数: imm_u 下位 12bit 等

## FPGA ポーティング例

`fpga/` に Digilent Arty A7-35 (Xilinx XC7A35T) への移植例を置く。合成・配置配線・
ビットストリーム生成はすべてオープンツールで行い、ベンダ IDE は使わない。

### 構成

シミュレーション用テストベンチ (`tb/tb_core.cpp`) が C++ で提供していた ROM / RAM /
UART を RTL 化し、`FpgaSoc` にまとめてある。ボード側に残るのはピンとクロックだけで
ある。

```
src/uart.veryl        16550 互換 UART (8N1、16 byte 受信 FIFO、divisor latch)
src/ram.veryl         byte enable 付き単一ポート RAM ($readmemh で初期化)
src/power_on_reset.veryl  コンフィグ後 256 クロックのリセット
src/fpga_soc.veryl    Soc + ブートスタブ + RAM + UART + mtime tick 生成
fpga/firmware/        ベアメタルのデモ (UART / CLINT タイマ / PLIC 外部割り込み)
fpga/arty_a7/         トップと XDC
```

メモリマップはシミュレーション側と同一で、CLINT (`0x1100_0000`) と PLIC
(`0x0c00_0000`) は `Soc` が内部で応答し、`FpgaSoc` はブートスタブ (`0x0000_1000`)、
UART (`0x1000_0000`)、RAM (`0x8000_0000`、64KiB) を足す。

| 項目 | 値 |
|---|---|
| SoC クロック | 25 MHz (基板の 100 MHz を ÷4) |
| ボーレート | 57870 (host 57600、+0.5%) 8N1 |
| RAM | 64 KiB (オンチップ) |

### 使い方

```bash
make fpga-sim         # ボード非依存の検証 (下記)
make fpga-arty        # -> sim/fpga/arty/soc.bit
make fpga-arty-prog   # 上記 + openFPGALoader で書き込み
```

合成は `scripts/setup_toolchain.sh` が入れる oss-cad-suite だけで完結する。配置配線
には nextpnr-xilinx が要るが oss-cad-suite に含まれないため、
[openXC7](https://github.com/openXC7) を導入し `NEXTPNR_XILINX_CHIPDB` と
`PRJXRAY_DB` を指定する (未指定なら合成まで実行し、案内を出して止まる)。

生成 SV は yosys 標準フロントエンドでは読めない (Veryl が関数引数に
`input var logic` を出す) ため、合成は `yosys -m slang` + `read_slang` で行う。

### クロックを下げてある理由

このコアの M 拡張は除算を単一サイクルの組合せ回路で行うため、そこがクリティカル
パスになる。基板の 100 MHz では到底閉じないので ÷4 の 25 MHz で動かす。Artix-7 での
実測値は本リポジトリの検証環境では取れていない (配置配線に openXC7 が必要) ため、
これは保守的な初期値である。スラックに余裕があれば `CLK_DIV_LOG2` を 1 に下げて
50 MHz にできる。

ボーレートは 16550 の divisor latch をそのまま使い、UART の基準クロックを SoC の
クロックとしている。25 MHz からの誤差は +0.5% で、8N1 のフレーミングが吸収できる
範囲である。

### 検証状況

- `make fpga-sim` — **実施**。`FpgaSoc` を Verilator で回し、UART の送信線から
  コンソールを復号する。設計内部を覗かずボードと同じ 2 本の線だけを見るので、
  ボーレート生成が壊れれば文字化けとして現れる。ファームウェアのバナー、CLINT の
  タイマ割り込み、PLIC 経由の UART 受信割り込み (打鍵のエコー) までを確認する
- yosys 合成 — **実施**。LUT 15644 / 20800、RAMB36 16 / 50、DSP48E1 10 / 90 で
  XC7A35T に収まる
- 配置配線とビットストリーム生成 — **未実施**。openXC7 が必要で、本リポジトリの
  検証環境には導入できていない
- **実機動作は未確認である**。ピン配置は Digilent の Arty-A7-35-Master.xdc から
  取っており、目視照合しかしていない

### FPGA 例の制限

- 外部 DRAM は繋いでいないため RAM はオンチップの 64KiB のみ。Linux は載らず、
  ベアメタル専用である
- 除算器が単一サイクルの組合せ回路であることが動作周波数と面積の両方を律速する。
  多サイクル化すれば両方改善するが、それはコアの変更になるためこの例では触れて
  いない

## 既知の制限

- S-mode と MMU は実装しない (NOMMU 構成のみ)
- Sdtrig (デバッグトリガ) は実装しない。tselect は非ゼロを返し「トリガ無し」を示す
- PLIC は 1 コンテキスト固定。`Plic` のソース数は `SRC_COUNT` パラメータで変えられる
  が、レジスタは 32bit 1 ワード分なので最大 31 ソース。本プラットフォームが繋ぐ本数は
  `RvPkg::PLIC_SRC_COUNT` (= 1、UART) で、SoC の `i_irq_src` 幅と PLIC への引き渡しは
  そこから決まる。DTS の `riscv,ndev` と揃えること
- CLINT は 1 hart 固定。mtime の歩進はプラットフォームが `i_mtime_tick` で与える
- UART と SYSCON はテストベンチ (C++) 側のままである

## ライセンス

third_party/riscv-tests は上流の LICENSE (BSD) に従う。Linux カーネルは上流の
ライセンス (GPL-2.0) に従い、本リポジトリにはソースを含まない。
