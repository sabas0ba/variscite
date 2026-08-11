# rv32ima_veryl

Veryl による RV32IMA_Zicsr コア (M/U-mode、PMP、NOMMU) の実装と検証環境。
riscv-tests の全件通過、Spike とのコシミュレーション一致、Verilator シミュレーション
上での Linux 起動とユーザアプリケーションの実行までを含む。

## 構成

- コア: マルチサイクル (fetch / execute / mem_access / mem_access2 / amo_write)、
  単一 32bit メモリポート (valid/ready、wstrb=0 で read)
- RV32I 全命令、M (MUL/DIV 系)、A (LR/SC, AMO 9 種)、Zicsr
- 特権: M-mode と U-mode。mstatus.MPP、mcounteren によるカウンタ許可、CSR の特権
  チェック、U-mode からの特権命令の不正命令例外
- PMP: 16 エントリ。OFF/TOR/NA4/NAPOT、R/W/X、L bit (ロック時は M-mode にも適用し、
  当該 cfg と address の書き込みを凍結)。非マッチ時は M-mode 許可 / U-mode 拒否
- 割り込み: machine timer / software / external (PLIC 経由)。mie/mip、mstatus.MIE、
  mtvec の direct / vectored 両モード、M-mode 未満では MIE に依らず受理
- 例外: 不正命令、ecall (M/U で cause 11/8)、ebreak、フェッチミスアライン、
  命令/ロード/ストアのアクセスフォルト (cause 1/5/7)
- データアクセスのミスアラインはハードウェアで処理 (2 サイクルに分割)。分割された
  両ワードの PMP を発行前に検査するため、フォルト時に部分完了しない

```
src/rv_pkg.veryl   共通定義 (リセットベクタ、misa、特権レベル、AluOp)
src/alu.veryl      ALU
src/core.veryl     コア本体 (FSM、CSR、特権、PMP、例外/割り込み、LR/SC)
src/tests.veryl    veryl test 用組込テスト (test_alu, test_core_smoke)
tb/tb_core.cpp     Verilator テストベンチ。ブート ROM / RAM / PLIC / CLINT /
                   16550A UART / SYSCON、HTIF tohost 判定、トレース、VCD、カバレッジ
tests/*.S          directed テスト (カバレッジ補完、割り込み、U-mode、PMP)
linux/             Linux ブート一式 (DTS、ビルドスクリプト)
linux/user/        freestanding ユーザランド (シェル、donut、mandelbrot)
scripts/           テスト実行・コシミュレーション・Linux 起動スクリプト
third_party/riscv-tests  (git 管理外) リビジョン固定で取得
```

## メモリマップ (テストベンチ)

| アドレス | 内容 |
|---|---|
| `0x0000_1000` | ブート ROM。a0=hartid, a1=DTB を設定し RAM へジャンプ |
| `0x0000_2000` | DTB |
| `0x0c00_0000` | PLIC (1 ソース = UART、1 コンテキスト) |
| `0x1000_0000` | 16550A UART (reg-shift=2, reg-io-width=4) |
| `0x1100_0000` | CLINT msip |
| `0x1100_4000` | CLINT mtimecmp |
| `0x1100_bff8` | CLINT mtime (read only) |
| `0x1110_0000` | SYSCON (0x5555 = poweroff, 0x7777 = reboot) |
| `0x8000_0000` | RAM (`+ramsize_mb`、既定 4MiB) |

## ツールチェーン

コンテナ環境 (Ubuntu 24.04) で検証済みの固定バージョン。GitHub リリースから取得し
SHA256 を検証している。

| ツール | バージョン | 取得元 / SHA256 |
|---|---|---|
| Veryl | v0.20.3 | veryl-lang/veryl `veryl-x86_64-linux.zip` sha256:8e4f36919dcb676afa037867dd80e98172e2d19487825423f1fdedd1e87e9ab7 |
| Verilator | 5.051 (oss-cad-suite 2026-08-10) | YosysHQ/oss-cad-suite-build `oss-cad-suite-linux-x64-20260810.tgz` sha256:4d1137c56eaa7f2fadce7dd7f79b614cc5f7862684bcbe79765bb9a1f9037db0 |
| riscv-none-elf-gcc | 15.2.0-1 (xPack) | xpack-dev-tools/riscv-none-elf-gcc-xpack `...linux-x64.tar.gz` sha256:aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 |
| flex | 2.6.4 (カーネルビルド用) | westes/flex sha256:e87aae032bf07c26f85ac0ed3250998c37621d95f8bd748b31f15b33c45ee995 |
| Spike | 16c0b60 (riscv-isa-sim) | riscv-software-src/riscv-isa-sim |
| riscv-tests | 447a5fcb8253627ddb5f6a226f64e43463afcdd5 (env: 6de71edb) | riscv-software-src/riscv-tests |
| Linux | v6.12 (tag adc218676) | torvalds/linux |

