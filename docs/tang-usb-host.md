# Tang Primer 20K 単独起動・USB入力

## 実装と検証の範囲

2026-10-13時点。`linux_standalone_top.veryl` は既存のLinux/LCD構成に、
VerylによるSD SPIとUSB ULPIホストを追加する。CPUは27 MHz、DDRは396/99 MHz、
LCDは33 MHz、USBはPHYの60 MHz入力を専用PLLに通して使用する。
USB PLLはT15のクロック入力に対応する `PLL_R[0]` に配置する。
単独起動構成のPMPは2エントリ。固定Linuxの `arch/riscv/kernel/head.S` は
M-mode起動時にエントリ0を全メモリ許可へ設定する。基準のLinux構成は4エントリを維持し、
単独起動構成ではUSB/SD追加後の回路規模を抑えるために2エントリを使用する。
この構成のGowin配置配線結果はLogic 15,189/20,736、Register 5,883/16,173、
BSRAM 8/46で、setup/hold違反は0件。324/81 MHzの診断ではLCD underflowが
発生したため、396/99 MHzを使用する。
CPUバスは直接接続する。表示FIFOの満杯フラグは次の書込み位置から先行計算して
レジスタに保持し、連続転送の間隔を保ったまま読出し要求の組合せ経路を短縮する。
PHYのDIR/NXT/DATAはPLLの157.5度位相出力で同時に保持し、次のリンククロック立上りへ渡す。
実機でturnaroundの値を読んでいた問題に対する修正であり、PHYの制御信号と
DATAに1.5 ns/3.5 nsの異なる出力遅延を与えたテストを追加している。
物理バスの出力停止は生のDIRで行い、出力の再開は立上りで保持したDIRを使う。

SDブートROMのCPU込み試験、FAT16/FAT32/exFATの読取り試験、USBリンク・
トランザクション・非同期MMIO・HID・ハブのモデル試験は通過した。
実機でUSB PHYの識別値 `24 04 06 00` とscratchの `A5` 読戻しが成功し、
full-speed接続とHID入力endpoint 1個の列挙を確認した。
396/99 MHzのHID診断ではLCD状態が `0x1`（有効、DDR error/underflowなし）だった。
USB/SD統合構成でもUART転送からLinux、fbcon、GUI自動起動まで到達し、
USB列挙、UARTでの色変更・移動・終了・再起動を実機確認した。
操作後もLCD状態は正常だった。再試行処理を追加した最終イメージでは、初回のGUI自動起動で
入力endpoint 1個を列挙した（この試行では再試行エラーなし）。
2026-10-13には約32GBのFAT32・MBRカードから、UART送信0 byteで
`SD verified`、Linux、fbcon、`fbui: ready`まで到達した。
SRAM書込み開始を含む経過時間は377.404秒。USB初期化はエラー5の後、
2回目の試行で回復し、HID入力endpoint 1個を列挙した。
結果は`logs/board/20261013-224636-SdBoot-result.json`に保存した。
USBキーボードの実キー入力と、電源投入からの単独起動は未確認である。

最終確認のSHA256は、bitstreamが
`5ffb6b60240c3e4929693bf2341dfc616a154fb4b65a853951a9327219bb07ed`、
`TANGBOOT.VBL` が `875def024786e8906bb2a583f2e4f4e204d358df96cf837d084dc3a39e078aec`。
UART起動結果は `logs/board/20261012-200813-LinuxBoot-result.json`、
GUI操作結果は `logs/board/20261012-200205-LinuxLcdGui-result.json` に保存した
（ログはgit管理外）。

## microSDからの読取り

`make linux-standalone-build` は8 KiBのSD対応ブートROMと、GUIを自動起動する
Linuxイメージを構築し、`sim/linux-standalone/TANGBOOT.VBL` を生成する。
カードのルートディレクトリにこのファイルを置く構成である。

SDインタフェースはSPI mode 0、初期化時約211 kHz、読取り時3.375 MHz。
CMD17の単一セクタ読取りとCRC16検証を行い、カードへの書込み命令は使用しない。
FAT16/FAT32/exFAT、512 byteセクタ、MBRの基本パーティションまたは
パーティションテーブルなしのボリュームに対応する。GPT、FAT12、512 byte以外の
セクタは非対応。exFATではブート領域とディレクトリエントリのchecksum、
連続割当とFAT chainの双方を検証する。起動ファイルは最大36 MiB。

