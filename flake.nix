{
  description = "rv32ima_veryl: Veryl による RV32IMA_Zicsr コアの開発環境";

  inputs = {
    # 入力はリビジョンで固定する (dotfiles と同一の nixos-26.05 リビジョン)。
    nixpkgs.url = "github:NixOS/nixpkgs/597283ad8aa0b331c788e97c4c262d58877074ef";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config = { };
              overlays = [ ];
            }
          )
        );
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.veryl
            pkgs.verilator
            pkgs.pkgsCross.riscv32-embedded.buildPackages.gcc
            pkgs.gnumake
            pkgs.python3
          ];
          # riscv-tests の Makefile と本リポジトリの RISCV_PREFIX を合わせる。
          # nixpkgs のクロス GCC は riscv32-none-elf- プレフィックスのため、
          # make 実行時に RISCV_PREFIX=riscv32-none-elf- を指定する。
          shellHook = ''
            export DOTFILES_ENV=nix-develop
          '';
        };
      });
    };
}
