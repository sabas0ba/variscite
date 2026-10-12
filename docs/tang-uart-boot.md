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
RTLの受信FIFOは16 byte、送信側は1 byteのshift registerのみである。実機DTBは
`compatible = "ns16550a"`、`fifo-size = <1>`、`tx-threshold = <0>`を指定する。
Linux 6.12の`drivers/tty/serial/8250/8250_of.c`は後者2項目から`tx_loadsz=1`を設定し、
THRE通知ごとの書込みを1 byteに制限する。`ns16850`の既定値は128 byteの一括送信であり、
このRTLには適合しない。受信FIFOの深さと送信能力は対称ではなく、完全な16550の機能実装でもない。
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
# Linux Imageと両環境のDTBを構築する。
make linux-build
python3 scripts/pack_tang_boot.py sim/linux/Image sim/linux/tang_primer_20k.dtb sim/tang-linux.vbl
```

Linux Imageはシミュレータと実機で共通とし、`CONFIG_CMDLINE_FALLBACK=y`でDTBの
`chosen.bootargs`を優先する。元の`nommu_virt_defconfig`には`CMDLINE_FORCE=y`があり、
解除しないと実機でも組込みの1 Mbps設定を使い、通常コンソールへの切替え時に通信速度が
変わってログを読めなくなる。ビルド時に設定を検査し、`sim/linux/kernel.config`へ保存する。

固定GOWINコンテナ内で`LINUX_BOOT=1 bash scripts/build_ddr_mpr.sh`を実行する。
`sim/fpga/linux_boot/impl/pnr/linux_boot.fs`を生成し、クロック・setup/hold・制約を検査する。
UARTの送受信はWindowsホストで行う。

```powershell
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-smoke.vbl -ExpectedText 'BOOT OK'
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-linux.vbl -CaptureSeconds 600 -ExpectedText 'userspace is alive'
# シェルからの応答も検査する。
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-linux.vbl -CaptureSeconds 600 -ExpectedText 'veryl$ ' -ConsoleCommand help -CommandExpectedText 'restart the machine'
# ユーザプロセスの描画完了を検査する（出力先はUART端末）。
scripts/boot-tang.ps1 -Suite <oss-cad-suite> -Port COM4 -Package sim/tang-linux.vbl -CaptureSeconds 600 -ExpectedText 'veryl$ ' -ConsoleCommand donut -CommandExpectedText 'donut: 24 frames rendered'
```

既定では成功・失敗ともLCD SoCへ復帰し、UARTを検査する。`-KeepRunning`を指定すると復帰せず、
Linuxとの後続通信に使用できる。ログは`logs/board/*-LinuxBoot-*`へ保存する。
package・bitstreamのSHA256、転送結果、期待文字列の検出結果を別々に記録する。
`ConsoleCommand`は起動完了文字列を検出した後にASCII 1行を送り、送信後に受け取った文字列だけで
`CommandExpectedText`を検査する。コマンド応答には別途`CaptureSeconds`の期限を設ける。
UART生ログは実行中も読めるよう逐次保存する。

シミュレータの回帰は`make linux-boot`で実行する。固定時間のsleepを使わず、起動メッセージと
プロンプトの後に`mandel`、その完了後に`donut`、24 frameの完了後に`poweroff`を送る。
各段階の出力とSYSCON終了、プロセスの終了コードを検査する。制御スクリプト自体の5件のテストは
`make linux-console-test`で実行でき、通常CIと`make all`にも含める。
この試験で、旧ユーザランドがRV32で無効な`wait4`を使い、子の終了前にシェルへ戻る問題も検出した。
`spawn.S`は`waitid(P_PID, ..., WEXITED)`へ変更し、`EINTR`時は同じPIDを待ち直す。

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
cycle/bitの3設定すべて成功した。これらはboot ROMの結合試験であり、Linuxの実機結果は
以下に別途記録する。LCD bootlogとGUIは未実装である。

UART変更後の既存Linuxシミュレーションも`/init`、Mandelbrot、donut 24 frame、SYSCON poweroffまで
成功した（853,919,151 cycle、300,378,013 retire）。これはLinux用UART/DDRの実機試験とは別の回帰である。

2026-10-12、`20261012-135920-LinuxBoot`でLinux 6.12の`/init`、`veryl$`プロンプト、
ホストから送った`help`への全4行の応答を実機で確認した。JTAG書込み・転送・起動・応答取得の
所要時間は352.067秒。カーネルログのRAMは128 MiB、CLINTは1 MHz、UARTは115200設定である。
終了後のLCD回路への復帰とUART検査も成功した。

この試験のImage SHA256は`88d321a24a8ad2f7e0bdd91236d202d699776c3e43b59b42b71c6e0634cee102`、
DTBは`83dc6c373754a88d8834f05b59e4fbf988860fe1d64bc3a79999a497fa5a8d5d`、
packageは`ce16f74234c9643e8e55553ff6b470ccf9786b238b6e6c15e84579cbbf6dd420`。
bitstreamは前述の`12c57e5d...`を使用した。

起動確認までに、DTBを無視する組込みコマンドラインの強制設定と、送信能力を超える
UART FIFO設定を修正した。前者は通常コンソールへの切替え後の通信速度不一致、後者は
TTY初期化後の文字欠落として実機で検出した。いずれもFPGA回路の変更は不要であった。

`waitid`へ修正した最終版のシミュレーション回帰は、標準DTB・64 MiB RAMで`/init`、Mandelbrot、
donut 24 frame、各プロセス終了後のシェル復帰、SYSCON poweroffまで成功した
（458,809,329 cycle、156,329,725 retire、`sim/linux-waitid-regression.log`）。
旧Imageでは新しい検査がdonut完了後のプロンプト待ちでtimeoutし、修正後は同じ検査を通過した。
実機DTB・128 MiB RAMのモデルでも同じ全段階が成功した
（586,751,939 cycle、200,501,262 retire、`sim/linux-tang-waitid-regression.log`）。
このモデル試験はCPU・カーネル・DTBの回帰であり、実DDR PHYやUARTのbit timingの検証は含まない。

最終版は`20261012-140541-LinuxBoot`で再度実機へ転送し、`/init`とUARTシェルへの到達後に
ホストから`donut`を送信した。別プロセスのUART描画が24 frame完了し、
`donut: 24 frames rendered`を取得した。所要483.533秒（JTAG書込み・転送・起動・描画を含む）。
実機でのMandelbrot、poweroff、LinuxからのLCD描画はこの試験の対象外である。
`20261012-141344-LcdSoc`で既知のLCD回路へ復帰し、UART検査も成功した。

最終ImageのSHA256は`d2f56fbd81a952d1b4f7f46beb53b5d77455b2e62412db85d78d0f3bd2883be2`、
packageは`a297a8e54ce5a3c83baac30d7c6d4dc98b7de3ad3fedf0d753fca4ad23c81139`。
DTB・bitstreamは上記の実機`help`試験と同じである。
