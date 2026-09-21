# Tang Primer 20K DDR3 MPR 読出し診断

対象は基板上の SK hynix H5TQ1G63EFR-PBC (x16、128 MiB)。
`DdrReadGateSweep` の MPR モードは初期化後、全 bank を閉じた状態で
MR3 A2=1 を設定し、A12=1、A[2:0]=0 の BL8 READ を発行する。
各レーンの DQ0/DQ8 に現れる 0,1,0,1,0,1,0,1 パターンを、
それぞれの `RVALID` とともに照合する。64 個の受信位相・ゲート位置を
走査した後、MR3 A2=0 を設定し、診断トップは DRAM を RESET する。
この診断は DRAM アレイへの書込み、読戻し、refresh を検証しない。

RTL は Veryl、テストベンチは SystemVerilog。`make ddr-mpr-test` は
MR3 の切替えと待ち時間、両レーンの個別位相、誤パターンの拒否、
無応答時の 64 通り完走を確認する。合成・配置配線は固定 Gowin コンテナで
`bash scripts/build_ddr_mpr.sh` を実行する。UART のフレームは状態文字と
4 桁の 16 進数で、前半 2 桁が観測済み `RVALID` レーン mask、
後半 2 桁が `RBURST` レーン mask を示す。`M` は両レーンでパターンを
観測したこと、`V` は `RVALID` が両レーンにあるがパターン不一致、
`E` は受信できなかったことを示す。

2026-09-21 の実機試験では、初期の 32 通り版
SHA256 `1d3d2aa1d77bf16404c51dcce1f81fa8b573b8614b02c720ca4aa628c5acc6d7`
で `M` を繰り返し観測した。一方、デバッグ信号や探索範囲の変更後は
同じ基板で `V0302` や `E0000` となった。64 通り版
SHA256 `d6b5e0fdd0e9f6172716e1ea1815a6ec9cb40eadb73e80a5c835efe87971ab72`
は 2 回とも `E0000`。配置またはタイミングへの依存が残り、MPR データを
安定して受信できたとは判定しない。通常の ACT/READ 診断は同日の再構築版
SHA256 `6edb31134bc24cd8e657c4846950f716e8e566e40fa9e40923224d882de3da47`
で `G` を検出したが、これは DQS ゲート検出のみを意味する。

実機診断は `scripts/test-ddr-init-board.ps1 -Mode DdrMpr` で実施する。
このスクリプトは結果にかかわらず検証済み LCD サンプルを復元する。
今回の試験でも復元と LCD UART 検査は通過した。ログは
`logs/board/20260921-182326-DdrMpr-*`、
`logs/board/20260921-182434-DdrMpr-*`、
`logs/board/20260921-182711-DdrRead-*` に保存される。

次は MPR コマンドと READ ゲートの基板上タイミングを観測し、
両レーンの DQ データアイを安定して選ぶ。その後に DDR アレイの
書込み・読戻し、refresh、アドレス alias を検証する。

## 一次資料

- [JEDEC JESD79-3F, 4.10 Multi Purpose Register](https://e2echina.ti.com/cfs-file/__key/telligent-evolution-components-attachments/00-120-01-00-00-26-20-93/JESD79_2D00_3F.pdf): MR3、READ アドレス、パターン、tMOD、tMPRR。
- [Gowin FPGA Primitive](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf): DQS、IDES8_MEM の端子仕様。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 搭載 DRAM の仕様。
