# Tang Primer 20K DDR3 MPR 読出し診断

対象は基板上の SK hynix H5TQ1G63EFR-PBC (x16、128 MiB)。
`DdrReadGateSweep` の MPR モードは初期化後、全 bank を閉じた状態で
MR3 A2=1 を設定し、A12=1、A[2:0]=0 の BL8 READ を発行する。
各レーンの DQ0/DQ8 に現れる 0,1,0,1,0,1,0,1 パターンを、
それぞれの `RVALID` とともに照合する。64 個の受信位相・ゲート位置で
それぞれ 3 回 READ し、3 回とも一致した候補だけを記録する。
走査後は MR3 A2=0 を設定し、診断トップは DRAM を RESET する。
この診断は DRAM アレイへの書込み、読戻し、refresh を検証しない。

RTL は Veryl、テストベンチは SystemVerilog。`make ddr-mpr-test` は
MR3 の切替えと待ち時間、両レーンの個別位相、誤パターンの拒否、
1 回だけ一致する候補の拒否、無応答時の 64 通り × 3 回の完走を確認する。
合成・配置配線は固定 Gowin コンテナで
`bash scripts/build_ddr_mpr.sh` を実行する。UART のフレームは状態文字と
4 桁の 16 進数で、前半 2 桁が直近の lane 0 DQ0 の 8 beat、
後半 2 桁が lane 1 DQ8 の 8 beat を示す。`RVALID` を観測しないレーンは
`00` のままである。`M` は両レーンでパターンを
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

同日の追加比較では、32 通り版 SHA256
`b97d515ade3f24610d9b7febdeffb9af18b6bb0423fafa642bf02d339dc6d0ba`
を同一 bitstream のまま 2 回ロードし、`M0303` と `V0303` を得た。
この比較版の 4 桁はパターンではなく、`RVALID` と `RBURST` のレーン mask。
両回とも両レーンの DQS バーストと `RVALID` はあったが、パターン照合の結果が
変動した。

DQ0/DQ8 の 8 beat を表示する比較用 32 通り版 SHA256
`976b501b94186f91f2b0515bc2cf74b1b6b3710730077947704b2d24220efc2d`
では、同一 bitstream の 2 回のロードで `V80AA` と `V0A80` となった。
期待値 `AA` または `55` に対して受信値そのものが変動している。
変更を 64 通りへ戻して再構築した SHA256
`906b563bb81fd54f1524a394bf24b9773b3b649fee94454ad655066cfa8d1d38`
では `E0000` だった。これらはいずれも各試験後の LCD 復元が成功した。
3 回一致へ変更した 64 通り版 SHA256
`b212683f5408b84097c8cd7ea3f280bc3baf9e3ed9fd335152abcb6dff77bc66`
および比較用 32 通り版 SHA256
`c2661a52851e4caae6872cfd92d8ae61b655a904d2fc3ebe28fc8735a2d94b9b`
も `E0000` だった。反復判定は偶然の一致を防ぐが、DQS が受信できない構成を
修復するものではない。どちらの試験後も LCD 復元は成功した。

次に診断コマンドを serializer slot 0 から slot 2 へ移した。
CL=6/AL=0 の READ を slot 2 に置く [Gowin のタイミング例](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf)
が根拠だが、これはベンダー PHY IP の例であり、このカスタム PHY の校正値ではない。
slot 2 の比較版 SHA256
`c1550be057a76d93a4116e49b0584d1876bd92b3c91509fe51977d5eb7e97e77`
を同一 bitstream のまま 3 回ロードすると `M`, `V80AA`, `M` だった。
配置を整理した最終版 SHA256
`991a0f4855e894731213e32491f298eaf966fda0f72493d591bc3bbd589f0aff`
は 2 回とも `V80AA` または `V0A80` で、安定受信には至っていない。
`M` の後続 4 桁も最後の `RVALID` の値であり、合格判定に使った 3 回の
サンプルを表すわけではない。slot 2 は DQS の観測を改善したが、
データアイ校正が必要である。各試験後の LCD 復元は成功した。
Gowin の公式 PHY 資料は各サンプリング点で反復してデータを読み、連続する
正しいサンプリング点の中央を選ぶ方法を説明している。現在は同じ候補を
3 回判定するが、連続する有効点の範囲とデータアイの中央は未検出である。

同日、DLL の `STEP` を UART の先頭 2 桁へ一時的に出す計測用 bitstream
SHA256 `954215dd2f54e3d3e98c19c04ed20bced55f39e8a631b2d21e06b2fba74f0613`
を 2 回ロードした。どちらも `STEP=0x15`、MPR 診断結果は `V` だった。
後半 2 桁は lane 1 の直近パターンで `AA`。この出力形式は計測専用であり、
通常版の UART フレームとは異なる。計測後に RTL と SDC の一時変更を戻し、
両回とも LCD 復元を確認した。ログは
`logs/board/20260921-231850-DdrMpr-*` と
`logs/board/20260921-231929-DdrMpr-*`。この観測は DLL の基準値を示すが、
受信遅延の有効範囲はまだ示さない。