ROMは最初の250 msにUART入力があればUART転送を選択する。それ以外はSDを試し、
ファイル・セクタ・転送内容の検証に失敗するとUARTへ戻る。VBLパケットCRCに加えて、
Image/DTB全体のCRCとDTB magicを検証してから実行する。
単独起動ROMでは、LCDのDDR読出しをImage/DTB検証後に開始する。
UART/SDからのロード中はframebufferを初期化するだけで、表示用DMAとの競合を避ける。
カードのルートへ`TANGBOOT.VBL`をコピーし、コピー元と読戻しのSHA256一致を確認する。
PCで安全に取り外してDockへ挿入した後、次の受信専用試験でSD起動を検証する。

```powershell
./scripts/test-tang-sd-boot.ps1 -Suite <Windows OSS CAD Suite> -Port COM4
```

この試験はstandalone回路をSRAMへロードし、UARTへは1 byteも送信しない。
`SD verified`、`Linux version`、`fbui: ready`をすべて受信した場合に合格とする。
結果、bitstreamのSHA256、UARTログは`logs/board/*-SdBoot-*`へ保存する。
SPI flashへは書き込まないため、この試験単独では電源投入からの起動確認にはならない。

`-Flash`を付けるとSPI flashへ書込み、`openFPGALoader --verify`による読戻し検証後に
同じSD起動試験を行う。`-Frequency 1000000`はJTAG検出・初期接続を1 MHzにする。
今回使用したWindows版openFPGALoaderは外部flash処理へ入ると10 MHzを要求し、
このプローブでは実際には6 MHzへ変更する。したがって、この指定だけではflash転送は低速化されない。
2026-10-13の初回flash書込みは17.52%で進捗が止まり、約298秒で処理を停止した。
その後のJTAG再検出が2回とも`usb bulk read failed`となった。
USB・電源の再接続でJTAG検出は復旧したが、1 MHz指定での再試行もflash転送時は6 MHzとなり、
書込みが再び停止した。停止時に出力された最終進捗は17.52%、経過時間は146.679秒。
`logs/board/20261013-230729-SdBoot-result.json`と同prefixの`-program.log`に記録した。
USB機器のソフトウェア再起動はWindowsの管理者権限不足で失敗し、再度USB・電源を再接続した。
flashは部分書込みの可能性があり、保存完了・電源投入起動は未確認。
再接続後、JTAG 1 MHzで検証済み回路をSRAMへロードし、SDからLinux・fbcon・GUIまで復旧した。
`logs/board/20261013-231123-SdBoot-result.json`はすべての起動判定が成功、
UART送信0 byte、経過時間356.722秒、errorなし。USB HID endpointは1個で、初期化エラー出力なし。
この復旧ではflashへ書き込んでいない。電源を切ると、次回は再びSRAMロードが必要である。
同じflash書込み条件の反復は行わず、転送停止の切り分けを別途行う。

実機操作に使用した既存WindowsツールはOSS CAD Suite `20260720`。
`openFPGALoader.exe`のSHA256は
`1200def4c208f85a68df2017bb51a94ef354a66eff85aeb839daf7123f10ab11`。
これはリポジトリのWindowsセットアップ既定値（2026-08-10）とは異なるため、
flash転送停止の切り分けではこの実体とログを基準にする。ツールの追加・更新は未実施。

### flash転送停止の調査

実行ファイルの自己申告は`openFPGALoader v1.1.1`。
公式tagのコミットは`85be4fa02b2dd6a83716d7dfac3d25bbd260ff7b`である。
既存バイナリがこのコミットと同一ソースかは、自己申告だけでは断定しない。

