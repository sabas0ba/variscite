# CLAUDE.md

Claude Code が本リポジトリで作業する際の補足。構成、メモリマップ、ツールチェーンの
固定バージョン、ビルド・検証手順、カバレッジ基準、Linux ブート手順は
[README.md](README.md) に定義してある。重複記述はしない。

## 初回セットアップ

本リポジトリは git bundle で受け渡されることがある。その場合は次で復元する。

```bash
git clone variscite.bundle rv32ima_veryl
cd rv32ima_veryl
```

ツールチェーンと外部ソースは git 管理外である。`container/Containerfile` が
`scripts/setup_toolchain.sh` を実行して固定バージョンを導入する。

```bash
podman build -t variscite-dev -f container/Containerfile .
podman run --rm -v "$PWD:/work" variscite-dev env WITH_TESTS=1 scripts/setup_toolchain.sh
```

導入されるもの (バージョンと SHA256 は README.md の表と一致させること):
Veryl / Verilator (oss-cad-suite) / xPack riscv-none-elf-gcc / flex / Spike、
および `third_party/riscv-tests` と Linux ソース。

## 作業環境

- **ビルドと検証はすべて `container/Containerfile` のコンテナ内で行う。** Windows
  ホストでは Smart App Control が未署名バイナリ (veryl.exe、verilator、nextpnr) の
  実行を止めるため、ホストで直接動かそうとしないこと。Windows からは
  `scripts/dev.ps1 <command>` が中継する
- 例外は基板への書き込みだけで、コンテナから USB デバイスに届かないため
  `scripts/flash.ps1` と `scripts/uart-term.ps1` がホスト側で動く。これらが使う
  Windows 版 oss-cad-suite は `scripts/setup-toolchain.ps1` が `tools/` に入れる
- 検証済み環境は README.md 記載の固定バイナリ構成 (Veryl v0.20.3 / Verilator 5.051
  / xPack riscv-none-elf-gcc 15.2.0-1)。nix が利用可能な環境では `flake.nix` の
  devShell を用いる (未評価につき、初回利用時は動作確認から行うこと)
- Linux ソースの位置は `LINUX_SRC` で指定する (コンテナ内では `/opt/src/linux`)
- 作業ツリーは `.gitattributes` で LF に固定してある。CRLF が混ざるとコンテナ内で
  shebang も make のレシピも壊れる。エディタやスクリプトで CR を書き込まないこと

## 変更後の検証

コア (`src/*.veryl`) に触れた場合、以下を全て通すこと。検査を通すために検査自体を
弱めない。

```bash
make all
```

これは CI (`.github/workflows/ci.yml` の `verify` ジョブ) と同じ内容である
(lint / veryl-test / plic-multi-test / tb / isa-build / run-isa / cov-test /
cov-check / cosim)。

- `make run-isa` は 76 本全 PASS が合格条件 (logs/isa/summary.txt)
- `make cosim` は 77 件全一致が合格条件 (logs/cosim/summary.txt)。除外を増やす
  場合は仕様上の根拠を README.md に明記する。トレース照合は `make run-isa` と
  `make cov-test` の出力を使うため、先にそれらを実行しておくこと
- カバレッジは `make cov-check` が予算 (line 4 / branch 2 / expr 13) で判定する。
  新たな未到達を作らないこと。どうしても到達不能な場合は README.md の除外理由に
  根拠を追記し、同じコミットで `scripts/cov_check.sh` の予算を上げる
- 特権・割り込み・メモリ順序に関わる変更は `make linux-boot` まで通す。Linux は
  riscv-tests が検出しない実装漏れ (U-mode 復帰、タイマ tick、UART の DLAB、
  ユーザランドの PIC 化など) を露出させるため、リグレッションとしての価値が高い

## 注意事項

- 一時ファイル・ログは git ignore 済みの `logs/` `sim/` に置く
- 生成 SV (`target/`) は成果物ではない。手編集しない
- コミットは Conventional Commits
- Verilator の最上位は `rv32ima_Soc` (`src/soc.veryl`)。CLINT と PLIC は RTL 側に
  あり、コアのメモリポートには現れない。テストベンチが供給するのは ROM / RAM /
  UART / SYSCON と、`i_mtime_tick` (mtime の歩進) および `i_irq_src` (UART の線) の
  2 本の入力だけである