`flake.nix` に nix devShell の定義を置くが、本セッションの検証環境には nix が
無いため未評価である。検証済み環境は上記の固定バイナリ構成とする。

## ビルドと検証

```bash
make lint        # veryl fmt --check && veryl check
make veryl-test  # veryl 組込テスト (test_alu, test_core_smoke)
make tb          # veryl build + Verilator ビルド (--coverage --trace)
make tb-fast     # 計装なしの高速モデル (Linux ブート用)
make isa-build   # riscv-tests (rv32ui/um/ua/mi の -p 76 本) をビルド
make run-isa     # 全 ISA テスト実行 -> logs/isa/summary.txt
make cov-test    # directed テスト (tests/*.S)
make coverage    # カバレッジ集計 -> logs/cov/summary.txt, logs/cov/annotated/
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
- `irq_test` — 本プラットフォーム固有の CLINT / PLIC を直接操作する

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
| ブート〜ユーザ空間到達 | 約 7.6e7 サイクル |
| mandelbrot + donut + poweroff まで | 7.6e8 サイクル / 2.9e8 命令 |
| 実行速度 | 約 6 Mcycles/s (約 2.3 MIPS) |

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
- directed テスト 4 本 PASS (coverage_boost / irq_test / umode_test / pmp_test)
- veryl test: 2 本 PASS (組込 SV テストベンチ)
- Spike コシミュレーション: 77 件で命令列完全一致、1 件 SKIP (breakpoint)
- Linux v6.12 (rv32 NOMMU): ユーザ空間到達、シェル、別プロセスでの
  mandelbrot / donut 実行、syscon 経由の poweroff まで確認
- カバレッジ (riscv-tests 76 本 + directed 4 本の合算):
  line 98.3% (226/230)、branch 98.3% (118/120)、expr 94.2% (196/208)、
  toggle 80.3% (4589/5718)

### カバレッジ基準と除外理由

line/branch の未到達 4 箇所は構造的到達不能であり、これを除くと到達可能行は全て
実行済みである。

1. `alu_op` の case default: funct3 は 3bit 全 8 値を列挙済み。網羅性要件のための
   防御的 default。
2. `md_res` の case default: 同上。
3. `amo_result` の default 節: q_amo_op が AMO RMW 以外の値になるのは LR/SC/load/
   store の発行時のみで、その場合 `amo_result` は消費されない (q_is_amo=1 は正規
   RMW funct5 を含意する)。
4. `always_ff` の state case default: 到達可能な状態は 5 値のみ。3bit エンコードの
   残余に対する防御的回復。

toggle の残余 (約 1100/5718 点) は次の構造的要因によるもので、機能の未検証を
示さない。

- WARL で 0 固定のビット: mie (0x888 以外)、mcounteren (下位 3bit 以外)、
  pmpcfg の予約ビット、mstatus の予約ビット、csr_uimm 上位 27bit、cause の上位ビット
- メモリマップ由来の定数: テストベンチの RAM 配置により pc / メモリアドレス系の
  bit30:22 が常時 0
- 命令フォーマット由来の定数: imm_u 下位 12bit 等

## 既知の制限

- S-mode と MMU は実装しない (NOMMU 構成のみ)
- Sdtrig (デバッグトリガ) は実装しない。tselect は非ゼロを返し「トリガ無し」を示す
- PLIC は 1 ソース / 1 コンテキストの簡略実装 (テストベンチ側)

## ライセンス

third_party/riscv-tests は上流の LICENSE (BSD) に従う。Linux カーネルは上流の
ライセンス (GPL-2.0) に従い、本リポジトリにはソースを含まない。