[upstream issue #573](https://github.com/trabucayre/openFPGALoader/issues/573)には、
同じTang Primer 20Kでflash書込み中にFTDI通信が停止する報告がある。
報告者は256 byteの書込み単位を128 byteへ変更して改善したと述べている。
今回の停止原因が同一であることや、この変更で解消することはまだ実機検証していない。

[v1.1.1のSPIFlash実装](https://github.com/trabucayre/openFPGALoader/blob/85be4fa02b2dd6a83716d7dfac3d25bbd260ff7b/src/spiFlash.cpp)では、
書込みループの単位は256 byte固定である。CLIの周波数変更とは独立した条件として、
128 byte版との比較が次の検証候補となる。比較時は同じbitstream、同じUSB接続、
同じ読戻し検証を使用し、書込み単位以外の差を記録する。
成功条件は全書込み・読戻し一致と、flashからの回路再構成後のSD→Linux→GUI起動。
電源を切ってからの単独起動は、その後に別途確認する。

2026-10-13に利用者の承認を得て、比較専用のNixコンテナを追加した。
`container/openfpgaloader/flake.nix` と `flake.lock` は既存のdotfilesと同じ
nixpkgs revisionを使用し、MinGW GCC 15.2.0、libftdi、libusb、zlibを固定する。
Windows実行ファイルとDLLは `tools/openfpgaloader/` へ出力する。

```powershell
podman build -t variscite-openfpgaloader:1.1.1 -f container/openfpgaloader/Containerfile .
podman run --rm --network none -v "${PWD}:/work" variscite-openfpgaloader:1.1.1
```

出力先が既に存在する場合は上書きせず終了する。再構築の比較には、コマンド末尾へ
`bash scripts/build-openfpgaloader.sh /work/.build/openfpgaloader-rebuild` のように
別の出力先を指定する。出力には実行ファイル・DLL・転送処理のソース、
Nix store path、`SHA256SUMS`を含む。ビルドログは `logs/openfpgaloader/` に保存する。

| 比較版 | 変更内容 | 実機結果 |
|---|---|---|
| `page256` | 固定upstreamの256 byte書込み | 9.37%で停止。120秒で終了し、その後JTAGのUSB bulk readも失敗 |
| `page128` | 書込みループ2箇所のみ128 byte化 | 書込み100%まで完了。読戻し位置387で不一致、34.587秒で失敗 |
| `page128-bounds` | 128 byte化とGW2A読取りの境界修正 | 書込み完了、読戻し位置48で不一致（20.954秒） |
| `page128-bounds-1mhz` | 境界修正版の外部flashクロックを1 MHzに固定 | 実効1 MHzを確認。書込み完了、読戻し位置357で不一致（21.408秒） |
| `page128-bounds-read128` | 境界修正版のverify/dumpの読取り単位を128 byte化 | 書込み完了、読戻し位置24で不一致（28.572秒）。別USBハブで実施 |

前2版の同梱DLLは全てSHA256一致。使用したbitstreamは前回SD起動成功時と同一。
結果は `logs/board/20261013-234342-SdBoot-result.json`（256 byte）、
`logs/board/20261013-234228-SdBoot-result.json`（128 byte）に保存した。
この比較では128 byte化で停止を回避できたが、読戻し検証は通っておらず、
flash保存や電源投入起動の成功とは扱わない。

比較時の実行ファイルSHA256:

```text
page256 6892c5d6e6fe01e70a8a6aff9cc05c6d502d1b283cb922a3b3f406b070fbf65c
page128 eeb41031f604eb04623f15eaad5aab89a7880bf2a0e52bf4ad95bb1ce7da0e8b
page128-bounds 3f95cf958708037b4eccc9b2ad9920d54548998ed7c098e6546e9cfbff7d3234
page128-bounds-1mhz f6861e54ba79a28637aea86391a1fbdaceafc87e0568f8098af24118926f55b3
page128-bounds-read128 6874524821e3c222efeb9a5c1f110647d7bb502535f6334b040a332ce4ebf681
```

読戻し調査中に、固定upstreamの `Gowin::spi_put` がGW2A受信時に
配列確保後の `len++` により送受信配列と呼出元バッファの境界を越えることを確認した。
`gw2a-read-bounds.patch` はデータ長と追加クロック用の転送長を分離し、
追加送信byteを0で初期化する。照合範囲や不一致の判定は変更しない。
実ソースから当該メソッドを抽出し、JTAG転送だけをモデル化したASan/UBSan試験で、
修正前のbuffer-overflowと修正後の成功を確認する。1/2/4/128/256/260 byte、
送信のみ、受信のみ、コマンド失敗、受信の1 bit位置補正を検証する。
この試験はコンテナ構築時の `nix flake check` に含む。
境界修正版と1 MHz版の結果は、それぞれ
`logs/board/20261013-235441-SdBoot-result.json`、
`logs/board/20261013-235722-SdBoot-result.json` に保存した。
境界修正やクロック低下だけで読戻し不一致が解消するとは確認できていない。

2026-10-14の128 byte単位のdumpでは、同じflash先頭4 KiBを2回読んだ結果の
SHA256が一致しなかった（`logs/board/flash-read128-{a,b}.bin`）。
このdump経路は通常の書込み経路とflashリセットの有無が異なるため、
書込み内容の破損と読取り経路の不安定を、この結果だけで区別しない。
利用者がType-C側の別USBハブへ変更した後も、通常書込み経路の全量照合は失敗した。
結果は `logs/board/20261014-000411-SdBoot-result.json` に記録した。
この試行は接続経路も変わっているため、読取り単位だけの比較には使わない。
flash書込み試験はここで止め、既存OSS CAD SuiteによるSRAMロードで復旧した。
`logs/board/20261014-000506-SdBoot-result.json` は `sd_verified`、`linux_started`、
`gui_ready` が全てtrue、UART送信0 byte、errorなし、経過379.864秒。
USBは初期化エラー5の後に入力endpoint 1個を列挙した。
この復旧はflashを書き換えない。現在の動作はSRAMロードによるものであり、
電源断後にflashから起動できることは未確認。
次の切り分けでは、正常動作が確認された別のJTAGアダプタ、またはメーカーの書込み経路で
同じbitstreamを全量照合し、書込み不良とSipeed USB/JTAG経路の読取り不良を区別する。
これらの比較はまだ実施していない。

追加環境の検証は、専用コンテナの構築、`nix flake check`（ASan/UBSan）、
5比較版のオフライン出力、ShellCheck、shfmt、nixfmt、statix、deadnix、
PowerShell構文検査を通過した。最終コンテナから出力した`page128-bounds-read128`は
実機試験で使った実行ファイルとSHA256が一致した。

実機試験は次で実行する。書込み・読戻しが成功した場合だけSD起動へ進む。
`ProgramSeconds` はプログラマ処理の上限で、UART受信の `CaptureSeconds` とは独立する。
実行ファイルのSHA256とタイムアウト値も結果JSONへ記録する。

```powershell
./scripts/test-tang-sd-boot.ps1 -Suite ./tools/openfpgaloader/page128-bounds -Port COM4 -Frequency 1000000 -ProgramSeconds 300 -Flash
```

## USB入力

対象はDockのユーザー用USB-C J8に接続したFS/LS機器。
USB2ハブをfull-speedで列挙し、ハブ配下のlow-speed機器にはPREを送る。
対応するHIDはboot protocolのキーボードとマウスである。
最大8入力endpoint、ハブ深さ3、ハブあたり15ポート、descriptor最大512 byte。
high-speed転送、汎用report descriptor解析、hotplugは未実装。
起動前に機器を接続する必要がある。

現段階では専用ユーザアプリがホストを占有する。LinuxのUSB HCDやevdevへの登録は
実装していない。GUIはUSB入力とUART入力を併用し、矢印/WASDで矩形移動、R/G/Bで
色変更、Escで終了する。マウス処理はモデル試験のみで、実機確認は未実施。
描画は変更範囲だけを更新し、USB SOFはCPUの描画処理と独立して生成する。
起動時のLINK/TIMEOUT/CRC/NAKによる列挙失敗は、100 ms後にバスリセットから
最大3回まで再試行する。descriptor/protocolのエラーは再試行しない。
UARTログに失敗コードと試行回数を残す。モデル試験では途中まで登録されたendpointと
アドレス割当の初期化、再試行上限、恒久エラーの即時返却も検証する。

操作応答の高速化は未完了。今回のUSB統合構成では、GUI開始からreadyまで約81〜145秒、
UARTによる色変更約30秒、矩形移動約10秒、終了約21秒だった。
部分描画への変更で以前の全面再描画より短縮しているが、対話用途には改善が必要である。

## レジスタ

USBベースは `0x11300000`、SDベースは `0x11400000`、窓は各256 byte。
USBはCPUからの要求を要求/応答toggleと保持データで60 MHz領域へ渡す。
転送中はTXバッファを書き換えない。

| USB offset | 内容 |
| --- | --- |
| 0x00 | ID `0x55484231` |
| 0x04 | bit0: SOF有効、bit1: root low-speed |
| 0x08 | busy[0]、completed[1]、結果[7:4]、受信長[14:8]、toggle[15]、PHY値[23:16]、line[25:24] |
| 0x0c | start[31]、操作[2:0]、toggle[3]、speed[5:4]、送信長[14:8]、token[26:16] |
| 0x10 | PHYレジスタ番号[5:0]、書込み値[15:8] |
| 0x14 | frame[10:0]、SOF遅延sticky[11] |
| 0x18 | PHY診断の有効サンプル数。busy中は0 |
| 0x40–0x7f | TX 64 byte |
| 0x80–0xbf | RX 64 byte。busy中は0 |
| 0xc0–0xff | 直前のPHYコマンドの最大16サンプル。入力DATA[7:0]、出力DATA[15:8]、DIR[16]、NXT[17]、STP[18]、drive[19]、内部PHY保持値[31:24] |

操作はIN=0、OUT=1、SETUP=2、SOF=3、PHY read=4、write=5。
結果はOK=1、NAK=2、STALL=3、CRC=4、timeout=5、PID=6、size=7、link=8。
speedはFS=1、LS=2、ハブ経由LS=3。
診断トレースは `UsbHostMmio` の `TRACE=1` で有効になる。
通常構成では `TRACE=0` として記憶回路を除外し、サンプル数は0を返す。

| SD offset | 内容 |
| --- | --- |
| 0x00 | ID `0x53445031` |
| 0x04 | CS_N[0]、低速選択[1]。reset値3 |
| 0x08 | busy[0]、直前の受信byte[15:8] |
| 0x0c | 下位byte書込みでSPI転送を開始 |

## 検証コマンド

固定された開発コンテナ内で以下を実行する。

```sh
make usb-host-test usb-hid-test sd-spi-test sd-boot-test tang-sd-boot-test pmp-two-test
make linux-standalone-build
scripts/build_usb_probe.sh
USB_HID_PROBE=1 scripts/build_usb_probe.sh
```

CPU込みSD試験は正常起動、VBL CRC不一致、SDセクタCRC不一致とUART復帰を検証する。
PMPの2エントリ試験は、未実装の設定byte/アドレスレジスタが0を返すこと、
U-modeの書込み禁止とM-modeの書込み許可、ロック後の設定保持を検証する。
UART復帰はDDR応答を200メモリクロック遅らせ、ホストのbit間隔を234 CPUクロック
（27 MHzで約115200 baud）とした条件でも検証する。
合成用RTLはVeryl、外部PHY/カードモデルと境界条件の検証はSV/C++/Cを使用する。

`scripts/boot-tang.ps1 -ByteDelayMilliseconds 1` は、UART受信の取りこぼしを
切り分けるための低速診断用オプションである。通常値は0。
`scripts/uart-term.ps1 -Port COM4 -MaxSeconds 300` で再書込みせずUARTを採取できる。

## 参照資料

- [Sipeed公式USBピン制約](https://github.com/sipeed/TangPrimer-20K-example/blob/main/USB/usb_serial/src/usb_example.cst)
- [Dock-3713回路図](https://dl.sipeed.com/fileList/TANG/Primer_20K/02_Schematic/Tang_Primer_20K_Dock-3713_Schematics.pdf)
- [SOM-3961回路図](https://dl.sipeed.com/fileList/TANG/Primer_20K/02_Schematic/Tang_Primer_20K_SOM-3961_Schematic.pdf)
- [USB3317データシート](https://ww1.microchip.com/downloads/en/DeviceDoc/3317.pdf): ULPIレジスタ、turnaround、STP、FS/LS設定
- [Microsoft exFAT仕様](https://learn.microsoft.com/en-us/windows/win32/fileio/exfat-specification): ボリュームとディレクトリ形式
- [Gowin Clock User Guide](https://cdn.gowinsemi.com.cn/UG286E.pdf): rPLLの静的位相設定

Dock回路図ではVBUSが+5 Vへ接続され、CCにはpull-downがある。USB-Cハブの
接続可否は実機で確認する必要がある。PHYレジスタアクセスの調査とは切り分ける。
