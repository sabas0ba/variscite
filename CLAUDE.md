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
make lint && make veryl-test && make tb && make run-isa && make cov-test && make coverage
```

- `make run-isa` は 76 本全 PASS が合格条件 (logs/isa/summary.txt)
- カバレッジは line で新たな未到達を作らないこと。除外は README.md の除外理由に
  追記し根拠を明記する
- 特権・割り込み・メモリ順序に関わる変更は `make linux-boot` まで通す。Linux は
  riscv-tests が検出しない実装漏れ (U-mode 復帰、タイマ tick、UART の DLAB 等) を
  露出させるため、リグレッションとしての価値が高い

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
- PMP は CSR として存在するだけで、アクセス制御は行わない (テスト・Linux とも
  全許可設定で使用するため)。実効的な保護が必要になった場合は明示的に実装する
