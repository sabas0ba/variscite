# Tang Primer 20K 単独起動・USB入力

## 実装と検証の範囲

2026-10-12時点。`linux_standalone_top.veryl` は既存のLinux/LCD構成に、
VerylによるSD SPIとUSB ULPIホストを追加する。CPUは27 MHz、DDRは396/99 MHz、
LCDは33 MHz、USBはPHYの60 MHz入力を専用PLLに通して使用する。
USB PLLはT15のクロック入力に対応する `PLL_R[0]` に配置する。
PHYのDIR/NXT/DATAはPLLの157.5度位相出力で同時に保持し、次のリンククロック立上りへ渡す。
実機でturnaroundの値を読んでいた問題に対する修正であり、PHYの制御信号と
DATAに1.5 ns/3.5 nsの異なる出力遅延を与えたテストを追加している。
物理バスの出力停止は生のDIRで行い、出力の再開は立上りで保持したDIRを使う。

SDブートROMのCPU込み試験、FAT16/FAT32/exFATの読取り試験、USBリンク・
トランザクション・非同期MMIO・HID・ハブのモデル試験は通過した。
実機では追加MMIOへアクセスでき、内部トレースでUSB PHYが識別値 `24 04 06 00` を
返すことを確認した。PHYの応答とMMIOへ返す保持値が一致しない問題を調査中である。
USBキーボード入力、実カードからのLinux起動、
電源投入からの単独起動は未確認である。

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
カードの準備と実機起動の手順は、実カード検証完了後に確定する。

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

## レジスタ

USBベースは `0x11300000`、SDベースは `0x11400000`、窓は各256 byte。
CPUからの要求は登録された外部バスを通り、USBは要求/応答toggleと保持データで
60 MHz領域へ渡す。転送中はTXバッファを書き換えない。

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
make usb-host-test usb-hid-test sd-spi-test sd-boot-test tang-sd-boot-test
make linux-standalone-build
scripts/build_usb_probe.sh
USB_HID_PROBE=1 scripts/build_usb_probe.sh
```

CPU込みSD試験は正常起動、VBL CRC不一致、SDセクタCRC不一致とUART復帰を検証する。
合成用RTLはVeryl、外部PHY/カードモデルと境界条件の検証はSV/C++/Cを使用する。

## 参照資料

- [Sipeed公式USBピン制約](https://github.com/sipeed/TangPrimer-20K-example/blob/main/USB/usb_serial/src/usb_example.cst)
- [Dock-3713回路図](https://dl.sipeed.com/fileList/TANG/Primer_20K/02_Schematic/Tang_Primer_20K_Dock-3713_Schematics.pdf)
- [SOM-3961回路図](https://dl.sipeed.com/fileList/TANG/Primer_20K/02_Schematic/Tang_Primer_20K_SOM-3961_Schematic.pdf)
- [USB3317データシート](https://ww1.microchip.com/downloads/en/DeviceDoc/3317.pdf): ULPIレジスタ、turnaround、STP、FS/LS設定
- [Microsoft exFAT仕様](https://learn.microsoft.com/en-us/windows/win32/fileio/exfat-specification): ボリュームとディレクトリ形式
- [Gowin Clock User Guide](https://cdn.gowinsemi.com.cn/UG286E.pdf): rPLLの静的位相設定

Dock回路図ではVBUSが+5 Vへ接続され、CCにはpull-downがある。USB-Cハブの
接続可否は実機で確認する必要がある。PHYレジスタアクセスの調査とは切り分ける。
