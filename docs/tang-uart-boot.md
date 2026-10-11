# Tang Primer 20K UARTブート

DDR検証済みの経路をLinux用SoCへ接続する。合成対象は`DdrLinuxSoc`、
`DdrLinuxProbe`、`TangLinuxTop`を含めVerylで記述する。
この文書の実装仕様と、末尾の実測結果を区別する。

## SoC構成

CPUは27 MHz、DDRは396/99 MHz、受信−6 tap、3 word校正窓を用いる。
初期化とtraining完了がCPUクロックへ同期されるまでCPUをresetに保持する。
既存`Soc`のCLINT/PLIC、PMP 4 entry、アクセス例外、DDR word CDC/controllerを使用する。

| アドレス | 用途 |
| --- | --- |
| `0x00001000..0x00001fff` | 4 KiB boot ROM。書込みはアクセス例外 |
| `0x10000000..0x1000001f` | 16550互換UART、reg-shift 2、source 1をPLICへ接続 |
| `0x11000000..0x1100ffff` | CLINT。mtimeは27分周で1 MHz |
| `0x0c000000..0x0c3fffff` | PLIC |
| `0x11100000` | SYSCON。full-word書込みの終了値をresetまで保持 |
| `0x80000000..0x87ffffff` | 128 MiB DDR。その他の外部アドレスはwordポートで拒否 |

UARTはT13 RX、M11 TX、115200 baud設定を使う。27 MHz／divisor 15の実ボーレートは
112500である。Linux用DTBはUART clock-frequencyを27 MHzとし、コンソールを115200で指定する。
`0x87e00000..0x87ffffff`の2 MiBはDTBとブート時のスタック用に予約する。
初期SPは`0x87fff000`。Linuxへの移行時は割込みを無効化し、`fence`と`fence.i`の後に
`a0=0`、`a1=0x87e00000`、PC=`0x80000000`でM-mode実行を開始する。

## 転送契約

ROMは起動後に`VBL1\n`を送信する。ホストは1 packetずつ送り、応答を受けてから次を送る。
各packetのheaderは20 byte、整数はlittle endianである。

| offset | サイズ | 内容 |
| --- | --- | --- |
| 0 | 4 | ASCII `VBL1` |
| 4 | 4 | command：`W`=87、`B`=66 |
| 8 | 4 | 転送先アドレス |
| 12 | 4 | payload長、1..256 |
| 16 | 4 | header先頭16 byteとpayloadを連結したCRC-32 |
| 20 | 可変 | payload |

CRCは反転多項式`0xedb88320`、初期値・最終XORが`0xffffffff`。
Python標準ライブラリ`zlib.crc32`と同じ形式である。

- `W`：Image窓`0x80000000..0x81ffffff`かDTB窓`0x87e00000..0x87e0ffff`内に限る。
  全payloadをスタック上のbufferへ受信し、CRCと範囲を検証してから転送先を更新する。
- `B`：アドレスは`0x80000000`、payloadは16 byte固定。
  Image長、DTB長、Image CRC、DTB CRCの4 wordを送る。
  長さ・DTB magic・DDRから読み戻した両ファイルのCRCを確認してから起動する。
- 応答は成功時`K`、拒否時`E`。`B`の`K`は送信完了を待ってから制御を移す。
- ROMは不完全packetの受信中に自律timeoutを行わない。転送中断時はSRAM再書込みで再開する。
  ホストは`E`を受けたら停止し、失敗した転送を成功扱いにしない。
- CRCは通信・保存データの破損検出用であり、署名や起動権限の認証ではない。

## 構築と実行

既存の固定開発コンテナ内で実行する。依存の追加は不要である。

```bash
make tang-boot-test
dtc -I dts -O dtb -o sim/tang_primer_20k.dtb linux/tang_primer_20k.dts
python3 scripts/pack_tang_boot.py sim/tang_boot_payload.bin sim/tang_primer_20k.dtb sim/tang-smoke.vbl
# Linux Imageは既存のlinux/build_linux.shによるM-mode/NOMMU版を使用する。
python3 scripts/pack_tang_boot.py sim/linux/Image sim/tang_primer_20k.dtb sim/tang-linux.vbl
```

固定GOWINコンテナ内で`LINUX_BOOT=1 bash scripts/build_ddr_mpr.sh`を実行する。
`sim/fpga/linux_boot/impl/pnr/linux_boot.fs`を生成し、クロック・setup/hold・制約を検査する。
UARTの送受信はWindowsホストで行う。

```powershell
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-smoke.vbl -ExpectedText 'BOOT OK'
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-linux.vbl -CaptureSeconds 600 -ExpectedText 'userspace is alive'
```

既定では成功・失敗ともLCD SoCへ復帰し、UARTを検査する。`-KeepRunning`を指定すると復帰せず、
Linuxとの後続通信に使用できる。ログは`logs/board/*-LinuxBoot-*`へ保存する。
package・bitstreamのSHA256、転送結果、期待文字列の検出結果を別々に記録する。

## 自動検証とTBの選択

`make tang-boot-test`は実際のCPU、ROM、UART、wordポートとCDCを接続する。
ROMやUARTの内部状態を書換えて転送を省略する処理は含まない。
疎なDDRモデル、待ち時間付き応答、UARTのbit単位送受信と送信側クロック差を扱うため、
この結合TBはVerilatorのC++ harnessとした。通常のUART単体試験は既存Veryl組込みテストを継続する。

検証項目はtraining前のCPU停止、header/payload CRC、範囲外転送拒否、boot時の全体CRC、
DDR命令実行、hartid/DTB引数、タイマ進行、UART→PLIC割込み、共通reset、DDR errorのtrapである。
UART受信を240 cycle/bitとし、ホスト側240/234/246 cycle/bitで同じ転送を実行する。
連続文字を受信する際はstop bit中央で次のstart待ちへ戻る。stop bit末尾まで待つ旧実装では
受信開始の遅れが蓄積し、長い転送で文字を失うことをこの試験で検出した。
試験は`ddr-controller-probe-test`の依存として既存make all/CIに含める。

## 実測結果

2026-10-11、`20261011-162942-LinuxBoot`で短いコードのUART転送、Image/DTBのCRC検査、
DDR命令実行、`BOOT OK`の出力が成功した。所要6.096秒（JTAG書込みと転送を含む）。
hartid/DTB引数、非整列DDR読書き、タイマ進行、UART→PLIC通知・claim/completeを
転送したコード自身が検査した。終了後のLCD復帰とUART検査も成功した。

bitstream SHA256は`12c57e5d5184628b39ec6ad5794dba46f274a80b34ca65866cec613b2e017dce`、
ROM hexのSHA256は`f4838fa9f77b6f5821ada52d19304fb793e3860f210a53aeaf968b875138e7c0`。
ROM使用量1,036/4,096 byte、LUT 12,197、ALU 1,378、register 4,117、setup/hold違反0。

`make all`は成功し、命令試験76件、Spike照合77件が通過した。カバレッジ未到達は
line 4 / branch 1 / expression 13で既存基準内。新規転送試験はホスト側240/234/246
cycle/bitの3設定すべて成功した。Linuxの`/init`到達、LCD bootlog、GUIは
個別の実機確認が必要であり、boot ROMの結合試験だけでは確認済みとしない。

UART変更後の既存Linuxシミュレーションも`/init`、Mandelbrot、donut 24 frame、SYSCON poweroffまで
成功した（853,919,151 cycle、300,378,013 retire）。これはLinux用UART/DDRの実機試験とは別の回帰である。
