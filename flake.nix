{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    # Zephyr RTOS (ZMK fork) - pins requirements.txt for pythonEnv
    zephyr.url = "github:zmkfirmware/zephyr/v3.5.0+zmk-fixes";
    zephyr.flake = false;

    # Zephyr SDK and Python environment
    zephyr-nix.url = "github:urob/zephyr-nix";
    zephyr-nix.inputs.zephyr.follows = "zephyr";
    zephyr-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, zephyr-nix, ... }: let
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      zephyr = zephyr-nix.packages.${system};
    in {
      default = pkgs.mkShellNoCC {
        packages = [
          # Zephyr toolchain
          zephyr.pythonEnv
          (zephyr.sdk-0_16.override { targets = ["arm-zephyr-eabi"]; })

          # Build tools
          pkgs.cmake
          pkgs.dtc
          pkgs.gcc
          pkgs.ninja

          # Workflow tools
          pkgs.just
          pkgs.yq
        ];

        env = {
          PYTHONPATH = "${zephyr.pythonEnv}/${zephyr.pythonEnv.sitePackages}";
        };

        shellHook = ''
          export ZMK_BUILD_DIR=$(pwd)/.build
          export ZMK_SRC_DIR=$(pwd)/zmk/app
        '';
      };
    });
  };
}
