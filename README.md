# rv32ima_veryl

Veryl による RV32IMA_Zicsr (M-mode のみ) コアの実装と検証環境。

## 構成

- コア: マルチサイクル (fetch / execute / mem_access / mem_access2 / amo_write)、
  単一 32bit メモリポート (valid/ready、wstrb=0 で read)
- RV32I 全命令、M (MUL/DIV 系)、A (LR/SC, AMO 9 種)、Zicsr、M-mode CSR、
  例外 (不正命令、ecall、ebreak、フェッチミスアライン) と mret
- データアクセスのミスアラインはハードウェアで処理 (2 分割アクセス)。
  AMO/LR/SC のミスアラインは例外 (cause 4/6)
- 制御移行先がミスアラインの場合は分岐命令側で例外 (cause 0、mtval=target)

```
src/rv_pkg.veryl   共通定義 (リセットベクタ、misa、AluOp)
src/alu.veryl      ALU
src/core.veryl     コア本体 (FSM、CSR、例外、LR/SC)
src/tests.veryl    veryl test 用組込テスト (test_alu, test_core_smoke)
tb/tb_core.cpp     Verilator テストベンチ (メモリモデル、HTIF tohost 判定、
                   トレースログ、VCD、カバレッジ出力)
tests/coverage_boost.S  カバレッジ補完の directed テスト
scripts/           テスト列挙・実行スクリプト
third_party/riscv-tests  (git 管理外) リビジョン固定で取得
```

## ツールチェーン

コンテナ環境 (Ubuntu 24.04) で検証済みの固定バージョン。いずれも GitHub リリース
から取得し SHA256 を検証している。

| ツール | バージョン | 取得元 / SHA256 |
|---|---|---|
| Veryl | v0.20.3 | veryl-lang/veryl `veryl-x86_64-linux.zip` sha256:8e4f36919dcb676afa037867dd80e98172e2d19487825423f1fdedd1e87e9ab7 |
| Verilator | 5.051 (oss-cad-suite 2026-08-10) | YosysHQ/oss-cad-suite-build `oss-cad-suite-linux-x64-20260810.tgz` sha256:4d1137c56eaa7f2fadce7dd7f79b614cc5f7862684bcbe79765bb9a1f9037db0 |
| riscv-none-elf-gcc | 15.2.0-1 (xPack) | xpack-dev-tools/riscv-none-elf-gcc-xpack `...linux-x64.tar.gz` sha256:aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 |
| riscv-tests | 447a5fcb8253627ddb5f6a226f64e43463afcdd5 (env: 6de71edb) | riscv-software-src/riscv-tests |

`flake.nix` に nix devShell の定義を置くが、本セッションの検証環境には nix が
無いため未評価である。検証済み環境は上記の固定バイナリ構成とする。

## ビルドと検証

```bash
make lint        # veryl fmt --check && veryl check
make veryl-test  # veryl 組込テスト (test_alu, test_core_smoke)
make tb          # veryl build + Verilator ビルド (--coverage --trace)
make isa-build   # riscv-tests (rv32ui/um/ua/mi の -p 76 本) をビルド
make run-isa     # 全 ISA テスト実行 -> logs/isa/summary.txt
make cov-test    # directed テスト (tests/coverage_boost.S)
make coverage    # カバレッジ集計 -> logs/cov/summary.txt, logs/cov/annotated/
```

riscv-tests は次で取得する (リビジョンは上表に固定):

```bash
git clone --recurse-submodules https://github.com/riscv-software-src/riscv-tests \
    third_party/riscv-tests
git -C third_party/riscv-tests checkout 447a5fcb8253627ddb5f6a226f64e43463afcdd5
```

単体実行とログ:

```bash
scripts/run_isa.sh rv32ui-p-add               # logs/isa/ に .out / .trace.log
scripts/run_isa.sh rv32mi-p-csr +trace=w.vcd  # VCD 波形出力
```

## 検証結果

- riscv-tests: rv32ui 42 / rv32um 8 / rv32ua 10 / rv32mi 16 の全 76 本 PASS
- veryl test: 2 本 PASS (組込 SV テストベンチ)
- カバレッジ (riscv-tests 76 本 + coverage_boost の合算):
  line 97.8% (180/184)、branch 97.8% (90/92)、expr 96.3% (131/136)、
  toggle 85.9% (4214/4904)

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

toggle の残余 (690/4904 点) は次の構造的要因によるもので、機能の未検証を示さない。

- WARL で 0 固定のビット: mie (0x888 以外)、mcountinhibit (CY/IR 以外)、mstatus の
  予約ビットと MPP=11 固定、csr_uimm 上位 27bit、例外 cause の未使用上位ビット等
- メモリマップ由来の定数: 4MiB @ 0x8000_0000 のため pc / メモリアドレス系の
  bit31 (1→0 なし) と bit30:22 (常時 0)
- 命令フォーマット由来の定数: imm_u 下位 12bit 等

## ライセンス

third_party/riscv-tests は上流の LICENSE (BSD) に従う。
