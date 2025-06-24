{
  description = "Home Manager configuration of kamana";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-darwin";
      overlays = [
        (final: prev: {
          bitwarden-cli = prev.bitwarden-cli.overrideAttrs (oldAttrs: {
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.llvmPackages_18.stdenv.cc ];
            stdenv = prev.llvmPackages_18.stdenv;
          });
        })
      ];
      pkgs = import nixpkgs {
        inherit system;
        overlays = overlays;
        config = {
          allowUnfreePredicate =
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "claude-code"
              "obsidian"
              "raycast"
              "tableplus"
              "windsurf"
            ];
        };
      };
    in
    {
      homeConfigurations.kamana = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          inherit inputs;
          inherit system;
        };

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