受信遅延診断 `TangDdrMprDelayProbe` を追加した。DQS primitive の
`RLOADN` と `RMOVE` を使い、DLLSTEP を基準に +0、+4、...、+28 tap の
8 点を走査する。各遅延値で READ ゲート位置 8 通りと RCLKSEL 8 通りを
組み合わせ、候補ごとに 3 READ を照合する。UART の 4 桁は従来の
パターン値ではなく、前半・後半がそれぞれ lane 0/1 の合格遅延マスクで、
bit 0 が +0 tap を表す。`DDR_MPR_DELAY=1 bash scripts/build_ddr_mpr.sh` で
専用 bitstream を構築し、`-Mode DdrMprDelay` で実機試験する。
[Gowin DQS primitive 資料](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf)
は `RLOADN`、`RMOVE`、`RDIR` による読出し遅延調整を規定する。

最初の固定ゲート版 SHA256
`e41871de8686d68df4a2ea1f4cc2e9fe0e48ec79fa413618c7b7937e1ea01d2f`
は `E0000` だった。ゲート位置も含めた全 512 候補版 SHA256
`bc12dd13c1cdc7ed1b5e2bab3cde5366581e0fb09f73ef681e2ca204b0daf4df`
も `E0000` で、合格遅延値は得られなかった。比較のため同じ RTL から
従来 MPR モードを再構築した SHA256
`91904a5d60c927f60266a74cb34a7827935db9730c9cc8d3e615712f157eb56d`
も `E0000` だった。全 512 候補版は約 200 us で refresh を行わず、
終了後に DRAM を RESET する。アレイデータの保持・利用はしない。
`RMOVE` より 1 controller cycle 前に `RDIR` を確定する最終版 SHA256
`845b3fdf2dc3961166e1c57a25271af5f49c78b470b10c3ff529ad95fce2bc5f`
では `V0000` となり、両レーンの `RVALID` は観測できたが、3 READ 連続で
合格する MPR パターンはどの遅延値にもなかった。現状では読出し校正値を
選べない。
シミュレーションでは 512 候補 × 3 READ、遅延更新 28 pulse、両レーンの
合格マスクを確認した。実機の各試験後に LCD 復元を確認した。ログは
`logs/board/20260921-232846-DdrMprDelay-*`、
`logs/board/20260921-233049-DdrMprDelay-*`、
`logs/board/20260921-233155-DdrMpr-*`、
`logs/board/20260921-233655-DdrMprDelay-*`。

実機診断は `scripts/test-ddr-init-board.ps1 -Mode DdrMpr` で実施する。
このスクリプトは結果にかかわらず検証済み LCD サンプルを復元する。
今回の試験でも復元と LCD UART 検査は通過した。ログは
`logs/board/20260921-182326-DdrMpr-*`、
`logs/board/20260921-182434-DdrMpr-*`、
`logs/board/20260921-182711-DdrRead-*`、
`logs/board/20260921-223810-DdrMpr-*`、
`logs/board/20260921-223857-DdrMpr-*`、
`logs/board/20260921-224014-DdrMpr-*`、
`logs/board/20260921-224714-DdrMpr-*`、
`logs/board/20260921-224834-DdrMpr-*`、
`logs/board/20260921-225331-DdrMpr-*`、
`logs/board/20260921-225416-DdrMpr-*`、
`logs/board/20260921-225454-DdrMpr-*`、
`logs/board/20260921-230027-DdrMpr-*`、
`logs/board/20260921-230107-DdrMpr-*` に保存される。

次は MPR コマンドと READ ゲートの基板上タイミングを観測し、
両レーンの DQ データアイを安定して選ぶ。その後に DDR アレイの
書込み・読戻し、refresh、アドレス alias を検証する。

## 一次資料

- [JEDEC JESD79-3F, 4.10 Multi Purpose Register](https://e2echina.ti.com/cfs-file/__key/telligent-evolution-components-attachments/00-120-01-00-00-26-20-93/JESD79_2D00_3F.pdf): MR3、READ アドレス、パターン、tMOD、tMPRR。
- [Gowin FPGA Primitive](https://www.gowinsemi.com/upload/database_doc/39/document/5bfcff2ce0b72.pdf): DQS、IDES8_MEM の端子仕様。
- [Gowin DDR3 PHY Interface IP User Guide, 3.2.5 EYE SCAN](https://www.gowinsemi.com/upload/database_doc/2819/document/660baf95016e1.pdf): 反復読出しと連続する正常サンプリング点の中央の選択。
- [SK hynix H5TQ1G63EFR Rev. 1.1](https://dl.sipeed.com/fileList/TANG/Primer_20K/07_Chip_manual/sk_hynix.pdf): 搭載 DRAM の仕様。
