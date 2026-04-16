{
  description = "Nick's home-manager modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    llm-agents.url = "github:numtide/llm-agents.nix";
    serena.url = "github:oraios/serena";
    sesame.url = "git+ssh://forgejo@liveoak:2222/Nick/sesame.git";
    devenv.url = "github:cachix/devenv/v2.0.6";
    worktrunk.url = "github:max-sixty/worktrunk/v0.38.0";
    zmx.url = "github:neurosnap/zmx";
  };

  outputs =
    { self, ... }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      forEachSupportedSystem =
        f:
        inputs.nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            inherit system;
            pkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
        );
    in
    {
      homeModules = {
        # Default: imports all modules, defines shared options. Modules are imported but nothing enabled by default.
        default = import ./modules { inherit inputs; };

        # Bundles: import all modules + set enable flags
        workstation = {
          imports = [
            (import ./modules { inherit inputs; })
            ./bundles/workstation.nix
          ];
        };
        server = {
          imports = [
            (import ./modules { inherit inputs; })
            ./bundles/server.nix
          ];
        };

        # Individual modules (for advanced users who want granular control)
        ai = import ./modules/ai.nix { inherit inputs; };
        applications = import ./modules/applications.nix { inherit inputs; };
        base = import ./modules/base.nix;
        dev = import ./modules/dev.nix { inherit inputs; };
        fonts = import ./modules/fonts.nix;
        git = import ./modules/git.nix;
        hammerspoon = import ./modules/hammerspoon.nix;
        media-processing = import ./modules/media-processing.nix;
        neovim = import ./modules/neovim.nix { inherit inputs; };
        scripts = import ./modules/scripts.nix;
        secrets = import ./modules/secrets.nix;
        shell = import ./modules/shell.nix { inherit inputs; };
        terminal = import ./modules/terminal.nix { inherit inputs; };
        utils = import ./modules/utils.nix { inherit inputs; };
        zellij = import ./modules/zellij.nix { inherit inputs; };
      };

      devShells = forEachSupportedSystem (
        { pkgs, system }:
        {
          default = pkgs.mkShellNoCC {
            packages = [
              self.formatter.${system}
            ];
          };
        }
      );

      formatter = forEachSupportedSystem ({ pkgs, ... }: pkgs.nixfmt-rfc-style);
    };
}
