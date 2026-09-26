# DDR PHY起動シーケンスの比較

`DdrPhyStartup` は停止しない27 MHz基準クロックで動作し、同期済みPLL/DLL lockを確認してからPHYの起動順序を制御する。従来のDRAM RESET/CKE/MRS/ZQ初期化を置き換えるものではない。PHYの準備完了を2段同期した後に既存 `Ddr3Startup` を開始する。

各段階を8基準クロック、約296 ns保持する。外部制御出力は全てレジスタ化し、位相番号の組合せデコードによるグリッチを避ける。

| 段階 | DLL freeze | 高速clock stop | 分周器reset | PHY reset | DQS HOLD | DLL update_n |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| lock安定待ち | 0 | 0 | 0 | 1 | 0 | 1 |
| DLL停止 | 1 | 0 | 0 | 1 | 0 | 1 |
| 高速clock停止 | 1 | 1 | 0 | 1 | 0 | 1 |
| 分周器reset | 1 | 1 | 1 | 1 | 0 | 1 |
| reset解除 | 1 | 1 | 0 | 0 | 0 | 1 |
| 高速clock再開 | 1 | 0 | 0 | 0 | 0 | 1 |
| DLL再開 | 0 | 0 | 0 | 0 | 0 | 1 |
| DQS停止 | 0 | 0 | 0 | 0 | 1 | 1 |
| DLL code更新 | 0 | 0 | 0 | 0 | 1 | 0 |
| 更新後待機 | 0 | 0 | 0 | 0 | 1 | 1 |
| ready | 0 | 0 | 0 | 0 | 0 | 1 |

PLL lock喪失時、およびready後のDLL lock喪失時は最初から再実行する。lock信号は基準クロックで2段同期する。比較モードのPHY resetはシーケンサが保持し、lockの立上りをそのままリセット解除へ使わない。

比較用 `DdrArrayStartupScan` はHOLD無効・90度DLL・全幅の位相/beat位置探索にこの起動手順を加える。既定 `PHY_STARTUP=0` は従来動作を維持する。構築は `DDR_ARRAY_STARTUP_SCAN=1 bash scripts/build_ddr_mpr.sh`、実機測定は `scripts/test-ddr-init-board.ps1 -Mode DdrArrayStartupScan` を使う。

`make ddr-phy-startup-test` はlock待機、制御順序、各保持時間、停止中のPLL lock喪失、DLL lock喪失と再実行を検証する。PHY/dividerのreset解除がclock停止中であること、および解除からclock再開まで8基準クロック以上あることも検証する。

STAでは既存のクロック・データ経路制約に加えて、起動モードだけ `ddr_phy_startup.sdc` を適用する。Gowin同梱の `gw2a/prim_sim.v` でDHCEN CEの4段、DQS HOLDの3段の負エッジ同期を確認したため、基準クロックからその入力への経路を除外する。readyは2段同期の初段入力だけを除外する。PHYと分周器のreset解除は高速clock停止中かつ再開の約296 ns前であり、連続clockを前提とするrecovery解析から専用PHY resetレジスタの出力と分周器reset端子だけを除外する。通常のデータ経路やreadyの2段目は解析を維持する。各モード用SDCは基本制約と追加制約を1ファイルに連結してGowinへ渡す。

起動手順の設計では [LiteDRAM GW2A PHYの初期化手順](https://github.com/enjoy-digital/litedram/blob/master/litedram/phy/gw2ddrphy.py) と [Gowin Primitive仕様のDLL/DHCEN/DQS](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf) を参照した。外部PHY実装を取り込んだものではなく、制御RTLと試験は本リポジトリのVeryl/SVで実装する。

2026-09-26にVeryl lint、起動試験、配置配線（setup/hold違反0）を通過した。共有モジュールの入力追加後、従来の `build_ddr_init.sh` と `build_ddr_read.sh` も再構築を通過した。bitstream SHA256 `6dba57a2612f92f5891d25b5116bcb123ac79fd0041fb76279db97ea1c687efd` の3回の実機結果は全て `V0000FDFD`。ログは `logs/board/20260926-172830-DdrArrayStartupScan-*`、`172857`、`172953`。全回のLCD SoC復帰・UART検査は通過した。

列ごとのDQ変化を示す後半のマスクは3回同一となったが、前半の全幅合格マスクは両laneとも0である。起動手順の追加だけでは安定したDDR読出しに達していない。次は有効信号前後の全128 bitを捕捉し、beat/DQ単位の不一致を確認する。
