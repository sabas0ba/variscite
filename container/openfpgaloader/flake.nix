{
  description = "Pinned Windows openFPGALoader comparison for Tang Primer 20K";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/597283ad8aa0b331c788e97c4c262d58877074ef";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      cross = pkgs.pkgsCross.mingwW64;
      source = pkgs.fetchzip {
        url = "https://github.com/trabucayre/openFPGALoader/archive/85be4fa02b2dd6a83716d7dfac3d25bbd260ff7b.tar.gz";
        sha256 = "00wbf7z5f55422fmqczxc6f7a2lmr52m1qx8m3ky5gl006rkf0sm";
      };
      ftdi =
        (cross.libftdi1.override {
          cppSupport = false;
          pythonSupport = false;
          docSupport = false;
        }).overrideAttrs
          (old: {
            # Neither EEPROM tools nor Python bindings are used by the programmer.
            buildInputs = [ ];
            patches = [ ];
            cmakeFlags = old.cmakeFlags ++ [
              "-DFTDI_EEPROM=OFF"
              "-DEXAMPLES=OFF"
            ];
            preFixup = "";
            doInstallCheck = false;
          });
      mkLoader =
        {
          pageBytes,
          fixReadBounds ? false,
          slowFlash ? false,
          smallReads ? false,
        }:
        cross.stdenv.mkDerivation {
          pname = "openfpgaloader-page${toString pageBytes}${pkgs.lib.optionalString fixReadBounds "-bounds"}${pkgs.lib.optionalString slowFlash "-1mhz"}${pkgs.lib.optionalString smallReads "-read128"}";
          version = "1.1.1";
          src = source;
          strictDeps = true;
          patches = pkgs.lib.optional fixReadBounds ./gw2a-read-bounds.patch;
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.pkg-config
          ];
          buildInputs = [
            ftdi
            cross.libusb1
            cross.zlib
          ];
          postPatch =
            pkgs.lib.optionalString (pageBytes == 128) ''
              substituteInPlace src/spiFlash.cpp \
                --replace-fail 'size = (addr + 256 > len)?(len-addr) : 256;' \
                               'size = (addr + 128 > len)?(len-addr) : 128;' \
                --replace-fail 'size = (addr + 256 > sec_len) ? (sec_len - addr) : 256;' \
                               'size = (addr + 128 > sec_len) ? (sec_len - addr) : 128;'
            ''
            + pkgs.lib.optionalString slowFlash ''
              substituteInPlace src/gowin.cpp \
                --replace-fail '_jtag->setClkFreq(10000000);' '_jtag->setClkFreq(1000000);'
            '';
          postConfigure = pkgs.lib.optionalString smallReads ''
            substituteInPlace ../src/gowin.cpp \
              --replace-fail 'spiFlash.verify(offset, data, length / 8, 256)' 'spiFlash.verify(offset, data, length / 8, 128)' \
              --replace-fail 'flash.dump(_filename, base_addr, len, 256)' 'flash.dump(_filename, base_addr, len, 128)'
          '';
          cmakeFlags = [
            "-DWINDOWS_CROSSCOMPILE=ON"
            "-DCROSS_COMPILE_DEPS=OFF"
            "-DWINDOWS_STATIC_ZLIB=OFF"
            "-DENABLE_CMSISDAP=OFF"
          ];
          # Bundle the runtime DLLs so host tool installations cannot change the comparison.
          postInstall = ''
            for dependency in ${ftdi} ${cross.libusb1} ${cross.zlib} ${pkgs.lib.getLib cross.stdenv.cc.cc} ${cross.windows.mcfgthreads}; do
              find "$dependency" -name '*.dll' -exec install -m755 -t "$out/bin" {} +
            done
            mkdir -p "$out/share/source"
            cp ../src/spiFlash.cpp "$out/share/source/"
            cp ../src/gowin.cpp "$out/share/source/"
          '';
        };
    in
    {
      checks.x86_64-linux.gw2a-bounds =
        pkgs.runCommand "gw2a-bounds-test"
          {
            nativeBuildInputs = [ pkgs.gcc ];
            inherit source;
            fixture = ./test-gw2a-spi.cpp;
            boundsPatch = ./gw2a-read-bounds.patch;
          }
          ''
            bash ${./check-gw2a-bounds.sh}
          '';
      packages.x86_64-linux = {
        page256 = mkLoader { pageBytes = 256; };
        page128 = mkLoader { pageBytes = 128; };
        page128-bounds = mkLoader {
          pageBytes = 128;
          fixReadBounds = true;
        };
        page128-bounds-1mhz = mkLoader {
          pageBytes = 128;
          fixReadBounds = true;
          slowFlash = true;
        };
        page128-bounds-read128 = mkLoader {
          pageBytes = 128;
          fixReadBounds = true;
          smallReads = true;
        };
        exportTools = pkgs.buildEnv {
          name = "openfpgaloader-export-tools";
          paths = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.diffutils
          ];
        };
      };
    };
}