- 新しいデバイスを RTL に足す場合、アドレス窓の分岐は `src/soc.veryl` の
  `*_hit` / `*_sel` に、ゲスト側の見え方は `linux/rv32ima_veryl.dts` に、
  レジスタレベルの検査は `tests/clint_plic_test.S` と `src/tests.veryl` の
  組込テストに、それぞれ追加する。窓の外へ素通しされることは
  `test_soc_decode` に倣って検査する
- FPGA 例 (`fpga/`) は Tang Primer 20K と Arty A7-35 の 2 枚。ボード側の差は
  パラメタだけで、コア自体はどちらも同じものが載る。`src/uart.veryl` `src/ram.veryl`
  `src/fpga_soc.veryl` はシミュレーション用テストベンチが C++ で持っていた周辺を
  RTL 化したもので、変更したら `make fpga-sim` を通すこと。これは実機に触らずに
  UART のボーレート生成・RAM・ブートスタブまで検査する唯一の手段である
- ビットストリームまで生成できるのは Tang だけである (`make fpga-tang`)。Arty は
  配置配線に openXC7 が要り、コンテナに入れていないため合成で止まる
- FPGA 用 RTL は `make tb` のカバレッジ対象 (`$(RTL)`) に入れていない。入れると
  カバレッジ予算が変わるので、追加する場合は `scripts/cov_check.sh` も併せて直す
- 生成 SV は yosys 標準フロントエンドでは読めない (Veryl が関数引数に
  `input var logic` を出すため)。合成は `yosys -m slang` + `read_slang` を使う
- コアの M 拡張の除算は逐次 (復元法、33 サイクル、`State::divide`)。以前は単一
  サイクルの組合せ回路で、FPGA でのクリティカルパスだったため置き換えた。乗算は
  単一サイクルのままで、DSP に載るので問題にならない
- FPGA での最大の面積要因は除算器ではなく **PMP** である。`pmp_entry` が 3 インスタンス
  あり、各々が全エントリぶんの比較器と NAPOT マスク生成を持つ。`Core` の
  `PMP_ENTRIES` (既定 16) で減らせる。実測は README.md の「面積を詰めた経緯」にある。
  面積の主張をする前に必ず測ること。ここは一度、除算器を主因と誤認している
- モジュールパラメータを上書きするテストベンチは `src/tests.veryl` に置かない。
  `veryl test` の多重トップ下では上書きが効かず、黙って既定値で通ってしまう。
  `tb/tb_plic_multi.sv` と `make plic-multi-test` のように単独ビルドする
  (理由は README.md の該当節)
- 例外の意味論 (ミスアライン分岐は分岐命令側で trap、データミスアラインは HW 処理、
  AMO 系は trap) は riscv-tests (ma_fetch / ma_data / ma_addr) の要求に基づく。
  変更時は該当テストの意図を先に確認する
- U-mode を実装済みのため、riscv-tests の rv32ui/um/ua は U-mode で実行される
  (`riscv_test.h` の reset_vector が mstatus を 0 クリアしてから mret するため)。
  misa.U を落とすと rv32mi-p-csr / scall の期待経路が変わる
- PMP はアクセス制御まで実装済み。riscv-tests の `INIT_PMP` と Linux の head.S は
  いずれもエントリ 0 を全許可に設定するため、既定では素通しになる。エントリの
  優先順位 (低番号優先)、非マッチ時の M-mode 許可、L bit の M-mode 適用と書き込み
  凍結を変更する場合は `tests/pmp_test.S` を先に確認する
- ユーザランド (`linux/user/`) は libc も libgcc も使わない。新しいコードで
  64bit 除算や math 関数を呼ぶとリンクが通らない (ビルドスクリプトが未定義シンボル
  を検査する)。固定小数点ヘルパは `linux/user/fixed.h` に置く
