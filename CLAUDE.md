# CLAUDE.md

Claude Code が本リポジトリで作業する際の補足。構成、ツールチェーンの固定
バージョン、ビルド・検証手順、カバレッジ基準は [README.md](README.md) に定義して
ある。重複記述はしない。

## 作業環境

- 検証済み環境は README.md 記載の固定バイナリ構成 (Veryl v0.20.3 / Verilator 5.051
  / xPack riscv-none-elf-gcc 15.2.0-1)。nix が利用可能な環境では `flake.nix` の
  devShell を用いる (未評価につき、初回利用時は動作確認から行うこと)
- `third_party/riscv-tests` は git 管理外。無い場合は README.md の手順で
  リビジョン固定で取得する

## 変更後の検証

コア (`src/*.veryl`) に触れた場合、以下を全て通すこと。検査を通すために検査自体を
弱めない。

```bash
make lint && make veryl-test && make tb && make run-isa && make cov-test && make coverage
```

- `make run-isa` は 76 本全 PASS が合格条件 (logs/isa/summary.txt)
- カバレッジは line で新たな未到達を作らないこと。除外は README.md の除外理由に
  追記し根拠を明記する

## 注意事項

- 一時ファイル・ログは git ignore 済みの `logs/` `sim/` に置く
- 生成 SV (`target/`) は成果物ではない。手編集しない
- コミットは Conventional Commits
- 例外の意味論 (ミスアライン分岐は分岐命令側で trap、データミスアラインは HW 処理、
  AMO 系は trap) は riscv-tests (ma_fetch / ma_data / ma_addr) の要求に基づく。
  変更時は該当テストの意図を先に確認する
