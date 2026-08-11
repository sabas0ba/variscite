# CLAUDE.md

Claude Code が本リポジトリで作業する際の補足。構成、メモリマップ、ツールチェーンの
固定バージョン、ビルド・検証手順、カバレッジ基準、Linux ブート手順は
[README.md](README.md) に定義してある。重複記述はしない。

## 作業環境

- 検証済み環境は README.md 記載の固定バイナリ構成 (Veryl v0.20.3 / Verilator 5.051
  / xPack riscv-none-elf-gcc 15.2.0-1)。nix が利用可能な環境では `flake.nix` の
  devShell を用いる (未評価につき、初回利用時は動作確認から行うこと)
- `third_party/riscv-tests` と Linux ソースは git 管理外。無い場合は README.md の
  手順でリビジョン固定で取得する

## 変更後の検証

コア (`src/*.veryl`) に触れた場合、以下を全て通すこと。検査を通すために検査自体を
弱めない。

```bash
make lint && make veryl-test && make tb && make run-isa && make cov-test \
  && make coverage && make cosim
```

- `make run-isa` は 76 本全 PASS が合格条件 (logs/isa/summary.txt)
- `make cosim` は 77 件全一致が合格条件 (logs/cosim/summary.txt)。除外を増やす
  場合は仕様上の根拠を README.md に明記する。トレース照合は `make run-isa` と
  `make cov-test` の出力を使うため、先にそれらを実行しておくこと
- カバレッジは line で新たな未到達を作らないこと。除外は README.md の除外理由に
  追記し根拠を明記する
- 特権・割り込み・メモリ順序に関わる変更は `make linux-boot` まで通す。Linux は
  riscv-tests が検出しない実装漏れ (U-mode 復帰、タイマ tick、UART の DLAB、
  ユーザランドの PIC 化など) を露出させるため、リグレッションとしての価値が高い

## 注意事項

- 一時ファイル・ログは git ignore 済みの `logs/` `sim/` に置く
- 生成 SV (`target/`) は成果物ではない。手編集しない
- コミットは Conventional Commits
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
